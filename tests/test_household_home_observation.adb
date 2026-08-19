with Ada.Command_Line;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO;           use Ada.Text_IO;
with HRA.Canonical_Source;  use HRA.Canonical_Source;
with HRA.Dates;             use HRA.Dates;
with HRA.Household;
with HRA.Household_Home_Observation; use HRA.Household_Home_Observation;
with HRA.Issues;
with HRA.Plan;

procedure Test_Household_Home_Observation is
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
      Val  : HRA.Dates.Date;
      Stat : HRA.Dates.Date_Status;
   begin
      if not HRA.Dates.Parse (S, Val, Stat) then
         raise Program_Error with "invalid test date: " & S;
      end if;
      return Val;
   end D;

   Canonical_Issues_Header : constant String :=
     "issue_id"   & ASCII.HT &
     "status"     & ASCII.HT &
     "date"       & ASCII.HT &
     "due"        & ASCII.HT &
     "closed"     & ASCII.HT &
     "category"   & ASCII.HT &
     "title"      & ASCII.HT &
     "amount"     & ASCII.HT &
     "currency"   & ASCII.HT &
     "details";

   function Make_Synthetic_Sources
     (Include_Undetermined_Issue : Boolean := False)
      return HRA.Canonical_Source.Source_Observation
   is
      Obs : HRA.Canonical_Source.Source_Observation;
   begin
      Obs.Root_Path := To_Unbounded_String ("/tmp/hra_test_home_observation");
      Obs.Paths :=
        HRA.Household.Resolve_Source_Paths (To_String (Obs.Root_Path));

      Obs.Texts (Accounts_Source) := To_Unbounded_String
        ("account assets:bank" & ASCII.LF &
         "  ; type: Asset" & ASCII.LF &
         "account assets:cash" & ASCII.LF &
         "  ; type: Asset" & ASCII.LF &
         "account expenses:food" & ASCII.LF &
         "  ; type: Expense" & ASCII.LF &
         "account income:salary" & ASCII.LF &
         "  ; type: Income" & ASCII.LF &
         "account budget:food" & ASCII.LF &
         "  ; type: Budget" & ASCII.LF &
         "account budget:unassigned" & ASCII.LF &
         "  ; type: Budget" & ASCII.LF &
         "account budget:opening" & ASCII.LF &
         "  ; type: Budget" & ASCII.LF);

      Obs.Texts (Actual_Source) := To_Unbounded_String
        ("2026-07-25 July Salary" & ASCII.LF &
         "    assets:bank          300000 JPY" & ASCII.LF &
         "    income:salary       -300000 JPY" & ASCII.LF & ASCII.LF &
         "2026-08-01 August Salary" & ASCII.LF &
         "    assets:bank          300000 JPY" & ASCII.LF &
         "    income:salary       -300000 JPY" & ASCII.LF & ASCII.LF &
         "2026-08-10 Grocery Shopping" & ASCII.LF &
         "    expenses:food          5000 JPY" & ASCII.LF &
         "    assets:cash           -5000 JPY" & ASCII.LF & ASCII.LF &
         "2026-08-19 Dinner" & ASCII.LF &
         "    expenses:food          2000 JPY" & ASCII.LF &
         "    assets:cash           -2000 JPY" & ASCII.LF & ASCII.LF &
         "2026-08-25 Future Admitted Actual" & ASCII.LF &
         "    expenses:food          1000 JPY" & ASCII.LF &
         "    assets:cash           -1000 JPY" & ASCII.LF);

      Obs.Texts (Plan_Source) := To_Unbounded_String
        ("2026-08-25 Planned Utility Bill" & ASCII.LF &
         "    ; plan-id: plan-util-aug" & ASCII.LF &
         "    expenses:food          8000 JPY" & ASCII.LF &
         "    assets:bank           -8000 JPY" & ASCII.LF & ASCII.LF &
         "2026-08-31 September Salary" & ASCII.LF &
         "    ; plan-id: plan-sep-salary" & ASCII.LF &
         "    assets:bank          300000 JPY" & ASCII.LF &
         "    income:salary       -300000 JPY" & ASCII.LF);

      Obs.Texts (Budget_Journal_Source) := To_Unbounded_String
        ("2026-07-25 Opening" & ASCII.LF &
         "    budget:opening            0 JPY" & ASCII.LF &
         "    budget:unassigned         0 JPY" & ASCII.LF & ASCII.LF &
         "2026-08-01 Food Allocation" & ASCII.LF &
         "    budget:unassigned    -50000 JPY" & ASCII.LF &
         "    budget:food           50000 JPY" & ASCII.LF);

      Obs.Texts (Budget_Config_Source) := To_Unbounded_String
        ("[[backing-pools]]" & ASCII.LF &
         "id = ""liquid""" & ASCII.LF &
         "asset-accounts = [""assets:bank"", ""assets:cash""]" & ASCII.LF & ASCII.LF &
         "[[envelopes]]" & ASCII.LF &
         "id = ""food""" & ASCII.LF &
         "label = ""Food""" & ASCII.LF &
         "pacing = ""daily""" & ASCII.LF &
         "backing-pool = ""liquid""" & ASCII.LF);

      Obs.Texts (Household_Config_Source) := To_Unbounded_String
        ("[cycle]" & ASCII.LF &
         "mode = ""income-anchor""" & ASCII.LF &
         "income-account = ""income:salary""" & ASCII.LF &
         "[money]" & ASCII.LF &
         "primary-commodity = ""JPY""" & ASCII.LF &
         "[budget]" & ASCII.LF &
         "opening-accounts = [""budget:opening""]" & ASCII.LF &
         "unassigned-accounts = [""budget:unassigned""]" & ASCII.LF &
         "[[budget.envelopes]]" & ASCII.LF &
         "id = ""food""" & ASCII.LF &
         "allocation-account = ""budget:food""" & ASCII.LF &
         "[envelope-history]" & ASCII.LF &
         "identities = [""food""]" & ASCII.LF &
         "[[envelope-history.expense-routing]]" & ASCII.LF &
         "effective-from = ""initial""" & ASCII.LF &
         "expense-account = ""expenses:food""" & ASCII.LF &
         "route = ""managed""" & ASCII.LF &
         "target = ""food""" & ASCII.LF &
         "note = ""home observation routing""" & ASCII.LF);

      Obs.Texts (Report_Config_Source) := To_Unbounded_String
        ("[presentation.amounts]" & ASCII.LF &
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

      Obs.Texts (Issues_Source) := To_Unbounded_String
        (Canonical_Issues_Header & ASCII.LF &
         "ISSUE-1" & ASCII.HT & "open" & ASCII.HT & "2026-08-01" & ASCII.HT &
         "2026-08-25" & ASCII.HT & "none" & ASCII.HT & "tax" & ASCII.HT &
         "Tax Payment" & ASCII.HT & "10000" & ASCII.HT & "JPY" & ASCII.HT & "city tax" & ASCII.LF &
         "ISSUE-2" & ASCII.HT & "resolved" & ASCII.HT & "2026-08-01" & ASCII.HT &
         "2026-08-25" & ASCII.HT & "2026-08-22" & ASCII.HT & "bill" & ASCII.HT &
         "Gas Bill" & ASCII.HT & "3000" & ASCII.HT & "JPY" & ASCII.HT & "gas" & ASCII.LF &
         "ISSUE-3" & ASCII.HT & "resolved" & ASCII.HT & "2026-08-01" & ASCII.HT &
         "2026-08-25" & ASCII.HT & "2026-08-15" & ASCII.HT & "bill" & ASCII.HT &
         "Electric Bill" & ASCII.HT & "4000" & ASCII.HT & "JPY" & ASCII.HT & "electric" & ASCII.LF &
         "ISSUE-4" & ASCII.HT & "open" & ASCII.HT & "2026-08-22" & ASCII.HT &
         "2026-08-25" & ASCII.HT & "none" & ASCII.HT & "admin" & ASCII.HT &
         "Future Issue" & ASCII.HT & "" & ASCII.HT & "" & ASCII.HT & "future" & ASCII.LF &
         "ISSUE-5" & ASCII.HT & "open" & ASCII.HT & "2026-08-01" & ASCII.HT &
         "none" & ASCII.HT & "none" & ASCII.HT & "misc" & ASCII.HT &
         "No Due Issue" & ASCII.HT & "" & ASCII.HT & "" & ASCII.HT & "" & ASCII.LF &
         (if Include_Undetermined_Issue then
            "ISSUE-6" & ASCII.HT & "resolved" & ASCII.HT & "2026-08-01" & ASCII.HT &
            "2026-08-25" & ASCII.HT & "undetermined" & ASCII.HT & "misc" & ASCII.HT &
            "Undet Issue" & ASCII.HT & "" & ASCII.HT & "" & ASCII.HT & "" & ASCII.LF
          else
            ""));

      return Obs;
   end Make_Synthetic_Sources;

   State     : HRA.Household.Household_State;
   Error_Msg : Unbounded_String;
begin
   Put_Line ("--- Testing Household Home observation ---");

   --  ========================================================================
   --  Setup standard admitted state
   --  ========================================================================
   declare
      Sources : constant HRA.Canonical_Source.Source_Observation :=
        Make_Synthetic_Sources (Include_Undetermined_Issue => False);
   begin
      Assert
        (HRA.Household.Admit_Canonical_Household (Sources, State, Error_Msg),
         "Admit synthetic Household state");
   end;

   --  ========================================================================
   --  A. Temporal Coordinates Laws
   --  ========================================================================

   --  A1. Observed_Through = Selected_Day = 2026-08-19
   declare
      Obs : constant Home_Observation :=
        Observe (D ("2026-08-19"), D ("2026-08-19"), State);
   begin
      Assert (Obs.Observed_Through = D ("2026-08-19"), "Observed_Through is preserved");
      Assert (Obs.Selected_Day = D ("2026-08-19"), "Selected_Day is preserved");
      Assert (Is_Available (Obs.Actual), "Actual is available when Selected_Day = Observed_Through");
      Assert (Transaction_Count (Obs.Actual) = 1, "Actual observes 1 transaction on 2026-08-19");
      Assert (Is_Available (Obs.Plan), "Plan is available");
      Assert (Open_Plan_Count (Obs.Plan) = 0, "Plan is available empty for 2026-08-19");
      Assert (Is_Available (Obs.Issue), "Issue is available");
      Assert (Due_Issue_Count (Obs.Issue) = 0, "Issue is available empty for 2026-08-19");
      Assert (Is_Available (Obs.Cycle), "Cycle is available");
      Assert (Obs.Attention.Plan_Due = Absent, "Plan_Due attention is Absent on 2026-08-19");
      Assert (Obs.Attention.Issue_Due = Absent, "Issue_Due attention is Absent on 2026-08-19");
      Assert (Obs.Attention.Cycle_End = Absent, "Cycle_End attention is Absent on 2026-08-19");
   end;

   --  A2. Selected_Day < Observed_Through (Past day: 2026-08-10)
   declare
      Obs : constant Home_Observation :=
        Observe (D ("2026-08-19"), D ("2026-08-10"), State);
   begin
      Assert (Is_Available (Obs.Actual), "Actual is available for past day 2026-08-10");
      Assert (Transaction_Count (Obs.Actual) = 1, "Actual observes 1 transaction on 2026-08-10");
      Assert (Is_Available (Obs.Plan), "Plan is available for past day 2026-08-10");
      Assert (Open_Plan_Count (Obs.Plan) = 0, "Plan is empty for 2026-08-10");
   end;

   --  A3. Selected_Day > Observed_Through (Future day: 2026-08-25)
   declare
      Obs : constant Home_Observation :=
        Observe (D ("2026-08-19"), D ("2026-08-25"), State);
   begin
      Assert (not Is_Available (Obs.Actual), "Actual is UNAVAILABLE for future focus day 2026-08-25");
      Assert (Is_Available (Obs.Plan), "Plan is available for future focus day 2026-08-25");
      Assert (Open_Plan_Count (Obs.Plan) = 1, "Plan observes 1 planned payment on 2026-08-25");
      Assert (Is_Available (Obs.Issue), "Issue is available for future focus day 2026-08-25");
      Assert (Due_Issue_Count (Obs.Issue) = 2, "Issue observes 2 open-as-of due issues on 2026-08-25");
      Assert (Is_Available (Obs.Cycle), "Cycle is available for future focus day 2026-08-25");
      Assert (Obs.Attention.Plan_Due = Present, "Plan_Due attention is Present on 2026-08-25");
      Assert (Obs.Attention.Issue_Due = Present, "Issue_Due attention is Present on 2026-08-25");
   end;

   --  ========================================================================
   --  B. Actual Laws
   --  ========================================================================

   --  B1. Past selected day + no Actual => available empty
   declare
      Obs : constant Home_Observation :=
        Observe (D ("2026-08-19"), D ("2026-08-11"), State);
   begin
      Assert (Is_Available (Obs.Actual), "Past day with no transactions is Available");
      Assert (Transaction_Count (Obs.Actual) = 0, "Past day with no transactions has 0 items");
   end;

   --  B2. Past selected day + Actual => available nonempty
   declare
      Obs : constant Home_Observation :=
        Observe (D ("2026-08-19"), D ("2026-08-10"), State);
   begin
      Assert (Is_Available (Obs.Actual), "Past day with transactions is Available");
      Assert (Transaction_Count (Obs.Actual) = 1, "Past day with transactions has exact count");
      Assert
        (To_String (Obs.Actual.Transactions.Element (1).Code_Or_Payee) = "Grocery Shopping",
         "Actual transaction payee is preserved");
   end;

   --  B3. Future selected day + admitted future Actual => unavailable, never leak transaction
   declare
      Obs : constant Home_Observation :=
        Observe (D ("2026-08-19"), D ("2026-08-25"), State);
   begin
      Assert (not Is_Available (Obs.Actual), "Future focus day with admitted Actual is UNAVAILABLE");
      Assert (Obs.Actual.Status = Unavailable, "Actual.Status is Unavailable");
   end;

   --  ========================================================================
   --  C. Plan Laws
   --  ========================================================================

   --  C1. Known future Plan on Selected_Day => available
   declare
      Obs : constant Home_Observation :=
        Observe (D ("2026-08-19"), D ("2026-08-25"), State);
   begin
      Assert (Is_Available (Obs.Plan), "Plan on 2026-08-25 is Available");
      Assert (Open_Plan_Count (Obs.Plan) = 1, "1 open plan on 2026-08-25");
      Assert
        (HRA.Plan.Text (Obs.Plan.Open_Plans.Element (1).ID) = "plan-util-aug",
         "Plan preserves whole Transaction and durable Plan_Id");
      Assert
        (To_String (Obs.Plan.Open_Plans.Element (1).Tx.Code_Or_Payee) = "Planned Utility Bill",
         "Plan preserves whole Transaction payload");
   end;

   --  C2. No Plan on Selected_Day => available empty
   declare
      Obs : constant Home_Observation :=
        Observe (D ("2026-08-19"), D ("2026-08-26"), State);
   begin
      Assert (Is_Available (Obs.Plan), "Plan on day with no plans is Available");
      Assert (Open_Plan_Count (Obs.Plan) = 0, "0 open plans on 2026-08-26");
   end;

   --  C3. Plan observation unavailable (broken evidence)
   declare
      Broken_Sources : HRA.Canonical_Source.Source_Observation :=
        Make_Synthetic_Sources;
      Broken_State   : HRA.Household.Household_State;
      Broken_Err     : Unbounded_String;
   begin
      --  Admit state normally, then invalidate Plan_Evidence count
      Assert
        (HRA.Household.Admit_Canonical_Household (Broken_Sources, Broken_State, Broken_Err),
         "Admit state for broken plan test");
      Broken_State.Plan_Evidence.Transactions.Clear;
      declare
         Obs : constant Home_Observation :=
           Observe (D ("2026-08-19"), D ("2026-08-25"), Broken_State);
      begin
         Assert (not Is_Available (Obs.Plan), "Plan observation is UNAVAILABLE when evidence fails");
         Assert (Obs.Plan.Status = Unavailable, "Plan.Status = Unavailable");
         Assert (Obs.Attention.Plan_Due = Unavailable, "Plan_Due attention is Unavailable when Plan fails");
      end;
   end;

   --  ========================================================================
   --  D. Issue Laws
   --  ========================================================================

   --  D1. Recorded_On after Observed_Through => not visible
   --  D2. resolved now, Closed_On after Observed_Through => open as-of
   --  D3. Closed_On <= Observed_Through => closed as-of
   --  D4. Due_On Selected_Day + open-as-of => due attention present
   --  D5. No_Due_Date / Due_Undetermined => due attention absent, no fake date
   declare
      Obs : constant Home_Observation :=
        Observe (D ("2026-08-19"), D ("2026-08-25"), State);
   begin
      --  Due_Issues on 2026-08-25 should contain ISSUE-1 (open) and ISSUE-2 (resolved 2026-08-22 > 2026-08-19)
      --  It must NOT contain ISSUE-3 (closed 2026-08-15 <= 2026-08-19) or ISSUE-4 (recorded 2026-08-22 > 2026-08-19)
      Assert (Due_Issue_Count (Obs.Issue) = 2, "2 open-as-of issues due on 2026-08-25");
      Assert
        (HRA.Issues.Text (Obs.Issue.Due_Issues.Element (1).Issue.ID) = "ISSUE-1",
         "ISSUE-1 is due on 2026-08-25");
      Assert
        (HRA.Issues.Text (Obs.Issue.Due_Issues.Element (2).Issue.ID) = "ISSUE-2",
         "ISSUE-2 (resolved in future) is open-as-of and due on 2026-08-25");
      Assert (Obs.Attention.Issue_Due = Present, "Issue_Due attention is Present on 2026-08-25");
   end;

   --  D6. Closed_Undetermined => uncertainty retained, makes Selected_Day due Unavailable
   declare
      Undet_Sources : constant HRA.Canonical_Source.Source_Observation :=
        Make_Synthetic_Sources (Include_Undetermined_Issue => True);
      Undet_State   : HRA.Household.Household_State;
      Undet_Err     : Unbounded_String;
   begin
      Assert
        (HRA.Household.Admit_Canonical_Household (Undet_Sources, Undet_State, Undet_Err),
         "Admit state with undetermined issue");
      declare
         Obs : constant Home_Observation :=
           Observe (D ("2026-08-19"), D ("2026-08-25"), Undet_State);
      begin
         Assert
           (not Is_Available (Obs.Issue),
            "Issue on 2026-08-25 is UNAVAILABLE when undetermined issue is due on that day");
         Assert
           (Obs.Attention.Issue_Due = Unavailable,
            "Issue_Due attention is Unavailable on 2026-08-25 due to undetermined closure");
      end;
      --  On a different day without undetermined issue, Issue is Available
      declare
         Obs : constant Home_Observation :=
           Observe (D ("2026-08-19"), D ("2026-08-26"), Undet_State);
      begin
         Assert (Is_Available (Obs.Issue), "Issue on 2026-08-26 is Available");
         Assert (Obs.Attention.Issue_Due = Absent, "Issue_Due attention is Absent on 2026-08-26");
      end;
   end;

   --  ========================================================================
   --  E. Cycle Laws
   --  ========================================================================

   --  Cycle Window: 2026-08-01 .. 2026-08-31
   --  End_Exclusive = 2026-08-31
   --  Human_End_Day = 2026-08-30 (Previous day)
   declare
      Obs_End : constant Home_Observation :=
        Observe (D ("2026-08-19"), D ("2026-08-30"), State);
      Obs_Other : constant Home_Observation :=
        Observe (D ("2026-08-19"), D ("2026-08-25"), State);
   begin
      Assert (Is_Available (Obs_End.Cycle), "Cycle is Available on 2026-08-30");
      Assert (Obs_End.Cycle.Human_End_Day = D ("2026-08-30"), "Human_End_Day is 2026-08-30");
      Assert (Obs_End.Attention.Cycle_End = Present, "Cycle_End attention is Present on 2026-08-30");
      Assert (Obs_Other.Attention.Cycle_End = Absent, "Cycle_End attention is Absent on 2026-08-25");
   end;

   --  E3. Cycle resolution unavailable
   declare
      No_Cycle_State : HRA.Household.Household_State := State;
   begin
      --  Clear actual transactions so cycle resolution has insufficient actual anchors
      No_Cycle_State.Actual_Ledger.Transactions.Clear;
      declare
         Obs : constant Home_Observation :=
           Observe (D ("2026-08-19"), D ("2026-08-30"), No_Cycle_State);
      begin
         Assert (not Is_Available (Obs.Cycle), "Cycle is UNAVAILABLE when cycle anchor resolution fails");
         Assert (Obs.Cycle.Status = Unavailable, "Cycle.Status is Unavailable");
         Assert (Obs.Attention.Cycle_End = Unavailable, "Cycle_End attention is Unavailable");
      end;
   end;

   --  ========================================================================
   --  F. Independence Laws
   --  ========================================================================

   --  F1. Plan unavailable does not destroy Actual or Issue
   declare
      Broken_Plan_State : HRA.Household.Household_State := State;
   begin
      Broken_Plan_State.Plan_Evidence.Transactions.Clear;
      declare
         Obs : constant Home_Observation :=
           Observe (D ("2026-08-19"), D ("2026-08-19"), Broken_Plan_State);
      begin
         Assert (Obs.Plan.Status = Unavailable, "Plan is Unavailable");
         Assert (Obs.Actual.Status = Available, "Actual remains Available when Plan fails");
         Assert (Obs.Issue.Status = Available, "Issue remains Available when Plan fails");
         Assert (Obs.Cycle.Status = Unavailable, "Cycle is Unavailable when Plan fails");
      end;
   end;

   --  F2. Cycle unavailable does not destroy Actual, Plan, or Issue
   declare
      Broken_Cycle_State : HRA.Household.Household_State := State;
   begin
      Broken_Cycle_State.Household_Policy.Cycle_Income_Account :=
        To_Unbounded_String ("income:invalid");
      declare
         Obs : constant Home_Observation :=
           Observe (D ("2026-08-19"), D ("2026-08-19"), Broken_Cycle_State);
      begin
         Assert (Obs.Cycle.Status = Unavailable, "Cycle is Unavailable");
         Assert (Obs.Actual.Status = Available, "Actual remains Available when Cycle fails");
         Assert (Obs.Plan.Status = Available, "Plan remains Available when Cycle fails");
         Assert (Obs.Issue.Status = Available, "Issue remains Available when Cycle fails");
      end;
   end;

   --  F3. Attention overlap: multiple dimensions are Present independently
   declare
      Obs : constant Home_Observation :=
        Observe (D ("2026-08-19"), D ("2026-08-25"), State);
   begin
      Assert (Obs.Attention.Plan_Due = Present, "Plan_Due is Present on 2026-08-25");
      Assert (Obs.Attention.Issue_Due = Present, "Issue_Due is Present on 2026-08-25");
      Assert (Obs.Attention.Cycle_End = Absent, "Cycle_End is Absent on 2026-08-25");
   end;

   --  ========================================================================
   --  G. Arbitrary Day Attention Query
   --  ========================================================================
   declare
      Obs : constant Home_Observation :=
        Observe (D ("2026-08-19"), D ("2026-08-19"), State);
      Att_25 : constant Attention_Observation :=
        Day_Attention (Obs, D ("2026-08-25"));
      Att_30 : constant Attention_Observation :=
        Day_Attention (Obs, D ("2026-08-30"));
      Att_10 : constant Attention_Observation :=
        Day_Attention (Obs, D ("2026-08-10"));
   begin
      Assert
        (Att_25.Plan_Due = Present
         and then Att_25.Issue_Due = Present
         and then Att_25.Cycle_End = Absent,
         "Day_Attention for 2026-08-25 correctly evaluates Plan_Due and Issue_Due");

      Assert
        (Att_30.Plan_Due = Absent
         and then Att_30.Issue_Due = Absent
         and then Att_30.Cycle_End = Present,
         "Day_Attention for 2026-08-30 correctly evaluates Cycle_End");

      Assert
        (Att_10.Plan_Due = Absent
         and then Att_10.Issue_Due = Absent
         and then Att_10.Cycle_End = Absent,
         "Day_Attention for 2026-08-10 correctly evaluates all Absent");
   end;

   Put_Line ("--------------------------------------------------");
   Put_Line ("Summary: Passed =" & Natural'Image (Passed_Count) &
             ", Failed =" & Natural'Image (Failed_Count));
   if Failed_Count > 0 then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Test_Household_Home_Observation;
