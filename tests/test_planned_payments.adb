with Ada.Text_IO;          use Ada.Text_IO;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Strings.Fixed;     use Ada.Strings.Fixed;
with HRA.Account;
with HRA.Actual_Admission;
with HRA.Dates;
with HRA.Journal;
with HRA.Journal_Evidence;
with HRA.Ledger;
with HRA.Money;
with HRA.Plan;
with HRA.Plan_Admission;
with HRA.Plan_Completion;
with HRA.Plan_Temporal_Observation;
with HRA.Planned_Payments;
with HRA.Planned_Payments_Render;

procedure Test_Planned_Payments is
   use type HRA.Planned_Payments.Temporal_Status;
   use type HRA.Planned_Payments.Projection_Status;

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

   function D (S : String) return HRA.Dates.Date is
      Val    : HRA.Dates.Date;
      Status : HRA.Dates.Date_Status;
   begin
      if not HRA.Dates.Parse (S, Val, Status) then
         raise Program_Error with "Invalid date in test: " & S;
      end if;
      return Val;
   end D;

   procedure Register
     (Registry : in out HRA.Account.Account_Registry;
      Name     : String;
      Kind     : HRA.Account.Account_Type)
   is
      Status : HRA.Account.Registry_Status;
   begin
      if not HRA.Account.Register_Account
        (Registry,
         HRA.Account.Declare_Account
           (HRA.Account.Make_Account (Name), Kind),
         Status)
      then
         raise Program_Error with "test registry admission failed: " & Name;
      end if;
   end Register;

   function Contains
     (Value : HRA.Planned_Payments.Observation;
      ID    : String) return Boolean
   is
   begin
      for Payment of Value.Payments loop
         if HRA.Plan.Text (Payment.ID) = ID then
            return True;
         end if;
      end loop;
      return False;
   end Contains;

   function Open_Plans
     (Plan_Source   : String;
      Actual_Source : String;
      As_Of         : HRA.Dates.Date)
      return HRA.Plan_Temporal_Observation.Open_Plan_Vectors.Vector
   is
      Plan_Ledger, Actual_Ledger : HRA.Ledger.Ledger;
      Plan_Evidence, Actual_Evidence : HRA.Journal_Evidence.Journal_Evidence;
      Parse_Error : Unbounded_String;
      Evidence_Diag : HRA.Journal_Evidence.Evidence_Diagnostic;
      Plans : HRA.Plan_Admission.Plan_Journal;
      Plan_Diag : HRA.Plan_Admission.Admission_Diagnostic;
      Actuals : HRA.Actual_Admission.Actual_Observation;
      Actual_Diag : HRA.Actual_Admission.Admission_Diagnostic;
      Completions : HRA.Plan_Completion.Completion_Relations;
      Completion_Diag : HRA.Plan_Completion.Admission_Diagnostic;
   begin
      if not HRA.Journal.Parse_Journal_Text
        (Plan_Source, Plan_Ledger, Parse_Error)
        or else not HRA.Journal_Evidence.Extract
          (Plan_Source, Plan_Ledger, Plan_Evidence, Evidence_Diag)
        or else not HRA.Plan_Admission.Admit
          (Plan_Ledger, Plan_Evidence, Plans, Plan_Diag)
        or else not HRA.Journal.Parse_Journal_Text
          (Actual_Source, Actual_Ledger, Parse_Error)
        or else not HRA.Journal_Evidence.Extract
          (Actual_Source, Actual_Ledger, Actual_Evidence, Evidence_Diag)
        or else not HRA.Actual_Admission.Admit
          (Actual_Ledger, Actual_Evidence, Actuals, Actual_Diag)
        or else not HRA.Plan_Completion.Admit
          (Plans, Actuals, Completions, Completion_Diag)
      then
         raise Program_Error with "temporal Planned Payments setup failed";
      end if;

      return HRA.Plan_Temporal_Observation.Observe
        (Plans, Completions, As_Of).Open_Plans;
   end Open_Plans;

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

   Multi_Post_Source : constant String :=
     "2026-08-20 Shared purchase" & ASCII.LF &
     "    ; plan-id: multi-post" & ASCII.LF &
     "    expenses:food        600 JPY" & ASCII.LF &
     "    expenses:subs        400 JPY" & ASCII.LF &
     "    assets:cash        -1000 JPY" & ASCII.LF;

   Registry  : HRA.Account.Account_Registry := HRA.Account.Empty_Registry;
   Result    : HRA.Planned_Payments.Observation;
   Diag      : HRA.Planned_Payments.Projection_Diagnostic;
   As_Of     : constant HRA.Dates.Date := D ("2026-08-15");

begin
   Put_Line ("--- Testing HRA.Planned_Payments ---");

   Register (Registry, "assets:cash", HRA.Account.Asset);
   Register (Registry, "assets:savings", HRA.Account.Asset);
   Register (Registry, "expenses:rent", HRA.Account.Expense);
   Register (Registry, "expenses:food", HRA.Account.Expense);
   Register (Registry, "expenses:subs", HRA.Account.Expense);

   declare
      Plans : constant HRA.Plan_Temporal_Observation.Open_Plan_Vectors.Vector :=
        Open_Plans (Plan_Source, Actual_Source, As_Of);
   begin
      Assert
        (HRA.Planned_Payments.Project
           (Plans, Registry, As_Of, Result, Diag),
         "Project Planned Payments from admitted temporal open Plans");
   end;

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
     (Result.Payments.Element (1).Timing = HRA.Planned_Payments.Overdue
        and then Result.Payments.Element (2).Timing = HRA.Planned_Payments.Due_Today
        and then Result.Payments.Element (3).Timing = HRA.Planned_Payments.Upcoming,
      "Temporal status is derived from observation day without changing lifecycle");
   Assert
     (HRA.Account.Name (Result.Payments.Element (1).Source) = "assets:cash"
        and then HRA.Account.Name (Result.Payments.Element (1).Destination) = "expenses:rent"
        and then HRA.Money.Render_Quantity (Result.Payments.Element (1).Amt.Val) = "1,000",
      "Binary outgoing projection preserves source, destination, and exact amount");

   declare
      Text : constant String := HRA.Planned_Payments_Render.Render (Result);
   begin
      Assert
        (Index (Text, "Planned Payments") > 0
           and then Index (Text, "plan-overdue") > 0
           and then Index (Text, "OVERDUE") > 0,
         "Human renderer consumes semantic Planned Payments result");
   end;

   declare
      Plans : constant HRA.Plan_Temporal_Observation.Open_Plan_Vectors.Vector :=
        Open_Plans (Multi_Post_Source, "", As_Of);
   begin
      Assert
        (not HRA.Planned_Payments.Project
           (Plans, Registry, As_Of, Result, Diag)
         and then Diag.Status =
           HRA.Planned_Payments.Plan_Report_Requires_Binary_Outgoing,
         "Keep valid multi-post Plan distinct from narrower Planned Payments projection");
   end;

   Put_Line
     (Natural'Image (Passed_Count) & " passed, " &
      Natural'Image (Failed_Count) & " failed");

   if Failed_Count > 0 then
      raise Program_Error with "planned payment tests failed";
   end if;
end Test_Planned_Payments;
