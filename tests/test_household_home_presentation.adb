with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO;           use Ada.Text_IO;
with HRA.Canonical_Source;  use HRA.Canonical_Source;
with HRA.Dates;             use type HRA.Dates.Date;
with HRA.Household;
with HRA.Household_Home_Observation;
with HRA.Household_Home_Presentation;
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
      Obs.Root_Path := To_Unbounded_String ("/tmp/hra_test_home_presentation");
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
   Put_Line ("--- Testing Household Home Presentation ---");

   --  ========================================================================
   --  Setup standard admitted state
   --  ========================================================================
   declare
      Sources : constant HRA.Canonical_Source.Source_Observation :=
        Make_Synthetic_Sources;
   begin
      Assert
        (HRA.Household.Admit_Canonical_Household (Sources, State, Error_Msg),
         "Admit synthetic Household state");
   end;

   --  ========================================================================
   --  1. Attention Marker Resolution Tests
   --  ========================================================================
   declare
      use HRA.Household_Home_Observation;
      use HRA.Household_Home_Presentation;
      Markers : HRA.Report_Config.Calendar_Markers :=
        (Cycle_End => '|', Plan_Due => '$', Issue_Due => '!', Multiple => '+');
      Att : Attention_Observation;
   begin
      --  All absent
      Att := (Plan_Scheduled => Absent, Issue_Due => Absent, Cycle_End => Absent);
      Assert (Resolve_Marker (Att, Markers) = ' ', "All absent resolves to space");

      --  Plan only
      Att := (Plan_Scheduled => Present, Issue_Due => Absent, Cycle_End => Absent);
      Assert (Resolve_Marker (Att, Markers) = '$', "Plan only resolves to '$'");

      --  Issue only
      Att := (Plan_Scheduled => Absent, Issue_Due => Present, Cycle_End => Absent);
      Assert (Resolve_Marker (Att, Markers) = '!', "Issue only resolves to '!'");

      --  Cycle only
      Att := (Plan_Scheduled => Absent, Issue_Due => Absent, Cycle_End => Present);
      Assert (Resolve_Marker (Att, Markers) = '|', "Cycle only resolves to '|'");

      --  Combinations of 2 (Multiple)
      Att := (Plan_Scheduled => Present, Issue_Due => Present, Cycle_End => Absent);
      Assert (Resolve_Marker (Att, Markers) = '+', "Plan + Issue resolves to '+'");

      Att := (Plan_Scheduled => Present, Issue_Due => Absent, Cycle_End => Present);
      Assert (Resolve_Marker (Att, Markers) = '+', "Plan + Cycle resolves to '+'");

      Att := (Plan_Scheduled => Absent, Issue_Due => Present, Cycle_End => Present);
      Assert (Resolve_Marker (Att, Markers) = '+', "Issue + Cycle resolves to '+'");

      --  Combination of 3
      Att := (Plan_Scheduled => Present, Issue_Due => Present, Cycle_End => Present);
      Assert (Resolve_Marker (Att, Markers) = '+', "All 3 present resolves to '+'");

      --  Unavailable with Present
      Att := (Plan_Scheduled => Present, Issue_Due => Unavailable, Cycle_End => Absent);
      Assert (Resolve_Marker (Att, Markers) = '$', "Plan present with Issue unavailable resolves to '$'");

      Att := (Plan_Scheduled => Absent, Issue_Due => Unavailable, Cycle_End => Unavailable);
      Assert (Resolve_Marker (Att, Markers) = ' ', "Only unavailables resolve to space");

      --  Custom marker glyphs
      Markers := (Cycle_End => 'C', Plan_Due => 'P', Issue_Due => 'I', Multiple => 'M');
      Att := (Plan_Scheduled => Present, Issue_Due => Absent, Cycle_End => Absent);
      Assert (Resolve_Marker (Att, Markers) = 'P', "Custom Plan marker");
      Att := (Plan_Scheduled => Absent, Issue_Due => Present, Cycle_End => Absent);
      Assert (Resolve_Marker (Att, Markers) = 'I', "Custom Issue marker");
      Att := (Plan_Scheduled => Absent, Issue_Due => Absent, Cycle_End => Present);
      Assert (Resolve_Marker (Att, Markers) = 'C', "Custom Cycle marker");
      Att := (Plan_Scheduled => Present, Issue_Due => Present, Cycle_End => Absent);
      Assert (Resolve_Marker (Att, Markers) = 'M', "Custom Multiple marker");
   end;

   --  ========================================================================
   --  2. Format_Cell Tests
   --  ========================================================================
   declare
      use HRA.Household_Home_Presentation;
      Cell : Calendar_Cell;
   begin
      --  1-digit, unselected, no marker
      Cell := (Date_Value => D ("2026-08-05"), Day_Number => 5,
               Is_Current_Month => True, Is_Selected => False,
               Is_Observed_Through => False, Is_Future => False,
               Attention => <>, Marker => ' ');
      Assert (Format_Cell (Cell) = "   5  ", "Format unselected 1-digit no marker is '   5  '");

      --  2-digit, unselected, no marker
      Cell := (Date_Value => D ("2026-08-19"), Day_Number => 19,
               Is_Current_Month => True, Is_Selected => False,
               Is_Observed_Through => True, Is_Future => False,
               Attention => <>, Marker => ' ');
      Assert (Format_Cell (Cell) = "  19  ", "Format unselected 2-digit no marker is '  19  '");

      --  2-digit, unselected, with marker '$'
      Cell.Marker := '$';
      Assert (Format_Cell (Cell) = " 19$ ", "Format unselected 2-digit with marker is ' 19$ '");

      --  2-digit, selected, no marker
      Cell.Is_Selected := True;
      Cell.Marker := ' ';
      Assert (Format_Cell (Cell) = "[19] ", "Format selected 2-digit no marker is '[19] '");

      --  2-digit, selected, with marker '$'
      Cell.Marker := '$';
      Assert (Format_Cell (Cell) = "[19$]", "Format selected 2-digit with marker is '[19$]'");

      --  1-digit, selected, with marker '!'
      Cell.Day_Number := 7;
      Cell.Marker := '!';
      Assert (Format_Cell (Cell) = "[ 7!]", "Format selected 1-digit with marker is '[ 7!]'");
   end;

   --  ========================================================================
   --  3. Calendar Grid Generation Tests
   --  ========================================================================
   declare
      use HRA.Household_Home_Observation;
      use HRA.Household_Home_Presentation;

      Obs  : constant Home_Observation :=
        Observe
          (Observed_Through => D ("2026-08-19"),
           Selected_Day     => D ("2026-08-19"),
           State            => State);

      Pres : constant Home_Presentation := Present (Obs);
      Grid : constant Calendar_Grid := Pres.Calendar;
   begin
      Assert (Grid.Year = 2026, "Calendar year is 2026");
      Assert (Grid.Month = 8, "Calendar month is 8 (August)");
      Assert (Natural (Grid.Weeks.Length) = 6, "August 2026 spans 6 calendar weeks");

      --  Week 1 check (starts Monday 2026-07-27)
      declare
         W1 : constant Calendar_Week := Grid.Weeks.Element (1);
      begin
         Assert (W1 (HRA.Dates.Monday).Date_Value = D ("2026-07-27"),
                 "Week 1 Monday is 2026-07-27 (previous month padding)");
         Assert (not W1 (HRA.Dates.Monday).Is_Current_Month,
                 "2026-07-27 is not current month");
         Assert (W1 (HRA.Dates.Saturday).Date_Value = D ("2026-08-01"),
                 "Week 1 Saturday is 2026-08-01 (first day of August)");
         Assert (W1 (HRA.Dates.Saturday).Is_Current_Month,
                 "2026-08-01 is current month");
         Assert (W1 (HRA.Dates.Sunday).Date_Value = D ("2026-08-02"),
                 "Week 1 Sunday is 2026-08-02");
      end;

      --  Week 4 check (contains selected day 2026-08-19 Wednesday)
      declare
         W4 : constant Calendar_Week := Grid.Weeks.Element (4);
      begin
         Assert (W4 (HRA.Dates.Wednesday).Date_Value = D ("2026-08-19"),
                 "Week 4 Wednesday is 2026-08-19");
         Assert (W4 (HRA.Dates.Wednesday).Is_Selected,
                 "2026-08-19 is selected");
         Assert (W4 (HRA.Dates.Wednesday).Is_Observed_Through,
                 "2026-08-19 is observed through");
         Assert (not W4 (HRA.Dates.Wednesday).Is_Future,
                 "2026-08-19 is not future");
         Assert (W4 (HRA.Dates.Thursday).Date_Value = D ("2026-08-20"),
                 "Week 4 Thursday is 2026-08-20");
         Assert (not W4 (HRA.Dates.Thursday).Is_Selected,
                 "2026-08-20 is not selected");
         Assert (W4 (HRA.Dates.Thursday).Is_Future,
                 "2026-08-20 is future");
      end;

      --  Week 5 check (contains 2026-08-25 Tuesday with Plan + Issue attention => '+', and 2026-08-30 Sunday with Cycle_End => '|')
      declare
         W5 : constant Calendar_Week := Grid.Weeks.Element (5);
      begin
         Assert (W5 (HRA.Dates.Tuesday).Date_Value = D ("2026-08-25"),
                 "Week 5 Tuesday is 2026-08-25");
         Assert (W5 (HRA.Dates.Tuesday).Marker = '+',
                 "2026-08-25 has '+' marker (Plan + Issue due)");
         Assert (W5 (HRA.Dates.Sunday).Date_Value = D ("2026-08-30"),
                 "Week 5 Sunday is 2026-08-30");
         Assert (W5 (HRA.Dates.Sunday).Marker = '|',
                 "2026-08-30 has '|' marker (Cycle end)");
      end;

      --  Week 6 check (contains 2026-08-31 Monday with Plan => '$', and next month padding)
      declare
         W6 : constant Calendar_Week := Grid.Weeks.Element (6);
      begin
         Assert (W6 (HRA.Dates.Monday).Date_Value = D ("2026-08-31"),
                 "Week 6 Monday is 2026-08-31");
         Assert (W6 (HRA.Dates.Monday).Is_Current_Month,
                 "2026-08-31 is current month");
         Assert (W6 (HRA.Dates.Monday).Marker = '$',
                 "2026-08-31 has '$' marker (Plan scheduled)");
         Assert (W6 (HRA.Dates.Tuesday).Date_Value = D ("2026-09-01"),
                 "Week 6 Tuesday is 2026-09-01 (next month padding)");
         Assert (not W6 (HRA.Dates.Tuesday).Is_Current_Month,
                 "2026-09-01 is not current month");
         Assert (W6 (HRA.Dates.Sunday).Date_Value = D ("2026-09-06"),
                 "Week 6 Sunday is 2026-09-06");
      end;
   end;

   --  ========================================================================
   --  4. Selected Day Domain Presentations (Today: 2026-08-19)
   --  ========================================================================
   declare
      use HRA.Household_Home_Observation;
      use HRA.Household_Home_Presentation;

      Obs  : constant Home_Observation :=
        Observe
          (Observed_Through => D ("2026-08-19"),
           Selected_Day     => D ("2026-08-19"),
           State            => State);

      Pres : constant Home_Presentation := Present (Obs);
   begin
      Assert (Pres.Observed_Through = D ("2026-08-19"),
              "Observed_Through is 2026-08-19");
      Assert (Pres.Selected_Day = D ("2026-08-19"),
              "Selected_Day is 2026-08-19");
      Assert (not Pres.Is_Future_Focus,
              "Is_Future_Focus is False on 2026-08-19");

      --  Actual Presentation
      Assert (Pres.Actual.Status = Available,
              "Actual presentation is Available");
      Assert (Natural (Pres.Actual.Items.Length) = 1,
              "Actual presentation has 1 transaction");
      Assert (To_String (Pres.Actual.Items.Element (1).Description) = "Dinner",
              "Transaction description is 'Dinner'");

      --  Plan Presentation (Empty)
      Assert (Pres.Plan.Status = Available,
              "Plan presentation is Available");
      Assert (Pres.Plan.Items.Is_Empty,
              "Plan presentation is empty on 2026-08-19");

      --  Issue Presentation (Empty)
      Assert (Pres.Issue.Status = Available,
              "Issue presentation is Available");
      Assert (Pres.Issue.Items.Is_Empty,
              "Issue presentation is empty on 2026-08-19");

      --  Cycle Presentation
      Assert (Pres.Cycle.Status = Available,
              "Cycle presentation is Available");
      Assert (Pres.Cycle.Has_Previous_Window,
              "Cycle has previous window");
      Assert (To_String (Pres.Cycle.Previous_Window_Text) = "2026-07-25 .. 2026-07-31",
              "Previous window text is 2026-07-25 .. 2026-07-31");
      Assert (Pres.Cycle.Has_Current_Window,
              "Cycle has current window");
      Assert (To_String (Pres.Cycle.Current_Window_Text) = "2026-08-01 .. 2026-08-30",
              "Current window text is 2026-08-01 .. 2026-08-30");
      Assert (To_String (Pres.Cycle.Focus_Cycle_Role) = "Current Cycle",
              "Role on 2026-08-19 is 'Current Cycle'");
   end;

   --  ========================================================================
   --  5. Future Focus Day (2026-08-25 > 2026-08-19)
   --  ========================================================================
   declare
      use HRA.Household_Home_Observation;
      use HRA.Household_Home_Presentation;

      Obs  : constant Home_Observation :=
        Observe
          (Observed_Through => D ("2026-08-19"),
           Selected_Day     => D ("2026-08-25"),
           State            => State);

      Pres : constant Home_Presentation := Present (Obs);
   begin
      Assert (Pres.Is_Future_Focus, "Is_Future_Focus is True on 2026-08-25");

      --  Actual is Unavailable (Horizon exceeded, future admitted Tx is NEVER leaked)
      Assert (Pres.Actual.Status = Unavailable,
              "Actual presentation is Unavailable on future focus day");
      Assert (Length (Pres.Actual.Unavailable_Message) > 0,
              "Actual unavailable message is present");

      --  Plan has 1 scheduled payment
      Assert (Pres.Plan.Status = Available,
              "Plan presentation is Available");
      Assert (Natural (Pres.Plan.Items.Length) = 1,
              "Plan has 1 item on 2026-08-25");
      declare
         Item : constant Plan_Item := Pres.Plan.Items.Element (1);
      begin
         Assert (To_String (Item.Plan_Id) = "plan-util-aug",
                 "Plan Id is plan-util-aug");
         Assert (To_String (Item.Due_Date_Text) = "2026-08-25",
                 "Due date is 2026-08-25");
         Assert (To_String (Item.Total_Amount) = "8,000 JPY",
                 "Amount is 8,000 JPY");
      end;

      --  Issue has 2 due issues
      Assert (Pres.Issue.Status = Available,
              "Issue presentation is Available");
      Assert (Natural (Pres.Issue.Items.Length) = 2,
              "Issue has 2 items on 2026-08-25");
      Assert (To_String (Pres.Issue.Items.Element (1).Issue_Id) = "ISSUE-1",
              "First due issue ID is ISSUE-1");
      Assert (To_String (Pres.Issue.Items.Element (2).Issue_Id) = "ISSUE-2",
              "Second due issue ID is ISSUE-2");

      --  Cycle is Available
      Assert (Pres.Cycle.Status = Available,
              "Cycle is Available on future day");
      Assert (To_String (Pres.Cycle.Focus_Cycle_Role) = "Current Cycle",
              "Role on 2026-08-25 is 'Current Cycle'");
   end;

   --  ========================================================================
   --  6. Cycle End Presentation Roles
   --  ========================================================================
   declare
      use HRA.Household_Home_Observation;
      use HRA.Household_Home_Presentation;

      --  Focus on current cycle human end: 2026-08-30
      Obs_Curr_End : constant Home_Observation :=
        Observe
          (Observed_Through => D ("2026-08-19"),
           Selected_Day     => D ("2026-08-30"),
           State            => State);
      Pres_Curr_End : constant Home_Presentation := Present (Obs_Curr_End);

      --  Focus on previous cycle human end: 2026-07-31
      Obs_Prev_End : constant Home_Observation :=
        Observe
          (Observed_Through => D ("2026-08-19"),
           Selected_Day     => D ("2026-07-31"),
           State            => State);
      Pres_Prev_End : constant Home_Presentation := Present (Obs_Prev_End);

      --  Focus on outside cycle windows: 2026-07-10
      Obs_Outside : constant Home_Observation :=
        Observe
          (Observed_Through => D ("2026-08-19"),
           Selected_Day     => D ("2026-07-10"),
           State            => State);
      Pres_Outside : constant Home_Presentation := Present (Obs_Outside);
   begin
      Assert (To_String (Pres_Curr_End.Cycle.Focus_Cycle_Role) = "Current Cycle End",
              "Role on 2026-08-30 is 'Current Cycle End'");
      Assert (To_String (Pres_Prev_End.Cycle.Focus_Cycle_Role) = "Previous Cycle End",
              "Role on 2026-07-31 is 'Previous Cycle End'");
      Assert (To_String (Pres_Outside.Cycle.Focus_Cycle_Role) = "Outside Known Cycles",
              "Role on 2026-07-10 is 'Outside Known Cycles'");
   end;

   --  ========================================================================
   --  7. Text Rendering Function Tests
   --  ========================================================================
   declare
      use HRA.Household_Home_Observation;
      use HRA.Household_Home_Presentation;

      Obs_Today : constant Home_Observation :=
        Observe
          (Observed_Through => D ("2026-08-19"),
           Selected_Day     => D ("2026-08-19"),
           State            => State);
      Pres_Today : constant Home_Presentation := Present (Obs_Today);
      Text_Today : constant String := Render_Home (Pres_Today);

      Obs_Future : constant Home_Observation :=
        Observe
          (Observed_Through => D ("2026-08-19"),
           Selected_Day     => D ("2026-08-25"),
           State            => State);
      Pres_Future : constant Home_Presentation := Present (Obs_Future);
      Text_Future : constant String := Render_Home (Pres_Future);
   begin
      Assert (Text_Today'Length > 0, "Render_Home for today produces non-empty output");
      Assert (Text_Future'Length > 0, "Render_Home for future produces non-empty output");
   end;

   --  ========================================================================
   --  Summary
   --  ========================================================================
   Put_Line ("--------------------------------------------------");
   Put_Line ("Summary: Passed = " & Natural'Image (Passed_Count) &
             ", Failed = " & Natural'Image (Failed_Count));

   if Failed_Count > 0 then
      raise Program_Error with "Household Home presentation tests failed";
   end if;
end Test_Household_Home_Presentation;
