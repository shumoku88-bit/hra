with Ada.Command_Line;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO;           use Ada.Text_IO;
with HRA.Canonical_Source;  use HRA.Canonical_Source;
with HRA.Cycle_Observation;
with HRA.Dates;             use HRA.Dates;
with HRA.Household;
with HRA.Household_Home_Observation; use HRA.Household_Home_Observation;
with HRA.Issues;
with HRA.Plan;

procedure Test_Household_Home_Observation is
   use type HRA.Cycle_Observation.Resolve_Status;

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
     (Include_Undetermined_Issue : Boolean := False;
      Include_Future_Plan_Anchor : Boolean := True;
      Include_Actual_Salary_Anchors : Boolean := True)
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
         "  ; type: Income" & ASCII.LF);

      Obs.Texts (Actual_Source) := To_Unbounded_String
        ((if Include_Actual_Salary_Anchors then
            "2026-07-25 July Salary" & ASCII.LF &
            "    assets:bank          300000 JPY" & ASCII.LF &
            "    income:salary       -300000 JPY" & ASCII.LF & ASCII.LF &
            "2026-08-01 August Salary" & ASCII.LF &
            "    assets:bank          300000 JPY" & ASCII.LF &
            "    income:salary       -300000 JPY" & ASCII.LF & ASCII.LF
          else
            "") &
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
         (if Include_Future_Plan_Anchor then
            "2026-08-31 September Salary" & ASCII.LF &
            "    ; plan-id: plan-sep-salary" & ASCII.LF &
            "    assets:bank          300000 JPY" & ASCII.LF &
            "    income:salary       -300000 JPY" & ASCII.LF
          else
            ""));

      Obs.Texts (Entitlement_Source) := To_Unbounded_String
        ("2026-07-25 origin JPY ; Opening" & ASCII.LF &
         "2026-08-01 transfer unallocated -> food 50000 JPY ; Food Allocation" & ASCII.LF);

      Obs.Texts (Envelope_Config_Source) := To_Unbounded_String
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

   declare
      Sources : constant HRA.Canonical_Source.Source_Observation :=
        Make_Synthetic_Sources;
   begin
      Assert
        (HRA.Household.Admit_Canonical_Household (Sources, State, Error_Msg),
         "Admit synthetic Household state");
   end;

   declare
      Obs : constant Home_Observation :=
        Observe (D ("2026-08-19"), D ("2026-08-19"), State);
   begin
      Assert (Observed_Through (Obs) = D ("2026-08-19"),
              "Observed_Through is preserved");
      Assert (Selected_Day (Obs) = D ("2026-08-19"),
              "Selected_Day is preserved");
      Assert (Is_Available (Actual (Obs)),
              "Actual is available at the observation horizon");
      Assert (Transaction_Count (Actual (Obs)) = 1,
              "Actual observes one transaction on 2026-08-19");
      Assert (Open_Plan_Count (Plan (Obs)) = 0,
              "Plan projection is available empty on 2026-08-19");
      Assert (Is_Available (Issue (Obs)) and then Due_Issue_Count (Issue (Obs)) = 0,
              "Issue projection is available empty on 2026-08-19");
      Assert (Is_Available (Cycle (Obs)),
              "Cycle is available for admitted anchors");
   end;

   declare
      Obs : constant Home_Observation :=
        Observe (D ("2026-08-19"), D ("2026-08-25"), State);
   begin
      Assert (not Is_Available (Actual (Obs))
              and then Actual (Obs).Reason = Observation_Horizon_Exceeded,
              "Future Actual is unavailable beyond knowledge horizon");
      Assert (Open_Plan_Count (Plan (Obs)) = 1,
              "Known future Plan remains visible beyond Actual horizon");
      Assert
        (HRA.Plan.Text (Plan (Obs).Open_Plans.Element (1).ID) = "plan-util-aug",
         "Future Plan preserves durable identity");
      Assert (Is_Available (Issue (Obs)) and then Due_Issue_Count (Issue (Obs)) = 2,
              "Issue observation uses the knowledge horizon independently");
      Assert (Selected_Attention (Obs).Plan_Scheduled = Present
              and then Selected_Attention (Obs).Issue_Due = Present,
              "Selected attention composes Plan and Issue facts");
   end;

   declare
      Obs : constant Home_Observation :=
        Observe (D ("2026-08-19"), D ("2026-08-10"), State);
   begin
      Assert (Is_Available (Actual (Obs)) and then Transaction_Count (Actual (Obs)) = 1,
              "Past Actual remains observable");
      Assert (Open_Plan_Count (Plan (Obs)) = 0,
              "Past day with no scheduled Plan is empty, not unavailable");
   end;

   --  Legacy Ledger/Evidence/Id fields are materialized read projections only.
   --  Home must consume the admitted Plan_Journal + Plan_Completions authority.
   declare
      Projection_Damaged_State : HRA.Household.Household_State := State;
   begin
      Projection_Damaged_State.Plan_Ledger.Transactions.Clear;
      Projection_Damaged_State.Plan_Evidence.Transactions.Clear;
      Projection_Damaged_State.Plan_Ids := HRA.Plan.Empty_Plan_Id_Universe;
      declare
         Obs : constant Home_Observation :=
           Observe
             (D ("2026-08-19"), D ("2026-08-25"), Projection_Damaged_State);
      begin
         Assert (Open_Plan_Count (Plan (Obs)) = 1,
                 "Home ignores damaged legacy Plan read projections");
         Assert (HRA.Plan.Text (Plan (Obs).Open_Plans.Element (1).ID) = "plan-util-aug",
                 "Admitted Plan authority retains identity after projection damage");
         Assert (Is_Available (Cycle (Obs)),
                 "Cycle consumes the same admitted temporal Plan authority");
         Assert (Selected_Attention (Obs).Plan_Scheduled = Present,
                 "Plan attention comes from admitted temporal authority");
      end;
   end;

   declare
      Undet_Sources : constant HRA.Canonical_Source.Source_Observation :=
        Make_Synthetic_Sources (Include_Undetermined_Issue => True);
      Undet_State : HRA.Household.Household_State;
      Undet_Err   : Unbounded_String;
   begin
      Assert
        (HRA.Household.Admit_Canonical_Household
           (Undet_Sources, Undet_State, Undet_Err),
         "Admit state with undetermined issue closure");
      declare
         Obs : constant Home_Observation :=
           Observe (D ("2026-08-19"), D ("2026-08-25"), Undet_State);
      begin
         Assert (not Is_Available (Issue (Obs))
                 and then Issue (Obs).Reason = Closure_Timing_Undetermined,
                 "Undetermined closure keeps Issue projection unavailable");
         Assert (Selected_Attention (Obs).Issue_Due = Unavailable,
                 "Issue attention preserves undetermined closure");
         Assert (Open_Plan_Count (Plan (Obs)) = 1,
                 "Issue unavailability does not affect Plan projection");
      end;
   end;

   declare
      No_Anchor_Sources : constant HRA.Canonical_Source.Source_Observation :=
        Make_Synthetic_Sources (Include_Future_Plan_Anchor => False);
      No_Anchor_State : HRA.Household.Household_State;
      No_Anchor_Err   : Unbounded_String;
   begin
      Assert
        (HRA.Household.Admit_Canonical_Household
           (No_Anchor_Sources, No_Anchor_State, No_Anchor_Err),
         "Admit state with no future Plan anchor");
      declare
         Obs : constant Home_Observation :=
           Observe (D ("2026-08-19"), D ("2026-08-30"), No_Anchor_State);
      begin
         Assert (not Is_Available (Cycle (Obs))
                 and then Cycle (Obs).Error = HRA.Cycle_Observation.Missing_Future_Plan_Anchor,
                 "Cycle reports genuine missing future Plan anchor");
         Assert (Selected_Attention (Obs).Cycle_End = Unavailable,
                 "Cycle attention is unavailable when cycle resolution fails");
      end;
   end;

   declare
      No_Actual_Anchors : constant HRA.Canonical_Source.Source_Observation :=
        Make_Synthetic_Sources (Include_Actual_Salary_Anchors => False);
      No_Actual_State : HRA.Household.Household_State;
      No_Actual_Err   : Unbounded_String;
   begin
      Assert
        (HRA.Household.Admit_Canonical_Household
           (No_Actual_Anchors, No_Actual_State, No_Actual_Err),
         "Admit state with no Actual income anchors");
      declare
         Obs : constant Home_Observation :=
           Observe (D ("2026-08-19"), D ("2026-08-30"), No_Actual_State);
      begin
         Assert (not Is_Available (Cycle (Obs))
                 and then Cycle (Obs).Error = HRA.Cycle_Observation.Insufficient_Actual_Anchors,
                 "Cycle reports genuine insufficient Actual anchors");
      end;
   end;

   declare
      Broken_Cycle_State : HRA.Household.Household_State := State;
   begin
      Broken_Cycle_State.Household_Policy.Cycle_Income_Account :=
        To_Unbounded_String ("income:invalid");
      declare
         Obs : constant Home_Observation :=
           Observe (D ("2026-08-19"), D ("2026-08-25"), Broken_Cycle_State);
      begin
         Assert (not Is_Available (Cycle (Obs)),
                 "Cycle failure remains independent");
         Assert (Is_Available (Issue (Obs)),
                 "Issue remains available when Cycle fails");
         Assert (Open_Plan_Count (Plan (Obs)) = 1,
                 "Plan remains available when Cycle fails");
      end;
   end;

   declare
      Obs : constant Home_Observation :=
        Observe (D ("2026-08-19"), D ("2026-08-19"), State);
   begin
      Assert (Day_Attention (Obs, D ("2026-07-31")).Cycle_End = Present,
              "Previous cycle human end is marked");
      Assert (Day_Attention (Obs, D ("2026-08-30")).Cycle_End = Present,
              "Current cycle human end is marked");
      Assert (Day_Attention (Obs, D ("2026-08-25")).Plan_Scheduled = Present,
              "Arbitrary-day Plan attention sees known future schedule");
      Assert (Day_Attention (Obs, D ("2026-08-31")).Cycle_End = Unavailable,
              "Cycle limit is outside current cycle coverage");
   end;

   Put_Line ("--------------------------------------------------");
   Put_Line
     ("Summary: Passed =" & Natural'Image (Passed_Count) &
      ", Failed =" & Natural'Image (Failed_Count));
   if Failed_Count > 0 then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Test_Household_Home_Observation;
