with Ada.Directories; use Ada.Directories;
with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO; use Ada.Text_IO;
with HRA.Dates;
with HRA.Envelope;
with HRA.Household;
with HRA.Household_Envelope_Change;
with HRA.Household_Envelope_Explanation;
with HRA.Household_Temporal;
with HRA.Money;

procedure Test_Household_Temporal is
   use type HRA.Dates.Date;
   use type HRA.Household_Envelope_Change.Baseline_Status;
   use type HRA.Household_Envelope_Explanation.Explain_Status;
   use type HRA.Household_Temporal.Observe_Status;
   use type HRA.Money.Quantity;

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
      Value  : HRA.Dates.Date;
      Status : HRA.Dates.Date_Status;
   begin
      if not HRA.Dates.Parse (S, Value, Status) then
         raise Program_Error with "invalid test date: " & S;
      end if;
      return Value;
   end D;

   procedure Write_File (Path, Content : String) is
      F : File_Type;
   begin
      Create (F, Out_File, Path);
      Put (F, Content);
      Close (F);
   end Write_File;

   procedure Put_Diagnostic
     (Diag : HRA.Household_Temporal.Observe_Diagnostic)
   is
   begin
      Put_Line
        ("[DIAG] Household temporal status = " &
         HRA.Household_Temporal.Observe_Status'Image (Diag.Status));

      case Diag.Status is
         when HRA.Household_Temporal.Success =>
            null;
         when HRA.Household_Temporal.Current_Observation_Unavailable |
              HRA.Household_Temporal.Earlier_Observation_Unavailable =>
            Put_Line ("[DIAG] observation = " & To_String (Diag.Observation_Error));
         when HRA.Household_Temporal.Baseline_Unavailable =>
            Put_Line
              ("[DIAG] baseline = " &
               HRA.Household_Envelope_Change.Baseline_Status'Image
                 (Diag.Baseline.Status));
         when HRA.Household_Temporal.Current_Explanation_Unavailable |
              HRA.Household_Temporal.Earlier_Explanation_Unavailable =>
            Put_Line
              ("[DIAG] explanation = " &
               HRA.Household_Envelope_Explanation.Explain_Status'Image
                 (Diag.Explanation.Status));
         when HRA.Household_Temporal.Change_Rejected =>
            Put_Line
              ("[DIAG] change = " &
               HRA.Household_Envelope_Change.Change_Status'Image
                 (Diag.Change.Status));
      end case;
   end Put_Diagnostic;

   Tmp_Dir : constant String := "/tmp/hra_test_household_temporal";
   Paths   : constant HRA.Household.Source_Paths :=
     HRA.Household.Resolve_Source_Paths (Tmp_Dir);
   State   : HRA.Household.Household_State;
   Err     : Unbounded_String;
   JPY     : constant HRA.Money.Commodity :=
     HRA.Money.Make_Commodity ("JPY");

   Change : HRA.Household_Envelope_Change.Change_Observation;
   Diag   : HRA.Household_Temporal.Observe_Diagnostic;

begin
   Put_Line ("--- Testing Household temporal application composition ---");

   if Exists (Tmp_Dir) then
      Delete_Tree (Tmp_Dir);
   end if;
   Create_Directory (Tmp_Dir);

   Write_File
     (To_String (Paths.Accounts_Journal),
      "account assets:wallet" & ASCII.LF &
      "  ; type: Asset" & ASCII.LF &
      "account expenses:coffee" & ASCII.LF &
      "  ; type: Expense" & ASCII.LF &
      "account income:salary" & ASCII.LF &
      "  ; type: Income" & ASCII.LF &
      "account budget:coffee" & ASCII.LF &
      "  ; type: Budget" & ASCII.LF &
      "account budget:unassigned" & ASCII.LF &
      "  ; type: Budget" & ASCII.LF &
      "account budget:opening" & ASCII.LF &
      "  ; type: Budget" & ASCII.LF &
      "account budget:rogue" & ASCII.LF &
      "  ; type: Budget" & ASCII.LF);

   Write_File
     (To_String (Paths.Actual_Journal),
      "2026-07-01 Previous Salary" & ASCII.LF &
      "    assets:wallet         10000 JPY" & ASCII.LF &
      "    income:salary        -10000 JPY" & ASCII.LF & ASCII.LF &
      "2026-08-01 Salary" & ASCII.LF &
      "    assets:wallet         10000 JPY" & ASCII.LF &
      "    income:salary        -10000 JPY" & ASCII.LF & ASCII.LF &
      "2026-08-13 Coffee Purchase" & ASCII.LF &
      "    expenses:coffee         500 JPY" & ASCII.LF &
      "    assets:wallet           -500 JPY" & ASCII.LF);

   Write_File
     (To_String (Paths.Plan_Journal),
      "2026-09-01 Next Salary" & ASCII.LF &
      "    ; plan-id: plan-next-salary" & ASCII.LF &
      "    assets:wallet         10000 JPY" & ASCII.LF &
      "    income:salary        -10000 JPY" & ASCII.LF);

   Write_File
     (To_String (Paths.Budget_Journal),
      "2026-08-01 Clean Envelope epoch" & ASCII.LF &
      "    budget:opening          0 JPY" & ASCII.LF &
      "    budget:unassigned       0 JPY" & ASCII.LF);

   Write_File
     (To_String (Paths.Budget_TOML),
      "[[backing-pools]]" & ASCII.LF &
      "id = ""liquid""" & ASCII.LF &
      "asset-accounts = [""assets:wallet""]" & ASCII.LF &
      "[[envelopes]]" & ASCII.LF &
      "id = ""coffee""" & ASCII.LF &
      "label = ""Coffee""" & ASCII.LF &
      "pacing = ""daily""" & ASCII.LF &
      "backing-pool = ""liquid""" & ASCII.LF);

   Write_File
     (To_String (Paths.Household_TOML),
      "[cycle]" & ASCII.LF &
      "mode = ""income-anchor""" & ASCII.LF &
      "income-account = ""income:salary""" & ASCII.LF &
      "[money]" & ASCII.LF &
      "primary-commodity = ""JPY""" & ASCII.LF &
      "[budget]" & ASCII.LF &
      "opening-accounts = [""budget:opening""]" & ASCII.LF &
      "unassigned-accounts = [""budget:unassigned""]" & ASCII.LF &
      "[[budget.envelopes]]" & ASCII.LF &
      "id = ""coffee""" & ASCII.LF &
      "allocation-account = ""budget:coffee""" & ASCII.LF &
      "[envelope-history]" & ASCII.LF &
      "identities = [""coffee""]" & ASCII.LF &
      "[[envelope-history.expense-routing]]" & ASCII.LF &
      "effective-from = ""initial""" & ASCII.LF &
      "expense-account = ""expenses:coffee""" & ASCII.LF &
      "route = ""managed""" & ASCII.LF &
      "target = ""coffee""" & ASCII.LF &
      "note = ""temporal test routing""" & ASCII.LF);

   Write_File
     (To_String (Paths.Report_TOML),
      "[presentation.amounts]" & ASCII.LF &
      "negative-style = ""parentheses""" & ASCII.LF &
      "[reports.trial-balance]" & ASCII.LF &
      "as-of = ""latest""" & ASCII.LF &
      "[reports.balance-sheet]" & ASCII.LF &
      "as-of = ""latest""" & ASCII.LF &
      "[reports.profit-and-loss]" & ASCII.LF &
      "from = ""beginning""" & ASCII.LF &
      "through = ""latest""" & ASCII.LF &
      "[reports.daily-flow]" & ASCII.LF &
      "from = ""beginning""" & ASCII.LF &
      "through = ""latest""" & ASCII.LF &
      "max-date-columns = 7" & ASCII.LF &
      "[reports.monthly-accounts]" & ASCII.LF &
      "from = ""beginning""" & ASCII.LF &
      "through = ""latest""" & ASCII.LF &
      "[reports.recent-transactions]" & ASCII.LF &
      "through = ""latest""" & ASCII.LF &
      "count = 10" & ASCII.LF);

   Write_File
     (To_String (Paths.Issues_TSV),
      "issue_id" & ASCII.HT & "status" & ASCII.HT & "date" & ASCII.HT &
      "due" & ASCII.HT & "closed" & ASCII.HT & "category" & ASCII.HT &
      "title" & ASCII.HT & "amount" & ASCII.HT & "currency" & ASCII.HT &
      "details" & ASCII.LF);

   Assert
     (HRA.Household.Load_Canonical_Household (Tmp_Dir, State, Err),
      "Setup: admit complete synthetic Household");

   declare
      Why : HRA.Household_Envelope_Explanation.Explanation_Observation;
      Why_Diag : HRA.Household_Envelope_Explanation.Explain_Diagnostic;
      Succeeded : constant Boolean :=
        HRA.Household_Envelope_Explanation.Explain
          (D ("2026-08-15"), State, Why, Why_Diag);
   begin
      Assert
        (Succeeded
           and then Why_Diag.Status =
             HRA.Household_Envelope_Explanation.Success,
         "Explain current Envelope directly from admitted Household state");
      if Succeeded then
         Assert
           (Why.Observed_Through = D ("2026-08-15")
              and then Natural (Why.Lines.Length) = 1,
            "Household explanation retains observation day and current membership");
         if Natural (Why.Lines.Length) = 1 then
            declare
               Line : constant
                 HRA.Household_Envelope_Explanation.Explanation_Line :=
                   Why.Lines.Element (1);
            begin
               Assert
                 (HRA.Envelope.Image (Line.Env_Id) = "coffee",
                  "Household explanation follows current Envelope order");
               Assert
                 (HRA.Money.Lookup_Balance
                    (Line.Why.Evidence.Consumption_Charges, JPY) = 500.0,
                  "Household explanation retains gross Consumption evidence");
               Assert
                 (HRA.Money.Lookup_Balance
                    (Line.Why.Observed_Position.Remaining, JPY) = -500.0,
                  "Household explanation closes over proof-backed Remaining");
            end;
         end if;
      end if;
   end;

   declare
      Succeeded : constant Boolean :=
        HRA.Household_Temporal.Observe_Envelope_Change
          (D ("2026-08-15"),
           (Kind => HRA.Household_Envelope_Change.No_Previous_Observation),
           (Kind => HRA.Household_Envelope_Change.Cycle_Start),
           State,
           Change,
           Diag);
   begin
      if not Succeeded then
         Put_Diagnostic (Diag);
      end if;
      Assert
        (Succeeded and then Diag.Status = HRA.Household_Temporal.Success,
         "Cycle Start request composes directly from admitted Household state");

      if Succeeded then
         Assert
           (Change.From_Date = D ("2026-08-01")
              and then Change.Through_Date = D ("2026-08-15"),
            "Temporal application retains resolved Cycle Start interval");
         Assert
           (Natural (Change.Lines.Length) = 1,
            "Temporal application retains one current Envelope coordinate");
         if Natural (Change.Lines.Length) = 1 then
            Assert
              (HRA.Envelope.Image (Change.Lines.Element (1).Env_Id) = "coffee",
               "Temporal application preserves current Envelope identity and order");
            Assert
              (HRA.Money.Lookup_Balance
                 (Change.Lines.Element (1).Consumption_Charges, JPY) = 500.0,
               "Cycle-start Change observes 500 JPY gross coffee consumption");
            Assert
              (HRA.Money.Lookup_Balance
                 (Change.Lines.Element (1).Remaining, JPY) = -500.0,
               "Cycle-start Change observes resulting -500 JPY Remaining movement");
         end if;
      end if;
   end;

   declare
      Succeeded : constant Boolean :=
        HRA.Household_Temporal.Observe_Envelope_Change
          (D ("2026-08-15"),
           (Kind             => HRA.Household_Envelope_Change.Previous_Observation_Available,
            Observed_Through => D ("2026-08-12")),
           (Kind => HRA.Household_Envelope_Change.Previous_Observation),
           State,
           Change,
           Diag);
   begin
      if not Succeeded then
         Put_Diagnostic (Diag);
      end if;
      Assert
        (Succeeded and then Diag.Status = HRA.Household_Temporal.Success,
         "Previous Observation context composes directly from admitted Household state");
      if Succeeded then
         Assert
           (Change.From_Date = D ("2026-08-12")
              and then Natural (Change.Lines.Length) = 1
              and then HRA.Money.Lookup_Balance
                (Change.Lines.Element (1).Consumption_Charges, JPY) = 500.0,
            "Previous Observation is caller supplied and retains later activity");
      end if;
   end;

   declare
      Succeeded : constant Boolean :=
        HRA.Household_Temporal.Observe_Envelope_Change
          (D ("2026-08-15"),
           (Kind => HRA.Household_Envelope_Change.No_Previous_Observation),
           (Kind => HRA.Household_Envelope_Change.Previous_Observation),
           State,
           Change,
           Diag);
   begin
      Assert
        (not Succeeded
           and then Diag.Status = HRA.Household_Temporal.Baseline_Unavailable
           and then Diag.Baseline.Status =
             HRA.Household_Envelope_Change.Previous_Observation_Unavailable,
         "Missing Previous Observation fails closed without evidence fallback");
   end;

   Write_File
     (To_String (Paths.Budget_Journal),
      "2026-08-01 Clean Envelope epoch" & ASCII.LF &
      "    budget:opening          0 JPY" & ASCII.LF &
      "    budget:unassigned       0 JPY" & ASCII.LF & ASCII.LF &
      "2026-08-02 Rogue Budget coordinate" & ASCII.LF &
      "    budget:unassigned      -1 JPY" & ASCII.LF &
      "    budget:rogue             1 JPY" & ASCII.LF);
   Assert
     (not HRA.Household.Load_Canonical_Household (Tmp_Dir, State, Err)
        and then Index (To_String (Err), "unrecognized") > 0,
      "Canonical Household rejects declared but semantically unknown Budget coordinate");

   Delete_Tree (Tmp_Dir);

   Put_Line
     (Natural'Image (Passed_Count) & " passed, " &
      Natural'Image (Failed_Count) & " failed");

   if Failed_Count > 0 then
      raise Program_Error with "Household temporal tests failed";
   end if;
end Test_Household_Temporal;
