with Ada.Strings.Unbounded;           use Ada.Strings.Unbounded;
with Ada.Text_IO;                     use Ada.Text_IO;
with HRA.Account;
with HRA.Canonical_Source;            use HRA.Canonical_Source;
with HRA.Cycle_Observation;           use type HRA.Cycle_Observation.Resolve_Status;
with HRA.Dates;                       use type HRA.Dates.Date;
                                      use type HRA.Dates.Day_Of_Week;
with HRA.Household;
with HRA.Household_Home_Observation;
with HRA.Household_Home_Presentation; use type HRA.Household_Home_Presentation.Calendar_Cell_Kind;
                                      use type HRA.Household_Home_Presentation.Cycle_Focus_Role;
                                      use type HRA.Household_Home_Presentation.Cycle_Unavailable_Reason;
                                      use type HRA.Household_Home_Presentation.Domain_Availability;
                                      use type HRA.Household_Home_Presentation.Issue_Unavailable_Reason;
with HRA.Household_Home_Text;
with HRA.Issue_Observation;           use type HRA.Issue_Observation.As_Of_Status;
with HRA.Issues;
with HRA.Money;                       use type HRA.Money.Quantity;
with HRA.Plan;
with HRA.Plan_Observation;            use type HRA.Plan_Observation.Admission_Status;
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
     (Include_Multi_Posting : Boolean := True;
      Include_Undetermined_Issue : Boolean := False;
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
         "account expenses:tax" & ASCII.LF &
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
         (if Include_Multi_Posting then
            "2026-08-19 Dinner with 3 Postings" & ASCII.LF &
            "    expenses:food          2000 JPY" & ASCII.LF &
            "    expenses:tax            200 JPY" & ASCII.LF &
            "    assets:cash           -2200 JPY" & ASCII.LF & ASCII.LF
          else
            "2026-08-19 Dinner" & ASCII.LF &
            "    expenses:food          2000 JPY" & ASCII.LF &
            "    assets:cash           -2000 JPY" & ASCII.LF & ASCII.LF) &
         "2026-08-25 Future Admitted Actual" & ASCII.LF &
         "    expenses:food          1000 JPY" & ASCII.LF &
         "    assets:cash           -1000 JPY" & ASCII.LF);

      Obs.Texts (Plan_Source) := To_Unbounded_String
        ((if Include_Multi_Posting then
            "2026-08-25 Planned Multi-Posting Payment" & ASCII.LF &
            "    ; plan-id: plan-multi-aug" & ASCII.LF &
            "    expenses:food          8000 JPY" & ASCII.LF &
            "    expenses:tax            800 JPY" & ASCII.LF &
            "    assets:bank           -8800 JPY" & ASCII.LF & ASCII.LF
          else
            "2026-08-25 Planned Utility Bill" & ASCII.LF &
            "    ; plan-id: plan-util-aug" & ASCII.LF &
            "    expenses:food          8000 JPY" & ASCII.LF &
            "    assets:bank           -8000 JPY" & ASCII.LF & ASCII.LF) &
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
   Put_Line ("--- Testing Household Home Presentation & Text Rendering ---");

   declare
      Sources : constant HRA.Canonical_Source.Source_Observation :=
        Make_Synthetic_Sources;
   begin
      Assert
        (HRA.Household.Admit_Canonical_Household (Sources, State, Error_Msg),
         "Admit synthetic Household state");
   end;

   declare
      use HRA.Household_Home_Presentation;
      use HRA.Household_Home_Text;
      Markers : HRA.Report_Config.Calendar_Markers :=
        (Cycle_End => '|', Plan_Due => '$', Issue_Due => '!', Multiple => '+');
      Att : Attention_Summary;
   begin
      Att := (Plan_Scheduled => Absent, Issue_Due => Absent, Cycle_End => Absent);
      Assert (Resolve_Marker (Att, Markers) = ' ', "All absent resolves to space");
      Att := (Plan_Scheduled => Present, Issue_Due => Absent, Cycle_End => Absent);
      Assert (Resolve_Marker (Att, Markers) = '$', "Plan only resolves to '$'");
      Att := (Plan_Scheduled => Absent, Issue_Due => Present, Cycle_End => Absent);
      Assert (Resolve_Marker (Att, Markers) = '!', "Issue only resolves to '!'");
      Att := (Plan_Scheduled => Absent, Issue_Due => Absent, Cycle_End => Present);
      Assert (Resolve_Marker (Att, Markers) = '|', "Cycle only resolves to '|'");
      Att := (Plan_Scheduled => Present, Issue_Due => Present, Cycle_End => Absent);
      Assert (Resolve_Marker (Att, Markers) = '+', "Plan + Issue resolves to '+'");
      Att := (Plan_Scheduled => Present, Issue_Due => Absent, Cycle_End => Present);
      Assert (Resolve_Marker (Att, Markers) = '+', "Plan + Cycle resolves to '+'");
      Att := (Plan_Scheduled => Absent, Issue_Due => Present, Cycle_End => Present);
      Assert (Resolve_Marker (Att, Markers) = '+', "Issue + Cycle resolves to '+'");
      Att := (Plan_Scheduled => Present, Issue_Due => Present, Cycle_End => Present);
      Assert (Resolve_Marker (Att, Markers) = '+', "All 3 present resolves to '+'");
      Att := (Plan_Scheduled => Present, Issue_Due => Unavailable, Cycle_End => Absent);
      Assert (Resolve_Marker (Att, Markers) = '$', "Plan present with Issue unavailable resolves to '$'");
      Att := (Plan_Scheduled => Absent, Issue_Due => Unavailable, Cycle_End => Unavailable);
      Assert (Resolve_Marker (Att, Markers) = ' ', "Only unavailables resolve to space");
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

   declare
      use HRA.Household_Home_Presentation;
      use HRA.Household_Home_Text;
      Cell : Calendar_Cell;
      Default_Markers : constant HRA.Report_Config.Calendar_Markers :=
        (Cycle_End => '|', Plan_Due => '$', Issue_Due => '!', Multiple => '+');
   begin
      Cell :=
        (Kind                => Dated_Cell,
         Date_Value          => D ("2026-08-05"),
         Is_Current_Month    => True,
         Is_Selected         => False,
         Is_Observed_Through => False,
         Is_Future           => False,
         Attention           => (others => Absent));
      Assert (Format_Cell (Cell, Default_Markers)'Length = 5,
              "Format_Cell 1-digit unselected no-marker length = 5");
      Assert (Format_Cell (Cell, Default_Markers) = "   5 ",
              "Format_Cell 1-digit unselected no-marker is '   5 '");
      Cell.Attention.Plan_Scheduled := Present;
      Assert (Format_Cell (Cell, Default_Markers)'Length = 5,
              "Format_Cell 1-digit unselected with marker length = 5");
      Assert (Format_Cell (Cell, Default_Markers) = "  5$ ",
              "Format_Cell 1-digit unselected with marker is '  5$ '");
      Cell.Is_Selected := True;
      Cell.Attention.Plan_Scheduled := Absent;
      Assert (Format_Cell (Cell, Default_Markers)'Length = 5,
              "Format_Cell 1-digit selected no-marker length = 5");
      Assert (Format_Cell (Cell, Default_Markers) = "[ 5] ",
              "Format_Cell 1-digit selected no-marker is '[ 5] '");
      Cell.Attention.Issue_Due := Present;
      Assert (Format_Cell (Cell, Default_Markers)'Length = 5,
              "Format_Cell 1-digit selected with marker length = 5");
      Assert (Format_Cell (Cell, Default_Markers) = "[ 5!]",
              "Format_Cell 1-digit selected with marker is '[ 5!]'");
      Cell :=
        (Kind                => Dated_Cell,
         Date_Value          => D ("2026-08-19"),
         Is_Current_Month    => True,
         Is_Selected         => False,
         Is_Observed_Through => True,
         Is_Future           => False,
         Attention           => (others => Absent));
      Assert (Format_Cell (Cell, Default_Markers)'Length = 5,
              "Format_Cell 2-digit unselected no-marker length = 5");
      Assert (Format_Cell (Cell, Default_Markers) = "  19 ",
              "Format_Cell 2-digit unselected no-marker is '  19 '");
      Cell.Attention.Plan_Scheduled := Present;
      Assert (Format_Cell (Cell, Default_Markers)'Length = 5,
              "Format_Cell 2-digit unselected with marker length = 5");
      Assert (Format_Cell (Cell, Default_Markers) = " 19$ ",
              "Format_Cell 2-digit unselected with marker is ' 19$ '");
      Cell.Is_Selected := True;
      Cell.Attention.Plan_Scheduled := Absent;
      Assert (Format_Cell (Cell, Default_Markers)'Length = 5,
              "Format_Cell 2-digit selected no-marker length = 5");
      Assert (Format_Cell (Cell, Default_Markers) = "[19] ",
              "Format_Cell 2-digit selected no-marker is '[19] '");
      Cell.Attention.Cycle_End := Present;
      Assert (Format_Cell (Cell, Default_Markers)'Length = 5,
              "Format_Cell 2-digit selected with marker length = 5");
      Assert (Format_Cell (Cell, Default_Markers) = "[19|]",
              "Format_Cell 2-digit selected with marker is '[19|]'");
      declare
         Pad_Cell : constant Calendar_Cell := (Kind => Out_Of_Range_Padding);
      begin
         Assert (Format_Cell (Pad_Cell)'Length = 5,
                 "Out_Of_Range_Padding Format_Cell has length = 5");
         Assert (Format_Cell (Pad_Cell) = "     ",
                 "Out_Of_Range_Padding Format_Cell is exactly 5 spaces");
      end;
   end;

   declare
      use HRA.Household_Home_Observation;
      use HRA.Household_Home_Presentation;
      use HRA.Household_Home_Text;
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
      declare
         W1 : constant Calendar_Week := Grid.Weeks.Element (1);
      begin
         Assert (W1 (HRA.Dates.Monday).Kind = Dated_Cell,
                 "Week 1 Monday is a Dated_Cell");
         Assert (W1 (HRA.Dates.Monday).Date_Value = D ("2026-07-27"),
                 "Week 1 Monday is 2026-07-27 (previous month padding)");
         Assert (not W1 (HRA.Dates.Monday).Is_Current_Month,
                 "2026-07-27 is not current month");
         Assert (W1 (HRA.Dates.Saturday).Kind = Dated_Cell,
                 "Week 1 Saturday is a Dated_Cell");
         Assert (W1 (HRA.Dates.Saturday).Date_Value = D ("2026-08-01"),
                 "Week 1 Saturday is 2026-08-01 (first day of August)");
         Assert (W1 (HRA.Dates.Saturday).Is_Current_Month,
                 "2026-08-01 is current month");
         Assert (W1 (HRA.Dates.Sunday).Date_Value = D ("2026-08-02"),
                 "Week 1 Sunday is 2026-08-02");
      end;
      declare
         W4 : constant Calendar_Week := Grid.Weeks.Element (4);
      begin
         Assert (W4 (HRA.Dates.Wednesday).Kind = Dated_Cell,
                 "Week 4 Wednesday is Dated_Cell");
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
      declare
         W5 : constant Calendar_Week := Grid.Weeks.Element (5);
      begin
         Assert (W5 (HRA.Dates.Tuesday).Date_Value = D ("2026-08-25"),
                 "Week 5 Tuesday is 2026-08-25");
         Assert (W5 (HRA.Dates.Tuesday).Attention.Plan_Scheduled = Present,
                 "2026-08-25 has Plan_Scheduled = Present");
         Assert (W5 (HRA.Dates.Tuesday).Attention.Issue_Due = Present,
                 "2026-08-25 has Issue_Due = Present");
         Assert (Resolve_Marker (W5 (HRA.Dates.Tuesday).Attention) = '+',
                 "2026-08-25 resolves to '+' marker");
         Assert (W5 (HRA.Dates.Sunday).Date_Value = D ("2026-08-30"),
                 "Week 5 Sunday is 2026-08-30");
         Assert (W5 (HRA.Dates.Sunday).Attention.Cycle_End = Present,
                 "2026-08-30 has Cycle_End = Present");
         Assert (Resolve_Marker (W5 (HRA.Dates.Sunday).Attention) = '|',
                 "2026-08-30 resolves to '|' marker");
      end;
      declare
         W6 : constant Calendar_Week := Grid.Weeks.Element (6);
      begin
         Assert (W6 (HRA.Dates.Monday).Date_Value = D ("2026-08-31"),
                 "Week 6 Monday is 2026-08-31");
         Assert (W6 (HRA.Dates.Monday).Is_Current_Month,
                 "2026-08-31 is current month");
         Assert (Resolve_Marker (W6 (HRA.Dates.Monday).Attention) = '$',
                 "2026-08-31 resolves to '$' marker");
         Assert (W6 (HRA.Dates.Tuesday).Kind = Dated_Cell,
                 "Week 6 Tuesday is Dated_Cell");
         Assert (W6 (HRA.Dates.Tuesday).Date_Value = D ("2026-09-01"),
                 "Week 6 Tuesday is 2026-09-01 (next month padding retains real date)");
         Assert (not W6 (HRA.Dates.Tuesday).Is_Current_Month,
                 "2026-09-01 is not current month");
         Assert (W6 (HRA.Dates.Sunday).Kind = Dated_Cell,
                 "Week 6 Sunday is Dated_Cell");
         Assert (W6 (HRA.Dates.Sunday).Date_Value = D ("2026-09-06"),
                 "Week 6 Sunday is 2026-09-06 (next month padding retains real date)");
      end;
      declare
         Grid_Text : constant String := Render_Calendar_Grid (Grid);
      begin
         Assert (Grid_Text'Length > 0, "Render_Calendar_Grid produces non-empty output");
      end;
   end;

   declare
      use HRA.Household_Home_Observation;
      use HRA.Household_Home_Presentation;
      use HRA.Household_Home_Text;
      Obs_Max : constant Home_Observation :=
        Observe
          (Observed_Through => D ("9999-12-01"),
           Selected_Day     => D ("9999-12-31"),
           State            => State);
      Pres_Max : constant Home_Presentation := Present (Obs_Max);
      Grid_Max : constant Calendar_Grid := Pres_Max.Calendar;
      Last_Wk  : constant Calendar_Week :=
        Grid_Max.Weeks.Element (Natural (Grid_Max.Weeks.Length));
   begin
      Assert (Grid_Max.Year = 9999 and then Grid_Max.Month = 12,
              "9999-12 calendar generated without exception");
      Assert (HRA.Dates.Day_Of_Week_Of (D ("9999-12-31")) = HRA.Dates.Friday,
              "9999-12-31 is Friday");
      Assert (Last_Wk (HRA.Dates.Friday).Kind = Dated_Cell,
              "9999-12 last week Friday is Dated_Cell");
      Assert (Last_Wk (HRA.Dates.Friday).Date_Value = D ("9999-12-31"),
              "9999-12 last week Friday Date_Value = 9999-12-31");
      Assert (Last_Wk (HRA.Dates.Friday).Is_Selected,
              "9999-12-31 is selected");
      Assert (Last_Wk (HRA.Dates.Saturday).Kind = Out_Of_Range_Padding,
              "9999-12 last week Saturday is Out_Of_Range_Padding");
      Assert (Last_Wk (HRA.Dates.Sunday).Kind = Out_Of_Range_Padding,
              "9999-12 last week Sunday is Out_Of_Range_Padding");
      Assert (Format_Cell (Last_Wk (HRA.Dates.Saturday)) = "     ",
              "9999-12 Saturday padding formats to exactly 5 spaces");
      Assert (Format_Cell (Last_Wk (HRA.Dates.Sunday)) = "     ",
              "9999-12 Sunday padding formats to exactly 5 spaces");
      declare
         Obs_Min : constant Home_Observation :=
           Observe
             (Observed_Through => D ("0001-01-01"),
              Selected_Day     => D ("0001-01-01"),
              State            => State);
         Pres_Min : constant Home_Presentation := Present (Obs_Min);
         Grid_Min : constant Calendar_Grid := Pres_Min.Calendar;
         W1_Min   : constant Calendar_Week := Grid_Min.Weeks.Element (1);
      begin
         Assert (Grid_Min.Year = 1 and then Grid_Min.Month = 1,
                 "0001-01 calendar generated without exception");
         Assert (W1_Min (HRA.Dates.Monday).Kind = Dated_Cell,
                 "0001-01 Monday is Dated_Cell");
         Assert (W1_Min (HRA.Dates.Monday).Date_Value = D ("0001-01-01"),
                 "0001-01-01 is Monday (origin of Gregorian calendar)");
      end;
   end;

   declare
      use HRA.Household_Home_Observation;
      use HRA.Household_Home_Presentation;
      Obs_Today : constant Home_Observation :=
        Observe
          (Observed_Through => D ("2026-08-19"),
           Selected_Day     => D ("2026-08-19"),
           State            => State);
      Pres_Today : constant Home_Presentation := Present (Obs_Today);
   begin
      Assert (Pres_Today.Actual.Status = Available, "Actual is Available");
      Assert (Natural (Pres_Today.Actual.Items.Length) = 1, "1 Actual transaction on 2026-08-19");
      declare
         Item : constant Actual_Item := Pres_Today.Actual.Items.Element (1);
      begin
         Assert (Item.Date = D ("2026-08-19"),
                 "Actual_Item Date is typed Date 2026-08-19");
         Assert (To_String (Item.Description) = "Dinner with 3 Postings",
                 "Description is 'Dinner with 3 Postings'");
         Assert (Natural (Item.Postings.Length) = 3,
                 "Actual_Item contains exactly 3 structured postings");
         Assert (HRA.Account.Name (Item.Postings.Element (1).Account) = "expenses:food",
                 "First posting account is expenses:food");
         Assert (Item.Postings.Element (1).Amount.Val = 2000.0,
                 "First posting amount is 2000");
         Assert (HRA.Account.Name (Item.Postings.Element (2).Account) = "expenses:tax",
                 "Second posting account is expenses:tax");
         Assert (Item.Postings.Element (2).Amount.Val = 200.0,
                 "Second posting amount is 200");
         Assert (HRA.Account.Name (Item.Postings.Element (3).Account) = "assets:cash",
                 "Third posting account is assets:cash");
         Assert (Item.Postings.Element (3).Amount.Val = -2200.0,
                 "Third posting amount is -2200");
      end;
      declare
         Obs_Future : constant Home_Observation :=
           Observe
             (Observed_Through => D ("2026-08-19"),
              Selected_Day     => D ("2026-08-25"),
              State            => State);
         Pres_Future : constant Home_Presentation := Present (Obs_Future);
      begin
         Assert (Pres_Future.Plan.Status = Available, "Plan is Available on 2026-08-25");
         Assert (Natural (Pres_Future.Plan.Items.Length) = 1, "1 Plan item on 2026-08-25");
         declare
            P_Item : constant Plan_Item := Pres_Future.Plan.Items.Element (1);
         begin
            Assert (HRA.Plan.Text (P_Item.Plan_Id) = "plan-multi-aug",
                    "Plan Id is typed plan-multi-aug");
            Assert (P_Item.Scheduled_Date = D ("2026-08-25"),
                    "Plan Scheduled_Date is typed Date 2026-08-25");
            Assert (To_String (P_Item.Description) = "Planned Multi-Posting Payment",
                    "Plan description matches");
            Assert (Natural (P_Item.Postings.Length) = 3,
                    "Plan has 3 structured postings preserved");
            Assert (HRA.Account.Name (P_Item.Postings.Element (1).Account) = "expenses:food",
                    "First plan posting is expenses:food");
            Assert (P_Item.Postings.Element (1).Amount.Val = 8000.0,
                    "First plan posting amount is 8000");
            Assert (HRA.Account.Name (P_Item.Postings.Element (2).Account) = "expenses:tax",
                    "Second plan posting is expenses:tax");
            Assert (P_Item.Postings.Element (2).Amount.Val = 800.0,
                    "Second plan posting amount is 800");
            Assert (HRA.Account.Name (P_Item.Postings.Element (3).Account) = "assets:bank",
                    "Third plan posting is assets:bank");
            Assert (P_Item.Postings.Element (3).Amount.Val = -8800.0,
                    "Third plan posting amount is -8800");
         end;
      end;
   end;

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
      Assert (Pres.Cycle.Status = Available,
              "Cycle presentation is Available");
      Assert (Pres.Cycle.Focus_Role = Current_Cycle,
              "Role on 2026-08-19 is enum Current_Cycle");
      Assert (HRA.Dates.First (Pres.Cycle.Previous_Window) = D ("2026-07-25"),
              "Previous window starts on 2026-07-25");
      Assert (HRA.Dates.First (Pres.Cycle.Current_Window) = D ("2026-08-01"),
              "Current window starts on 2026-08-01");
      declare
         Obs_Fut : constant Home_Observation :=
           Observe
             (Observed_Through => D ("2026-08-19"),
              Selected_Day     => D ("2026-08-25"),
              State            => State);
         Pres_Fut : constant Home_Presentation := Present (Obs_Fut);
      begin
         Assert (Pres_Fut.Is_Future_Focus, "Is_Future_Focus is True on 2026-08-25");
         Assert (Pres_Fut.Actual.Status = Unavailable,
                 "Actual is Unavailable on future focus day");
         Assert ((case Pres_Fut.Actual.Reason is when Observation_Horizon_Exceeded => True),
                 "Actual unavailable reason is Observation_Horizon_Exceeded");
         Assert (Pres_Fut.Issue.Status = Available, "Issue is Available");
         Assert (Natural (Pres_Fut.Issue.Items.Length) = 2, "2 due issues on 2026-08-25");
         declare
            I1 : constant Issue_Item := Pres_Fut.Issue.Items.Element (1);
            I2 : constant Issue_Item := Pres_Fut.Issue.Items.Element (2);
         begin
            Assert (HRA.Issues.Text (I1.Issue_Id) = "ISSUE-1",
                    "First issue ID is typed ISSUE-1");
            Assert (I1.Status_As_Of = HRA.Issue_Observation.Open,
                    "First issue status is typed Open");
            Assert (I1.Due_Date = D ("2026-08-25"),
                    "First issue due date is typed 2026-08-25");
            Assert (I1.Amount.Has_Amount and then I1.Amount.Value.Val = 10000.0,
                    "First issue amount is typed 10000 JPY");
            Assert (To_String (I1.Title) = "Tax Payment",
                    "First issue title matches");
            Assert (To_String (I1.Category) = "tax",
                    "First issue category matches");
            Assert (To_String (I1.Details) = "city tax",
                    "First issue details match");
            Assert (HRA.Issues.Text (I2.Issue_Id) = "ISSUE-2",
                    "Second issue ID is typed ISSUE-2");
            Assert (I2.Status_As_Of = HRA.Issue_Observation.Open,
                    "Second issue (closed in future) has Status_As_Of = Open as-of 2026-08-19");
            Assert (I2.Due_Date = D ("2026-08-25"),
                    "Second issue due date is typed 2026-08-25");
            Assert (I2.Amount.Has_Amount and then I2.Amount.Value.Val = 3000.0,
                    "Second issue amount is typed 3000 JPY");
         end;
      end;
      declare
         Obs_Later : constant Home_Observation :=
           Observe
             (Observed_Through => D ("2026-08-25"),
              Selected_Day     => D ("2026-08-25"),
              State            => State);
         Pres_Later : constant Home_Presentation := Present (Obs_Later);
      begin
         Assert (Natural (Pres_Later.Issue.Items.Length) = 2,
                 "2 due issues on 2026-08-25 as of 2026-08-25 (ISSUE-1 and newly visible ISSUE-4)");
         declare
            I1_Later : constant Issue_Item := Pres_Later.Issue.Items.Element (1);
            I2_Later : constant Issue_Item := Pres_Later.Issue.Items.Element (2);
         begin
            Assert (HRA.Issues.Text (I1_Later.Issue_Id) = "ISSUE-1",
                    "First due issue is ISSUE-1");
            Assert (I1_Later.Status_As_Of = HRA.Issue_Observation.Open,
                    "ISSUE-1 remains Open");
            Assert (HRA.Issues.Text (I2_Later.Issue_Id) = "ISSUE-4",
                    "Second due issue is newly visible ISSUE-4");
            Assert (I2_Later.Status_As_Of = HRA.Issue_Observation.Open,
                    "ISSUE-4 is Open");
         end;
      end;
   end;

   declare
      use HRA.Household_Home_Observation;
      use HRA.Household_Home_Presentation;
      use HRA.Household_Home_Text;
      Obs_Curr_End : constant Home_Observation :=
        Observe
          (Observed_Through => D ("2026-08-19"),
           Selected_Day     => D ("2026-08-30"),
           State            => State);
      Pres_Curr_End : constant Home_Presentation := Present (Obs_Curr_End);
      Obs_Prev_End : constant Home_Observation :=
        Observe
          (Observed_Through => D ("2026-08-19"),
           Selected_Day     => D ("2026-07-31"),
           State            => State);
      Pres_Prev_End : constant Home_Presentation := Present (Obs_Prev_End);
      Obs_Prev : constant Home_Observation :=
        Observe
          (Observed_Through => D ("2026-08-19"),
           Selected_Day     => D ("2026-07-28"),
           State            => State);
      Pres_Prev : constant Home_Presentation := Present (Obs_Prev);
      Obs_Outside : constant Home_Observation :=
        Observe
          (Observed_Through => D ("2026-08-19"),
           Selected_Day     => D ("2026-07-10"),
           State            => State);
      Pres_Outside : constant Home_Presentation := Present (Obs_Outside);
   begin
      Assert (Pres_Curr_End.Cycle.Focus_Role = Current_Cycle_End,
              "Focus on 2026-08-30 is enum Current_Cycle_End");
      Assert (Pres_Prev_End.Cycle.Focus_Role = Previous_Cycle_End,
              "Focus on 2026-07-31 is enum Previous_Cycle_End");
      Assert (Pres_Prev.Cycle.Focus_Role = Previous_Cycle,
              "Focus on 2026-07-28 is enum Previous_Cycle");
      Assert (Pres_Outside.Cycle.Focus_Role = Outside_Known_Cycles,
              "Focus on 2026-07-10 is enum Outside_Known_Cycles");
      Assert (Render_Home (Pres_Curr_End)'Length > 0, "Render Current_Cycle_End");
      Assert (Render_Home (Pres_Prev_End)'Length > 0, "Render Previous_Cycle_End");
      Assert (Render_Home (Pres_Prev)'Length > 0, "Render Previous_Cycle");
      Assert (Render_Home (Pres_Outside)'Length > 0, "Render Outside_Known_Cycles");
   end;

   declare
      D_2026_08_19 : constant HRA.Dates.Date := D ("2026-08-19");
      D_2024_02_15 : constant HRA.Dates.Date := D ("2024-02-15");
      D_2026_02_10 : constant HRA.Dates.Date := D ("2026-02-10");
   begin
      Assert (HRA.Dates.Image (HRA.Dates.First_Of_Month (D_2026_08_19)) = "2026-08-01",
              "First_Of_Month (2026-08-19) = 2026-08-01");
      Assert (HRA.Dates.Image (HRA.Dates.Last_Of_Month (D_2026_08_19)) = "2026-08-31",
              "Last_Of_Month (2026-08-19) = 2026-08-31");
      Assert (HRA.Dates.Image (HRA.Dates.Last_Of_Month (D_2024_02_15)) = "2024-02-29",
              "Last_Of_Month (2024-02-15) = 2024-02-29 (Leap February)");
      Assert (HRA.Dates.Image (HRA.Dates.Last_Of_Month (D_2026_02_10)) = "2026-02-28",
              "Last_Of_Month (2026-02-10) = 2026-02-28 (Common February)");
   end;

   declare
      use HRA.Household_Home_Observation;
      use HRA.Household_Home_Presentation;
      use HRA.Household_Home_Text;
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

   declare
      use HRA.Household_Home_Observation;
      use HRA.Household_Home_Presentation;
      use HRA.Household_Home_Text;
      Sources_Undet : constant HRA.Canonical_Source.Source_Observation :=
        Make_Synthetic_Sources (Include_Undetermined_Issue => True);
      State_Undet   : HRA.Household.Household_State;
      Diag_Msg      : Unbounded_String;
   begin
      Assert
        (HRA.Household.Admit_Canonical_Household (Sources_Undet, State_Undet, Diag_Msg),
         "Admit state with undetermined issue");
      declare
         Obs_Undet  : constant Home_Observation :=
           Observe (D ("2026-08-19"), D ("2026-08-25"), State_Undet);
         Pres_Undet : constant Home_Presentation := Present (Obs_Undet);
      begin
         Assert (Pres_Undet.Issue.Status = Unavailable,
                 "Issue presentation is Unavailable when closure undetermined");
         Assert ((case Pres_Undet.Issue.Reason is when Closure_Timing_Undetermined => True),
                 "Issue unavailable reason is Closure_Timing_Undetermined");
         Assert (Render_Home (Pres_Undet)'Length > 0,
                 "Render_Home with unavailable issue produces diagnostic text");
      end;
   end;

   declare
      use HRA.Household_Home_Observation;
      use HRA.Household_Home_Presentation;
      use HRA.Household_Home_Text;
      Broken_State : HRA.Household.Household_State := State;
   begin
      Broken_State.Plan_Evidence.Transactions.Clear;
      declare
         Obs_Broken  : constant Home_Observation :=
           Observe (D ("2026-08-19"), D ("2026-08-25"), Broken_State);
         Pres_Broken : constant Home_Presentation := Present (Obs_Broken);
      begin
         Assert (Pres_Broken.Plan.Status = Unavailable,
                 "Plan presentation is Unavailable when Plan evidence missing");
         Assert (Pres_Broken.Plan.Diagnostic.Status =
                   HRA.Plan_Observation.Plan_Source_Evidence_Error,
                 "Plan diagnostic retains exact Plan_Source_Evidence_Error");
         Assert (Pres_Broken.Cycle.Status = Unavailable,
                 "Cycle presentation is Unavailable when Plan dependency fails");
         Assert (Pres_Broken.Cycle.Failure.Reason = Plan_Dependency_Unavailable,
                 "Cycle failure reason is Plan_Dependency_Unavailable");
         Assert (Pres_Broken.Cycle.Failure.Plan_Error.Status =
                   HRA.Plan_Observation.Plan_Source_Evidence_Error,
                 "Cycle failure diagnostic retains exact upstream error");
         Assert (Render_Home (Pres_Broken)'Length > 0,
                 "Render_Home with broken plan/cycle produces diagnostic text");
      end;
   end;

   declare
      use HRA.Household_Home_Observation;
      use HRA.Household_Home_Presentation;
      use HRA.Household_Home_Text;
      Sources_No_Anchor : constant HRA.Canonical_Source.Source_Observation :=
        Make_Synthetic_Sources (Include_Future_Plan_Anchor => False);
      State_No_Anchor   : HRA.Household.Household_State;
      Diag_Msg          : Unbounded_String;
   begin
      Assert
        (HRA.Household.Admit_Canonical_Household (Sources_No_Anchor, State_No_Anchor, Diag_Msg),
         "Admit state without future plan anchor");
      declare
         Obs_No_Anchor  : constant Home_Observation :=
           Observe (D ("2026-08-19"), D ("2026-08-19"), State_No_Anchor);
         Pres_No_Anchor : constant Home_Presentation := Present (Obs_No_Anchor);
      begin
         Assert (Pres_No_Anchor.Cycle.Status = Unavailable,
                 "Cycle presentation is Unavailable when anchor missing");
         Assert (Pres_No_Anchor.Cycle.Failure.Reason = Cycle_Resolution_Failed,
                 "Cycle failure reason is Cycle_Resolution_Failed");
         Assert (Pres_No_Anchor.Cycle.Failure.Cycle_Error =
                   HRA.Cycle_Observation.Missing_Future_Plan_Anchor,
                 "Cycle error is Missing_Future_Plan_Anchor");
         Assert (Render_Home (Pres_No_Anchor)'Length > 0,
                 "Render_Home with cycle resolution failure produces diagnostic text");
      end;
   end;

   declare
      use HRA.Household_Home_Observation;
      use HRA.Household_Home_Presentation;
      Obs : constant Home_Observation :=
        Observe (D ("2026-08-19"), D ("2026-08-19"), State);
      Pres : constant Home_Presentation := Present (Obs);
   begin
      if Pres.Actual.Status = Available then
         for Item of Pres.Actual.Items loop
            Assert (Item.Date = D ("2026-08-19"), "GUI reads typed Date without string parsing");
            for P of Item.Postings loop
               Assert (HRA.Account.Name (P.Account)'Length > 0,
                       "GUI inspects Account directly from Posting_Item");
               Assert (P.Amount.Val /= 0.0,
                       "GUI inspects Amount Quantity directly without parsing currency string");
            end loop;
         end loop;
      end if;
      if Pres.Cycle.Status = Available then
         Assert (Pres.Cycle.Focus_Role = Current_Cycle,
                 "GUI evaluates Cycle_Focus_Role enum directly");
         Assert (HRA.Dates.First (Pres.Cycle.Current_Window) <= Pres.Selected_Day,
                 "GUI tests period bounds with typed dates");
      end if;
      Assert (Pres.Attention.Plan_Scheduled = Absent,
              "GUI checks Plan_Scheduled Attention_State enum directly");
   end;

   Put_Line ("--------------------------------------------------");
   Put_Line ("Summary: Passed = " & Natural'Image (Passed_Count) &
             ", Failed = " & Natural'Image (Failed_Count));

   if Failed_Count > 0 then
      raise Program_Error with "Household Home presentation tests failed";
   end if;
end Test_Household_Home_Presentation;