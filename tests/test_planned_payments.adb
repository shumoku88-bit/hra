with Ada.Text_IO;          use Ada.Text_IO;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Strings.Fixed;     use Ada.Strings.Fixed;
with ALedger.Account;
with ALedger.Dates;
with ALedger.Journal;
with ALedger.Ledger;
with ALedger.Money;
with ALedger.Plan;
with ALedger.Planned_Payments;
with ALedger.Planned_Payments_Render;

procedure Test_Planned_Payments is
   use type ALedger.Planned_Payments.Temporal_Status;
   use type ALedger.Planned_Payments.Admission_Status;

   Passed_Count : Natural := 0;
   Failed_Count : Natural := 0;

   procedure Assert (Condition : Boolean; Test_Name : String) is
   begin
      if Condition then
         Put_Line ("[PASS] " & Test_Name);
         Passed_Count := Passed_Count + 1;
      else
         Put_Line ("[FAIL] " & Test_Name);
         Failed_Count := Failed_Count + 1;
      end if;
   end Assert;

   function D (S : String) return ALedger.Dates.Date is
      Val    : ALedger.Dates.Date;
      Status : ALedger.Dates.Date_Status;
   begin
      if not ALedger.Dates.Parse (S, Val, Status) then
         raise Program_Error with "Invalid date in test: " & S;
      end if;
      return Val;
   end D;

   procedure Register
     (Registry : in out ALedger.Account.Account_Registry;
      Name     : String;
      Kind     : ALedger.Account.Account_Type)
   is
      Status : ALedger.Account.Registry_Status;
   begin
      if not ALedger.Account.Register_Account
        (Registry,
         ALedger.Account.Declare_Account
           (ALedger.Account.Make_Account (Name), Kind),
         Status)
      then
         raise Program_Error with "test registry admission failed: " & Name;
      end if;
   end Register;

   function Contains
     (Value : ALedger.Planned_Payments.Observation;
      ID    : String) return Boolean
   is
   begin
      for Payment of Value.Payments loop
         if ALedger.Plan.Text (Payment.ID) = ID then
            return True;
         end if;
      end loop;
      return False;
   end Contains;

   Plan_Source : constant String :=
     "2026-08-10 Overdue bill" & ASCII.LF &
     "    ; plan-id: plan-overdue" & ASCII.LF &
     "    expenses:rent       1000 JPY" & ASCII.LF &
     "    assets:cash        -1000 JPY" & ASCII.LF & ASCII.LF &
     "2026-08-15 Due today" & ASCII.LF &
     "    ; plan-id: plan-today" & ASCII.LF &
     "    expenses:food        250 JPY" & ASCII.LF &
     "    assets:cash         -250 JPY" & ASCII.LF & ASCII.LF &
     "2026-08-20 Future bill" & ASCII.LF &
     "    ; plan-id: plan-future" & ASCII.LF &
     "    expenses:food        500 JPY" & ASCII.LF &
     "    assets:cash         -500 JPY" & ASCII.LF & ASCII.LF &
     "2026-08-18 Completed bill" & ASCII.LF &
     "    ; plan-id: plan-completed" & ASCII.LF &
     "    expenses:food        300 JPY" & ASCII.LF &
     "    assets:cash         -300 JPY" & ASCII.LF & ASCII.LF &
     "2026-08-19 Cancelled bill" & ASCII.LF &
     "    ; plan-id: plan-cancelled" & ASCII.LF &
     "    ; cancelled-on: 2026-08-14" & ASCII.LF &
     "    expenses:food        400 JPY" & ASCII.LF &
     "    assets:cash         -400 JPY" & ASCII.LF & ASCII.LF &
     "2026-08-22 Old subscription" & ASCII.LF &
     "    ; plan-id: plan-old" & ASCII.LF &
     "    ; superseded-on: 2026-08-13" & ASCII.LF &
     "    ; superseded-by: plan-new" & ASCII.LF &
     "    expenses:subs        600 JPY" & ASCII.LF &
     "    assets:cash         -600 JPY" & ASCII.LF & ASCII.LF &
     "2026-08-25 New subscription" & ASCII.LF &
     "    ; plan-id: plan-new" & ASCII.LF &
     "    expenses:subs        700 JPY" & ASCII.LF &
     "    assets:cash         -700 JPY" & ASCII.LF & ASCII.LF &
     "2026-08-16 Savings target" & ASCII.LF &
     "    ; plan-id: plan-savings" & ASCII.LF &
     "    assets:savings       200 JPY" & ASCII.LF &
     "    assets:cash         -200 JPY" & ASCII.LF;

   Actual_Source : constant String :=
     "2026-08-14 Completed bill actual" & ASCII.LF &
     "    ; plan-id: plan-completed" & ASCII.LF &
     "    expenses:food        300 JPY" & ASCII.LF &
     "    assets:cash         -300 JPY" & ASCII.LF;

   Duplicate_Source : constant String :=
     "2026-08-20 First" & ASCII.LF &
     "    ; plan-id: duplicate-plan" & ASCII.LF &
     "    expenses:food        100 JPY" & ASCII.LF &
     "    assets:cash         -100 JPY" & ASCII.LF & ASCII.LF &
     "2026-08-21 Second" & ASCII.LF &
     "    ; plan-id: duplicate-plan" & ASCII.LF &
     "    expenses:food        200 JPY" & ASCII.LF &
     "    assets:cash         -200 JPY" & ASCII.LF;

   Multi_Post_Source : constant String :=
     "2026-08-20 Shared purchase" & ASCII.LF &
     "    ; plan-id: multi-post" & ASCII.LF &
     "    expenses:food        600 JPY" & ASCII.LF &
     "    expenses:subs        400 JPY" & ASCII.LF &
     "    assets:cash        -1000 JPY" & ASCII.LF;

   Registry     : ALedger.Account.Account_Registry := ALedger.Account.Empty_Registry;
   Plans        : ALedger.Ledger.Ledger;
   Actual       : ALedger.Ledger.Ledger;
   Empty_Actual : ALedger.Ledger.Ledger;
   Duplicate    : ALedger.Ledger.Ledger;
   Multi_Post   : ALedger.Ledger.Ledger;
   Error_Msg    : Unbounded_String;
   Result       : ALedger.Planned_Payments.Observation;
   Diag         : ALedger.Planned_Payments.Admission_Diagnostic;

begin
   Put_Line ("--- Testing ALedger.Planned_Payments ---");

   Register (Registry, "assets:cash", ALedger.Account.Asset);
   Register (Registry, "assets:savings", ALedger.Account.Asset);
   Register (Registry, "expenses:rent", ALedger.Account.Expense);
   Register (Registry, "expenses:food", ALedger.Account.Expense);
   Register (Registry, "expenses:subs", ALedger.Account.Expense);

   Assert
     (ALedger.Journal.Parse_Journal_Text (Plan_Source, Plans, Error_Msg),
      "Setup: parse Plan Journal accounting facts");
   Assert
     (ALedger.Journal.Parse_Journal_Text (Actual_Source, Actual, Error_Msg),
      "Setup: parse Actual Journal accounting facts");
   Assert
     (ALedger.Journal.Parse_Journal_Text ("", Empty_Actual, Error_Msg),
      "Setup: parse empty Actual Journal");

   Assert
     (ALedger.Planned_Payments.Observe
        (Plans, Plan_Source, Actual, Actual_Source, Registry,
         D ("2026-08-15"), Result, Diag),
      "Observe open Planned Payments from explicit lifecycle evidence");
   Assert
     (Natural (Result.Payments.Length) = 4,
      "Open payment projection keeps four binary outgoing Plans");
   Assert
     (Contains (Result, "plan-overdue")
        and then Contains (Result, "plan-today")
        and then Contains (Result, "plan-future")
        and then Contains (Result, "plan-new"),
      "Open projection preserves expected Plan identities");
   Assert
     (not Contains (Result, "plan-completed")
        and then not Contains (Result, "plan-cancelled")
        and then not Contains (Result, "plan-old"),
      "Completion, cancellation, and supersession close Plans explicitly");
   Assert
     (not Contains (Result, "plan-savings"),
      "Asset-to-Asset target is recognized as a non-payment Plan");
   Assert
     (Result.Payments.Element (1).Timing = ALedger.Planned_Payments.Overdue
        and then Result.Payments.Element (2).Timing = ALedger.Planned_Payments.Due_Today
        and then Result.Payments.Element (3).Timing = ALedger.Planned_Payments.Upcoming,
      "Temporal status is derived from observation day without changing lifecycle");
   Assert
     (ALedger.Account.Name (Result.Payments.Element (1).Source) = "assets:cash"
        and then ALedger.Account.Name (Result.Payments.Element (1).Destination) = "expenses:rent"
        and then ALedger.Money.Render_Quantity (Result.Payments.Element (1).Amt.Val) = "1,000",
      "Binary outgoing projection preserves source, destination, and exact amount");

   declare
      Text : constant String := ALedger.Planned_Payments_Render.Render (Result);
   begin
      Assert
        (Index (Text, "Planned Payments") > 0
           and then Index (Text, "plan-overdue") > 0
           and then Index (Text, "OVERDUE") > 0,
         "Human renderer consumes semantic Planned Payments result");
   end;

   Assert
     (ALedger.Journal.Parse_Journal_Text (Duplicate_Source, Duplicate, Error_Msg),
      "Setup: parse duplicate Plan Journal accounting facts");
   Assert
     (not ALedger.Planned_Payments.Observe
        (Duplicate, Duplicate_Source, Empty_Actual, "", Registry,
         D ("2026-08-15"), Result, Diag)
        and then Diag.Status = ALedger.Planned_Payments.Duplicate_Plan_Id,
      "Reject duplicate durable Plan identity");

   Assert
     (ALedger.Journal.Parse_Journal_Text (Multi_Post_Source, Multi_Post, Error_Msg),
      "Setup: parse valid multi-post outgoing Plan");
   Assert
     (not ALedger.Planned_Payments.Observe
        (Multi_Post, Multi_Post_Source, Empty_Actual, "", Registry,
         D ("2026-08-15"), Result, Diag)
        and then Diag.Status = ALedger.Planned_Payments.Plan_Report_Requires_Binary_Outgoing,
      "Keep valid multi-post Plan distinct from narrower Planned Payments projection");

   Put_Line
     (Natural'Image (Passed_Count) & " passed, " &
      Natural'Image (Failed_Count) & " failed");

   if Failed_Count > 0 then
      raise Program_Error with "planned payment tests failed";
   end if;
end Test_Planned_Payments;
