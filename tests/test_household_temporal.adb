with Ada.Directories; use Ada.Directories;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO; use Ada.Text_IO;
with ALedger.Dates;
with ALedger.Envelope;
with ALedger.Household;
with ALedger.Household_Envelope_Change;
with ALedger.Household_Temporal;
with ALedger.Money;

procedure Test_Household_Temporal is
   use type ALedger.Dates.Date;
   use type ALedger.Household_Envelope_Change.Baseline_Status;
   use type ALedger.Household_Temporal.Observe_Status;
   use type ALedger.Money.Quantity;

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
      Value  : ALedger.Dates.Date;
      Status : ALedger.Dates.Date_Status;
   begin
      if not ALedger.Dates.Parse (S, Value, Status) then
         raise Program_Error with "invalid test date: " & S;
      end if;
      return Value;
   end D;

   Tmp_Dir : constant String := "/tmp/aledger_test_household_temporal";
   Paths   : constant ALedger.Household.Source_Paths :=
     ALedger.Household.Resolve_Source_Paths (Tmp_Dir);
   State   : ALedger.Household.Household_State;
   Err     : Unbounded_String;
   F       : File_Type;
   JPY     : constant ALedger.Money.Commodity :=
     ALedger.Money.Make_Commodity ("JPY");

   Change : ALedger.Household_Envelope_Change.Change_Observation;
   Diag   : ALedger.Household_Temporal.Observe_Diagnostic;

begin
   Put_Line ("--- Testing Household temporal application composition ---");

   if Exists (Tmp_Dir) then
      Delete_Tree (Tmp_Dir);
   end if;
   Create_Directory (Tmp_Dir);

   Create (F, Out_File, To_String (Paths.Accounts_Journal));
   Put_Line (F, "account assets:wallet");
   Put_Line (F, "  ; type: Asset");
   Put_Line (F, "account expenses:coffee");
   Put_Line (F, "  ; type: Expense");
   Put_Line (F, "account income:salary");
   Put_Line (F, "  ; type: Income");
   Put_Line (F, "account budget:coffee");
   Put_Line (F, "  ; type: Budget");
   Put_Line (F, "account budget:unassigned");
   Put_Line (F, "  ; type: Budget");
   Put_Line (F, "account budget:opening");
   Put_Line (F, "  ; type: Budget");
   Close (F);

   Create (F, Out_File, To_String (Paths.Actual_Journal));
   Put_Line (F, "2026-08-01 Salary");
   Put_Line (F, "    assets:wallet         10000 JPY");
   Put_Line (F, "    income:salary        -10000 JPY");
   New_Line (F);
   Put_Line (F, "2026-08-13 Coffee Purchase");
   Put_Line (F, "    expenses:coffee         500 JPY");
   Put_Line (F, "    assets:wallet           -500 JPY");
   Close (F);

   Create (F, Out_File, To_String (Paths.Plan_Journal));
   Put_Line (F, "2026-09-01 Next Salary");
   Put_Line (F, "    ; plan-id: plan-next-salary");
   Put_Line (F, "    assets:wallet         10000 JPY");
   Put_Line (F, "    income:salary        -10000 JPY");
   Close (F);

   Create (F, Out_File, To_String (Paths.Budget_Journal));
   Put_Line (F, "2026-08-01 Clean Envelope epoch");
   Put_Line (F, "    budget:opening          0 JPY");
   Put_Line (F, "    budget:unassigned       0 JPY");
   Close (F);

   Create (F, Out_File, To_String (Paths.Budget_TOML));
   Put_Line (F, "[[backing-pools]]");
   Put_Line (F, "id = ""liquid""");
   Put_Line (F, "asset-accounts = [""assets:wallet""]");
   Put_Line (F, "[[envelopes]]");
   Put_Line (F, "id = ""coffee""");
   Put_Line (F, "label = ""Coffee""");
   Put_Line (F, "pacing = ""daily""");
   Put_Line (F, "backing-pool = ""liquid""");
   Close (F);

   Create (F, Out_File, To_String (Paths.Household_TOML));
   Put_Line (F, "[cycle]");
   Put_Line (F, "mode = ""income-anchor""");
   Put_Line (F, "income-account = ""income:salary""");
   Put_Line (F, "[money]");
   Put_Line (F, "primary-commodity = ""JPY""");
   Put_Line (F, "[budget]");
   Put_Line (F, "opening-accounts = [""budget:opening""]");
   Put_Line (F, "unassigned-accounts = [""budget:unassigned""]");
   Put_Line (F, "[[budget.envelopes]]");
   Put_Line (F, "id = ""coffee""");
   Put_Line (F, "allocation-account = ""budget:coffee""");
   Put_Line (F, "[envelope-history]");
   Put_Line (F, "identities = [""coffee""]");
   Put_Line (F, "[[envelope-history.expense-routing]]");
   Put_Line (F, "effective-from = ""initial""");
   Put_Line (F, "expense-account = ""expenses:coffee""");
   Put_Line (F, "route = ""managed""");
   Put_Line (F, "target = ""coffee""");
   Put_Line (F, "note = ""temporal test routing""");
   Close (F);

   Create (F, Out_File, To_String (Paths.Report_TOML));
   Put_Line (F, "[presentation.amounts]");
   Put_Line (F, "negative-style = ""parentheses""");
   Put_Line (F, "[reports.trial-balance]");
   Put_Line (F, "as-of = ""latest""");
   Put_Line (F, "[reports.balance-sheet]");
   Put_Line (F, "as-of = ""latest""");
   Put_Line (F, "[reports.profit-and-loss]");
   Put_Line (F, "from = ""beginning""");
   Put_Line (F, "through = ""latest""");
   Put_Line (F, "[reports.daily-flow]");
   Put_Line (F, "from = ""beginning""");
   Put_Line (F, "through = ""latest""");
   Put_Line (F, "max-date-columns = 7");
   Put_Line (F, "[reports.monthly-accounts]");
   Put_Line (F, "from = ""beginning""");
   Put_Line (F, "through = ""latest""");
   Put_Line (F, "[reports.recent-transactions]");
   Put_Line (F, "through = ""latest""");
   Put_Line (F, "count = 10");
   Close (F);

   Create (F, Out_File, To_String (Paths.Issues_TSV));
   Put_Line (F, "issue_id" & ASCII.HT & "status");
   Close (F);

   Assert
     (ALedger.Household.Load_Canonical_Household (Tmp_Dir, State, Err),
      "Setup: admit complete synthetic Household");

   Assert
     (ALedger.Household_Temporal.Observe_Envelope_Change
        (D ("2026-08-15"),
         (Kind => ALedger.Household_Envelope_Change.No_Previous_Observation),
         (Kind => ALedger.Household_Envelope_Change.Cycle_Start),
         State,
         Change,
         Diag)
      and then Diag.Status = ALedger.Household_Temporal.Success,
      "Cycle Start request composes directly from admitted Household state");

   Assert
     (Change.From_Date = D ("2026-08-01")
        and then Change.Through_Date = D ("2026-08-15"),
      "Temporal application retains resolved Cycle Start interval");
   Assert
     (Natural (Change.Lines.Length) = 1
        and then ALedger.Envelope.Image (Change.Lines.Element (1).Env_Id) = "coffee",
      "Temporal application preserves current Envelope identity and order");
   Assert
     (ALedger.Money.Lookup_Balance
        (Change.Lines.Element (1).Consumption_Charges, JPY) = 500.0,
      "Cycle-start Change observes 500 JPY gross coffee consumption");
   Assert
     (ALedger.Money.Lookup_Balance
        (Change.Lines.Element (1).Remaining, JPY) = -500.0,
      "Cycle-start Change observes resulting -500 JPY Remaining movement");

   Assert
     (ALedger.Household_Temporal.Observe_Envelope_Change
        (D ("2026-08-15"),
         (Kind             => ALedger.Household_Envelope_Change.Previous_Observation_Available,
          Observed_Through => D ("2026-08-12")),
         (Kind => ALedger.Household_Envelope_Change.Previous_Observation),
         State,
         Change,
         Diag)
      and then Diag.Status = ALedger.Household_Temporal.Success
      and then Change.From_Date = D ("2026-08-12")
      and then ALedger.Money.Lookup_Balance
        (Change.Lines.Element (1).Consumption_Charges, JPY) = 500.0,
      "Previous Observation context is caller supplied and composes through Change");

   Assert
     (not ALedger.Household_Temporal.Observe_Envelope_Change
        (D ("2026-08-15"),
         (Kind => ALedger.Household_Envelope_Change.No_Previous_Observation),
         (Kind => ALedger.Household_Envelope_Change.Previous_Observation),
         State,
         Change,
         Diag)
      and then Diag.Status = ALedger.Household_Temporal.Baseline_Unavailable
      and then Diag.Baseline.Status =
        ALedger.Household_Envelope_Change.Previous_Observation_Unavailable,
      "Missing Previous Observation fails closed without evidence fallback");

   Delete_Tree (Tmp_Dir);

   Put_Line
     (Natural'Image (Passed_Count) & " passed, " &
      Natural'Image (Failed_Count) & " failed");

   if Failed_Count > 0 then
      raise Program_Error with "Household temporal tests failed";
   end if;
end Test_Household_Temporal;
