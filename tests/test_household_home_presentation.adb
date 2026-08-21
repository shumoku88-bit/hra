with Ada.Command_Line;
with Ada.Strings.Fixed;               use Ada.Strings.Fixed;
with Ada.Strings.Unbounded;           use Ada.Strings.Unbounded;
with Ada.Text_IO;                     use Ada.Text_IO;
with HRA.Canonical_Source;            use HRA.Canonical_Source;
with HRA.Cycle_Observation;           use type HRA.Cycle_Observation.Resolve_Status;
with HRA.Dates;                       use type HRA.Dates.Date;
with HRA.Household;
with HRA.Household_Home_Observation;
with HRA.Household_Home_Presentation; use type HRA.Household_Home_Presentation.Attention_State;
                                      use type HRA.Household_Home_Presentation.Daily_Target_Availability;
                                      use type HRA.Household_Home_Presentation.Daily_Target_Not_Visible_Reason;
                                      use type HRA.Household_Home_Presentation.Domain_Availability;
                                      use type HRA.Household_Home_Presentation.Issue_Unavailable_Reason;
with HRA.Household_Home_Text;
with HRA.Plan;
with HRA.Report_Config;

procedure Test_Household_Home_Presentation is
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
     "issue_id" & ASCII.HT & "status" & ASCII.HT & "date" & ASCII.HT &
     "due" & ASCII.HT & "closed" & ASCII.HT & "category" & ASCII.HT &
     "title" & ASCII.HT & "amount" & ASCII.HT & "currency" & ASCII.HT &
     "details";

   function Make_Synthetic_Sources
     (Include_Undetermined_Issue : Boolean := False;
      Include_Future_Plan_Anchor : Boolean := True)
      return HRA.Canonical_Source.Source_Observation
   is
      Obs : HRA.Canonical_Source.Source_Observation;
   begin
      Obs.Root_Path := To_Unbounded_String ("/tmp/hra_test_home_presentation");
      Obs.Paths := HRA.Household.Resolve_Source_Paths (To_String (Obs.Root_Path));

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
        ("2026-07-25 July Salary" & ASCII.LF &
         "    assets:bank          300000 JPY" & ASCII.LF &
         "    income:salary       -300000 JPY" & ASCII.LF & ASCII.LF &
         "2026-08-01 August Salary" & ASCII.LF &
         "    assets:bank          300000 JPY" & ASCII.LF &
         "    income:salary       -300000 JPY" & ASCII.LF & ASCII.LF &
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
          else ""));

      Obs.Texts (Entitlement_Source) := To_Unbounded_String
        ("2026-07-25 origin JPY ; Opening" & ASCII.LF &
         "2026-08-01 transfer unallocated -> food 50000 JPY ; Food Allocation" & ASCII.LF);

      Obs.Texts (Envelope_Config_Source) := To_Unbounded_String
        ("[[backing-pools]]" & ASCII.LF &
         "id = ""liquid""" & ASCII.LF &
         "asset-accounts = [""assets:bank"", ""assets:cash""]" & ASCII.LF &
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
         "note = ""home presentation routing""" & ASCII.LF);

      Obs.Texts (Report_Config_Source) := To_Unbounded_String
        ("[presentation.amounts]" & ASCII.LF &
         "negative-style = ""parentheses""" & ASCII.LF &
         "[reports.trial-balance]" & ASCII.LF & "as-of = ""latest""" & ASCII.LF &
         "[reports.balance-sheet]" & ASCII.LF & "as-of = ""latest""" & ASCII.LF &
         "[reports.profit-and-loss]" & ASCII.LF & "from = ""beginning""" & ASCII.LF &
         "through = ""latest""" & ASCII.LF &
         "[reports.daily-flow]" & ASCII.LF & "from = ""beginning""" & ASCII.LF &
         "through = ""latest""" & ASCII.LF & "max-date-columns = 7" & ASCII.LF &
         "[reports.monthly-accounts]" & ASCII.LF & "from = ""beginning""" & ASCII.LF &
         "through = ""latest""" & ASCII.LF &
         "[reports.recent-transactions]" & ASCII.LF & "through = ""latest""" & ASCII.LF &
         "count = 10" & ASCII.LF);

      Obs.Texts (Issues_Source) := To_Unbounded_String
        (Canonical_Issues_Header & ASCII.LF &
         "ISSUE-1" & ASCII.HT & "open" & ASCII.HT & "2026-08-01" & ASCII.HT &
         "2026-08-25" & ASCII.HT & "none" & ASCII.HT & "tax" & ASCII.HT &
         "Tax Payment" & ASCII.HT & "10000" & ASCII.HT & "JPY" & ASCII.HT & "city tax" & ASCII.LF &
         "ISSUE-2" & ASCII.HT & "resolved" & ASCII.HT & "2026-08-01" & ASCII.HT &
         "2026-08-25" & ASCII.HT & "2026-08-22" & ASCII.HT & "bill" & ASCII.HT &
         "Gas Bill" & ASCII.HT & "3000" & ASCII.HT & "JPY" & ASCII.HT & "gas" & ASCII.LF &
         (if Include_Undetermined_Issue then
            "ISSUE-3" & ASCII.HT & "resolved" & ASCII.HT & "2026-08-01" & ASCII.HT &
            "2026-08-25" & ASCII.HT & "undetermined" & ASCII.HT & "misc" & ASCII.HT &
            "Undetermined" & ASCII.HT & "" & ASCII.HT & "" & ASCII.HT & "" & ASCII.LF
          else ""));

      return Obs;
   end Make_Synthetic_Sources;

   State     : HRA.Household.Household_State;
   Error_Msg : Unbounded_String;
begin
   Put_Line ("--- Testing Household Home Presentation & Text Rendering ---");

   declare
      Sources : constant HRA.Canonical_Source.Source_Observation := Make_Synthetic_Sources;
   begin
      Assert
        (HRA.Household.Admit_Canonical_Household (Sources, State, Error_Msg),
         "Admit synthetic Household state");
   end;

   declare
      use HRA.Household_Home_Presentation;
      Markers : constant HRA.Report_Config.Calendar_Markers :=
        (Cycle_End => '|', Plan_Due => '$', Issue_Due => '!', Multiple => '+');
   begin
      Assert
        (HRA.Household_Home_Text.Resolve_Marker
           ((Plan_Scheduled => Present, Issue_Due => Absent, Cycle_End => Absent), Markers) = '$',
         "Plan-only attention maps to Plan marker");
      Assert
        (HRA.Household_Home_Text.Resolve_Marker
           ((Plan_Scheduled => Present, Issue_Due => Present, Cycle_End => Absent), Markers) = '+',
         "Multiple attention maps to combined marker");
      Assert
        (HRA.Household_Home_Text.Resolve_Marker
           ((Plan_Scheduled => Absent, Issue_Due => Absent, Cycle_End => Present), Markers) = '|',
         "Cycle-only attention maps to Cycle marker");
   end;

   declare
      Obs  : constant HRA.Household_Home_Observation.Home_Observation :=
        HRA.Household_Home_Observation.See_Home
          (D ("2026-08-19"), D ("2026-08-19"), State);
      Pres : constant HRA.Household_Home_Presentation.Home_Presentation :=
        HRA.Household_Home_Presentation.Present (Obs);
   begin
      Assert (Pres.Known_Through = D ("2026-08-19")
              and then Pres.Selected_Day = D ("2026-08-19"),
              "Presentation preserves known-through and focus coordinates");
      Assert (Pres.Daily_Target.Status = HRA.Household_Home_Presentation.Unconfigured,
              "Daily Target presentation is Unconfigured when absent from policy");
      Assert (Pres.Actual.Status = HRA.Household_Home_Presentation.Available
              and then Natural (Pres.Actual.Items.Length) = 1,
              "Presentation exposes visible Actual items");
      Assert (Pres.Plan.Items.Is_Empty,
              "Plan presentation is available empty without an availability shell");
      Assert (Pres.Cycle.Status = HRA.Household_Home_Presentation.Available,
              "Cycle presentation is available for admitted anchors");
      Assert (Pres.Calendar.Year = 2026 and then Pres.Calendar.Month = 8,
              "Calendar presentation retains selected month");
      declare
         Text : constant String := HRA.Household_Home_Text.Render_Home (Pres);
      begin
         Assert (Index (Text, "Daily Target : (not configured)") > 0
                 and then Index (Text, "Known Through: 2026-08-19") < Index (Text, "Daily Target :")
                 and then Index (Text, "Daily Target :") < Index (Text, "Attention    :"),
                 "Text renders Daily Target unconfigured between Known Through and Attention");
      end;
   end;

   declare
      Obs  : constant HRA.Household_Home_Observation.Home_Observation :=
        HRA.Household_Home_Observation.See_Home
          (D ("2026-08-19"), D ("2026-08-25"), State);
      Pres : constant HRA.Household_Home_Presentation.Home_Presentation :=
        HRA.Household_Home_Presentation.Present (Obs);
      Text : constant String := HRA.Household_Home_Text.Render_Home (Pres);
   begin
      Assert (Pres.Is_Future_Focus,
              "Future focus is explicit in presentation");
      Assert (Pres.Actual.Status = HRA.Household_Home_Presentation.Unavailable,
              "Future Actual presentation remains unavailable");
      Assert (Natural (Pres.Plan.Items.Length) = 1
              and then HRA.Plan.Text (Pres.Plan.Items.Element (1).Plan_Id) = "plan-util-aug",
              "Known future Plan is presented directly");
      Assert (Natural (Pres.Plan.Items.Element (1).Postings.Length) = 2,
              "Plan presentation preserves whole posting payload");
      Assert (Pres.Issue.Status = HRA.Household_Home_Presentation.Available
              and then Natural (Pres.Issue.Items.Length) = 2,
              "Issue presentation remains independent");
      Assert (Pres.Attention.Plan_Scheduled = HRA.Household_Home_Presentation.Present
              and then Pres.Attention.Issue_Due = HRA.Household_Home_Presentation.Present,
              "Presentation carries combined attention facts");
      Assert (Index (Text, "Planned Payments:") > 0
              and then Index (Text, "plan-util-aug") > 0
              and then Index (Text, "[Open]") > 0,
              "Text renderer consumes always-present Plan presentation");
      Assert (Index (Text, "known through 2026-08-19") > 0
              and then Index (Text, "not yet visible") > 0,
              "Text names knowledge and visibility without observation-machine wording");

      declare
         Horizon_Obs : constant HRA.Household_Home_Observation.Home_Horizon_Observation :=
           HRA.Household_Home_Observation.See_Horizon (D ("2026-08-19"), State);
         Day_Obs : constant HRA.Household_Home_Observation.Home_Day_Observation :=
           HRA.Household_Home_Observation.Project_Day (Horizon_Obs, D ("2026-08-25"), State);
         Pres_Split : constant HRA.Household_Home_Presentation.Home_Presentation :=
           HRA.Household_Home_Presentation.Present (Horizon_Obs, Day_Obs);
      begin
         Assert (Pres_Split.Is_Future_Focus = Pres.Is_Future_Focus
                 and then Pres_Split.Known_Through = Pres.Known_Through
                 and then Pres_Split.Selected_Day = Pres.Selected_Day
                 and then Pres_Split.Actual.Status = Pres.Actual.Status
                 and then Natural (Pres_Split.Plan.Items.Length) = Natural (Pres.Plan.Items.Length)
                 and then Natural (Pres_Split.Issue.Items.Length) = Natural (Pres.Issue.Items.Length),
                 "Present (Horizon, Day_Obs) matches presentation from See_Home");
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
         "Admit state with undetermined Issue closure");
      declare
         Obs : constant HRA.Household_Home_Observation.Home_Observation :=
           HRA.Household_Home_Observation.See_Home
             (D ("2026-08-19"), D ("2026-08-25"), Undet_State);
         Pres : constant HRA.Household_Home_Presentation.Home_Presentation :=
           HRA.Household_Home_Presentation.Present (Obs);
      begin
         Assert (Pres.Issue.Status = HRA.Household_Home_Presentation.Unavailable
                 and then Pres.Issue.Reason =
                   HRA.Household_Home_Presentation.Closure_Timing_Undetermined,
                 "Issue unavailable reason survives presentation");
         Assert (Natural (Pres.Plan.Items.Length) = 1,
                 "Issue unavailability does not manufacture Plan unavailability");
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
         "Admit state without future Plan cycle anchor");
      declare
         Obs : constant HRA.Household_Home_Observation.Home_Observation :=
           HRA.Household_Home_Observation.See_Home
             (D ("2026-08-19"), D ("2026-08-30"), No_Anchor_State);
         Pres : constant HRA.Household_Home_Presentation.Home_Presentation :=
           HRA.Household_Home_Presentation.Present (Obs);
         Text : constant String := HRA.Household_Home_Text.Render_Home (Pres);
      begin
         Assert (Pres.Cycle.Status = HRA.Household_Home_Presentation.Unavailable
                 and then Pres.Cycle.Error = HRA.Cycle_Observation.Missing_Future_Plan_Anchor,
                 "Cycle presentation retains genuine resolution failure directly");
         Assert (Pres.Plan.Items.Is_Empty,
                 "Plan presentation remains a valid projection when Cycle fails");
         Assert (Index (Text, "Cycle resolution failed") > 0
                 and then Index (Text, "Plan observation unavailable") = 0,
                 "Text renders genuine Cycle failure without retired Plan-unavailable shell");
      end;
   end;

   --  ========================================================================
   --  Calendar Format_Cell fixed 4-slot invariant tests
   --  ========================================================================
   declare
      Padding_Cell : constant HRA.Household_Home_Presentation.Calendar_Cell :=
        (Kind => HRA.Household_Home_Presentation.Out_Of_Range_Padding);

      Single_Digit_Plain : constant HRA.Household_Home_Presentation.Calendar_Cell :=
        (Kind             => HRA.Household_Home_Presentation.Dated_Cell,
         Date_Value       => D ("2026-08-05"),
         Is_Current_Month => True,
         Is_Selected      => False,
         Is_Known_Through => False,
         Is_Future        => False,
         Attention        => (Plan_Scheduled => HRA.Household_Home_Presentation.Absent,
                              Issue_Due      => HRA.Household_Home_Presentation.Absent,
                              Cycle_End      => HRA.Household_Home_Presentation.Absent));

      Single_Digit_Selected : constant HRA.Household_Home_Presentation.Calendar_Cell :=
        (Kind             => HRA.Household_Home_Presentation.Dated_Cell,
         Date_Value       => D ("2026-08-05"),
         Is_Current_Month => True,
         Is_Selected      => True,
         Is_Known_Through => False,
         Is_Future        => False,
         Attention        => (Plan_Scheduled => HRA.Household_Home_Presentation.Absent,
                              Issue_Due      => HRA.Household_Home_Presentation.Absent,
                              Cycle_End      => HRA.Household_Home_Presentation.Absent));

      Single_Digit_Marked : constant HRA.Household_Home_Presentation.Calendar_Cell :=
        (Kind             => HRA.Household_Home_Presentation.Dated_Cell,
         Date_Value       => D ("2026-08-05"),
         Is_Current_Month => True,
         Is_Selected      => False,
         Is_Known_Through => False,
         Is_Future        => False,
         Attention        => (Plan_Scheduled => HRA.Household_Home_Presentation.Present,
                              Issue_Due      => HRA.Household_Home_Presentation.Absent,
                              Cycle_End      => HRA.Household_Home_Presentation.Absent));

      Single_Digit_Marked_Selected : constant HRA.Household_Home_Presentation.Calendar_Cell :=
        (Kind             => HRA.Household_Home_Presentation.Dated_Cell,
         Date_Value       => D ("2026-08-05"),
         Is_Current_Month => True,
         Is_Selected      => True,
         Is_Known_Through => False,
         Is_Future        => False,
         Attention        => (Plan_Scheduled => HRA.Household_Home_Presentation.Present,
                              Issue_Due      => HRA.Household_Home_Presentation.Absent,
                              Cycle_End      => HRA.Household_Home_Presentation.Absent));

      Double_Digit_Plain : constant HRA.Household_Home_Presentation.Calendar_Cell :=
        (Kind             => HRA.Household_Home_Presentation.Dated_Cell,
         Date_Value       => D ("2026-08-15"),
         Is_Current_Month => True,
         Is_Selected      => False,
         Is_Known_Through => False,
         Is_Future        => False,
         Attention        => (Plan_Scheduled => HRA.Household_Home_Presentation.Absent,
                              Issue_Due      => HRA.Household_Home_Presentation.Absent,
                              Cycle_End      => HRA.Household_Home_Presentation.Absent));

      Double_Digit_Selected : constant HRA.Household_Home_Presentation.Calendar_Cell :=
        (Kind             => HRA.Household_Home_Presentation.Dated_Cell,
         Date_Value       => D ("2026-08-15"),
         Is_Current_Month => True,
         Is_Selected      => True,
         Is_Known_Through => False,
         Is_Future        => False,
         Attention        => (Plan_Scheduled => HRA.Household_Home_Presentation.Absent,
                              Issue_Due      => HRA.Household_Home_Presentation.Absent,
                              Cycle_End      => HRA.Household_Home_Presentation.Absent));

      Double_Digit_Marked : constant HRA.Household_Home_Presentation.Calendar_Cell :=
        (Kind             => HRA.Household_Home_Presentation.Dated_Cell,
         Date_Value       => D ("2026-08-15"),
         Is_Current_Month => True,
         Is_Selected      => False,
         Is_Known_Through => False,
         Is_Future        => False,
         Attention        => (Plan_Scheduled => HRA.Household_Home_Presentation.Present,
                              Issue_Due      => HRA.Household_Home_Presentation.Absent,
                              Cycle_End      => HRA.Household_Home_Presentation.Absent));

      Double_Digit_Marked_Selected : constant HRA.Household_Home_Presentation.Calendar_Cell :=
        (Kind             => HRA.Household_Home_Presentation.Dated_Cell,
         Date_Value       => D ("2026-08-15"),
         Is_Current_Month => True,
         Is_Selected      => True,
         Is_Known_Through => False,
         Is_Future        => False,
         Attention        => (Plan_Scheduled => HRA.Household_Home_Presentation.Present,
                              Issue_Due      => HRA.Household_Home_Presentation.Absent,
                              Cycle_End      => HRA.Household_Home_Presentation.Absent));
   begin
      Assert (HRA.Household_Home_Text.Format_Cell (Padding_Cell) = "     ",
              "Padding cell formats as 5 spaces");
      Assert (HRA.Household_Home_Text.Format_Cell (Single_Digit_Plain) = "  5  ",
              "Single-digit plain cell formats as '  5  '");
      Assert (HRA.Household_Home_Text.Format_Cell (Single_Digit_Selected) = "[ 5 ]",
              "Single-digit selected cell formats as '[ 5 ]' preserving digit column");
      Assert (HRA.Household_Home_Text.Format_Cell (Single_Digit_Marked) = "  5$ ",
              "Single-digit marked cell formats as '  5$ '");
      Assert (HRA.Household_Home_Text.Format_Cell (Single_Digit_Marked_Selected) = "[ 5$]",
              "Single-digit marked selected cell formats as '[ 5$]' preserving digit column");
      Assert (HRA.Household_Home_Text.Format_Cell (Double_Digit_Plain) = " 15  ",
              "Double-digit plain cell formats as ' 15  '");
      Assert (HRA.Household_Home_Text.Format_Cell (Double_Digit_Selected) = "[15 ]",
              "Double-digit selected cell formats as '[15 ]' preserving digit column");
      Assert (HRA.Household_Home_Text.Format_Cell (Double_Digit_Marked) = " 15$ ",
              "Double-digit marked cell formats as ' 15$ '");
      Assert (HRA.Household_Home_Text.Format_Cell (Double_Digit_Marked_Selected) = "[15$]",
              "Double-digit marked selected cell formats as '[15$]' preserving digit column");

      declare
         Grid : HRA.Household_Home_Presentation.Calendar_Grid;
         Grid_Text : constant String :=
           HRA.Household_Home_Text.Render_Calendar_Grid (Grid);
      begin
         Assert (Index (Grid_Text, " Mon  Tue  Wed  Thu  Fri  Sat  Sun") > 0,
                 "Calendar header aligns with 4-slot cell layout");
      end;
   end;

   --  ========================================================================
   --  Daily Target Presentation & Text Rendering scenarios
   --  ========================================================================
   declare
      DT_Sources : HRA.Canonical_Source.Source_Observation := Make_Synthetic_Sources;
      DT_State   : HRA.Household.Household_State;
      DT_Err     : Unbounded_String;
   begin
      --  Configure [daily-target]
      DT_Sources.Texts (Household_Config_Source) := To_Unbounded_String
        ("[cycle]" & ASCII.LF &
         "mode = ""income-anchor""" & ASCII.LF &
         "income-account = ""income:salary""" & ASCII.LF &
         "[money]" & ASCII.LF &
         "primary-commodity = ""JPY""" & ASCII.LF &
         "[daily-target]" & ASCII.LF &
         "assets = [{ id = ""bank"", account = ""assets:bank"" }, { id = ""cash"", account = ""assets:cash"" }]" & ASCII.LF &
         "[envelope-history]" & ASCII.LF &
         "identities = [""food""]" & ASCII.LF &
         "[[envelope-history.expense-routing]]" & ASCII.LF &
         "effective-from = ""initial""" & ASCII.LF &
         "expense-account = ""expenses:food""" & ASCII.LF &
         "route = ""managed""" & ASCII.LF &
         "target = ""food""" & ASCII.LF &
         "note = ""home presentation routing""" & ASCII.LF);

      --  Tag plan with daily-target-id
      DT_Sources.Texts (Plan_Source) := To_Unbounded_String
        ("2026-08-25 Planned Utility Bill" & ASCII.LF &
         "    ; plan-id: plan-util-aug" & ASCII.LF &
         "    ; daily-target-id: sel-util" & ASCII.LF &
         "    expenses:food          8000 JPY" & ASCII.LF &
         "    assets:bank           -8000 JPY" & ASCII.LF & ASCII.LF &
         "2026-08-31 September Salary" & ASCII.LF &
         "    ; plan-id: plan-sep-salary" & ASCII.LF &
         "    assets:bank          300000 JPY" & ASCII.LF &
         "    income:salary       -300000 JPY" & ASCII.LF);

      Assert
        (HRA.Household.Admit_Canonical_Household (DT_Sources, DT_State, DT_Err),
         "Admit Household state configured with Daily Target");

      declare
         Obs  : constant HRA.Household_Home_Observation.Home_Observation :=
           HRA.Household_Home_Observation.See_Home
             (D ("2026-08-19"), D ("2026-08-19"), DT_State);
         Pres : constant HRA.Household_Home_Presentation.Home_Presentation :=
           HRA.Household_Home_Presentation.Present (Obs);
         Text : constant String := HRA.Household_Home_Text.Render_Home (Pres);
      begin
         Assert
           (Pres.Daily_Target.Status = HRA.Household_Home_Presentation.Visible,
            "Configured Daily Target presents as Visible");
         Assert
           (Pres.Daily_Target.Remaining_Days = 12,
            "Visible Daily Target retains exact remaining days");
         Assert
           (Index (Text, "Daily Target : ") > 0
            and then Index (Text, "over 12 remaining days in cycle") > 0,
            "Text renders Visible Daily Target with exact capacity and days");
      end;

      --  Configured Daily Target + Missing Future Anchor -> Cycle_Unavailable
      declare
         Broken_Cycle_Sources : HRA.Canonical_Source.Source_Observation := DT_Sources;
         Broken_Cycle_State   : HRA.Household.Household_State;
      begin
         Broken_Cycle_Sources.Texts (Plan_Source) := To_Unbounded_String
           ("2026-08-25 Planned Utility Bill" & ASCII.LF &
            "    ; plan-id: plan-util-aug" & ASCII.LF &
            "    ; daily-target-id: sel-util" & ASCII.LF &
            "    expenses:food          8000 JPY" & ASCII.LF &
            "    assets:bank           -8000 JPY" & ASCII.LF);

         Assert
           (HRA.Household.Admit_Canonical_Household
              (Broken_Cycle_Sources, Broken_Cycle_State, DT_Err),
            "Admit configured Daily Target state without future cycle anchor");

         declare
            Obs  : constant HRA.Household_Home_Observation.Home_Observation :=
              HRA.Household_Home_Observation.See_Home
                (D ("2026-08-19"), D ("2026-08-19"), Broken_Cycle_State);
            Pres : constant HRA.Household_Home_Presentation.Home_Presentation :=
              HRA.Household_Home_Presentation.Present (Obs);
            Text : constant String := HRA.Household_Home_Text.Render_Home (Pres);
         begin
            Assert
              (Pres.Daily_Target.Status = HRA.Household_Home_Presentation.Not_Visible
               and then Pres.Daily_Target.Reason =
                 HRA.Household_Home_Presentation.Cycle_Unavailable,
               "Daily Target presents as Not_Visible (Cycle_Unavailable)");
            Assert
              (Index (Text, "Daily Target : (not yet visible: cycle boundaries are undetermined)") > 0,
               "Text renders gentle not-yet-visible message for Cycle_Unavailable");
         end;
      end;

      --  Scope Unavailable scenario
      declare
         Scope_Unavail_Sources : HRA.Canonical_Source.Source_Observation := DT_Sources;
         Scope_Unavail_State   : HRA.Household.Household_State;
      begin
         --  Invalid plan shape: 3 postings
         Scope_Unavail_Sources.Texts (Plan_Source) := To_Unbounded_String
           ("2026-08-25 Planned Three-Leg Bill" & ASCII.LF &
            "    ; plan-id: plan-bad" & ASCII.LF &
            "    ; daily-target-id: sel-bad" & ASCII.LF &
            "    expenses:food          4000 JPY" & ASCII.LF &
            "    expenses:food          4000 JPY" & ASCII.LF &
            "    assets:bank           -8000 JPY" & ASCII.LF & ASCII.LF &
            "2026-08-31 September Salary" & ASCII.LF &
            "    ; plan-id: plan-sep-salary" & ASCII.LF &
            "    assets:bank          300000 JPY" & ASCII.LF &
            "    income:salary       -300000 JPY" & ASCII.LF);

         Assert
           (HRA.Household.Admit_Canonical_Household
              (Scope_Unavail_Sources, Scope_Unavail_State, DT_Err),
            "Admit state with unsupported daily target plan shape");

         declare
            Obs  : constant HRA.Household_Home_Observation.Home_Observation :=
              HRA.Household_Home_Observation.See_Home
                (D ("2026-08-19"), D ("2026-08-19"), Scope_Unavail_State);
            Pres : constant HRA.Household_Home_Presentation.Home_Presentation :=
              HRA.Household_Home_Presentation.Present (Obs);
            Text : constant String := HRA.Household_Home_Text.Render_Home (Pres);
         begin
            Assert
              (Pres.Daily_Target.Status = HRA.Household_Home_Presentation.Not_Visible
               and then Pres.Daily_Target.Reason =
                 HRA.Household_Home_Presentation.Scope_Unavailable,
               "Daily Target presents as Not_Visible (Scope_Unavailable)");
            Assert
              (Index (Text, "Daily Target : (setup unavailable: daily target configuration cannot be applied)") > 0
               and then Index (Text, "not yet visible") = 0,
               "Text distinguishes setup-unavailable from temporal not-yet-visible");
         end;
      end;
   end;

   Put_Line ("--------------------------------------------------");
   Put_Line
     ("Summary: Passed =" & Natural'Image (Passed_Count) &
      ", Failed =" & Natural'Image (Failed_Count));
   if Failed_Count > 0 then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Test_Household_Home_Presentation;
