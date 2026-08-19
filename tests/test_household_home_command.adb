with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;           use Ada.Strings.Unbounded;
with Ada.Text_IO;                     use Ada.Text_IO;
with HRA.Canonical_Source;            use HRA.Canonical_Source;
with HRA.Dates;                       use type HRA.Dates.Date;
with HRA.Household;
with HRA.Household_Check_Observation;
with HRA.Household_Report_Observation;
with HRA.Household_Home_Command;      use HRA.Household_Home_Command;
with HRA.Household_Home_Observation;
with HRA.Household_Home_Presentation;
with HRA.Household_Home_Text;

procedure Test_Household_Home_Command is
   use type HRA.Household_Home_Command.Parse_Status;
   use type HRA.Household_Home_Command.Date_Option_Source;

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

   function D (Text : String) return HRA.Dates.Date is
      Value  : HRA.Dates.Date;
      Status : HRA.Dates.Date_Status;
   begin
      if not HRA.Dates.Parse (Text, Value, Status) then
         raise Program_Error with "invalid synthetic date: " & Text;
      end if;
      return Value;
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

   function Make_Synthetic_Sources return HRA.Canonical_Source.Source_Observation is
      Obs : HRA.Canonical_Source.Source_Observation;
   begin
      Obs.Root_Path := To_Unbounded_String ("/tmp/hra_test_home_command");
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
         "2026-08-19 Dinner with 3 Postings" & ASCII.LF &
         "    expenses:food          2000 JPY" & ASCII.LF &
         "    expenses:tax            200 JPY" & ASCII.LF &
         "    assets:cash           -2200 JPY" & ASCII.LF & ASCII.LF &
         "2026-08-25 Future Admitted Actual" & ASCII.LF &
         "    expenses:food          1000 JPY" & ASCII.LF &
         "    assets:cash           -1000 JPY" & ASCII.LF);

      Obs.Texts (Plan_Source) := To_Unbounded_String
        ("2026-08-25 Planned Multi-Posting Payment" & ASCII.LF &
         "    ; plan-id: plan-multi-aug" & ASCII.LF &
         "    expenses:food          8000 JPY" & ASCII.LF &
         "    expenses:tax            800 JPY" & ASCII.LF &
         "    assets:bank           -8800 JPY" & ASCII.LF & ASCII.LF &
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
         "Tax Payment" & ASCII.HT & "10000" & ASCII.HT & "JPY" & ASCII.HT &
         "city tax" & ASCII.LF);

      return Obs;
   end Make_Synthetic_Sources;

begin
   Put_Line ("--- Testing HRA.Household_Home_Command & Application Surface ---");

   --  ========================================================================
   --  1. Stage A: Pure CLI Argument Parsing & Validation
   --  ========================================================================
   declare
   begin
      --  1a. Empty CLI args (home command with all defaults)
      declare
         Args : String_Array (1 .. 0);
         Res  : constant Parse_Resolution := Parse_Arguments (Args);
      begin
         Assert (Res.Status = Success, "Parse_Arguments on empty args succeeds");
         Assert (not Res.Parsed.Has_Base, "Empty args has no explicit base");
         Assert (not Res.Parsed.Has_Through, "Empty args has no explicit through");
         Assert (not Res.Parsed.Has_Day, "Empty args has no explicit day");
         Assert (Length (Res.Parsed.Base_Directory) = 0, "Base directory empty by default");
         Assert (Needs_Clock (Res.Parsed), "Empty args requires clock read");
      end;

      --  1b. Order A: --base then --through then --day
      declare
         Args : constant String_Array :=
           [1 => To_Unbounded_String ("--base"),
            2 => To_Unbounded_String ("/canonical/root"),
            3 => To_Unbounded_String ("--through"),
            4 => To_Unbounded_String ("2026-08-19"),
            5 => To_Unbounded_String ("--day"),
            6 => To_Unbounded_String ("2026-08-25")];
         Res  : constant Parse_Resolution := Parse_Arguments (Args);
      begin
         Assert (Res.Status = Success, "Parse_Arguments order A succeeds");
         Assert (To_String (Res.Parsed.Base_Directory) = "/canonical/root",
                 "Base directory parsed: /canonical/root");
         Assert (Res.Parsed.Has_Base, "Order A has explicit base");
         Assert (Res.Parsed.Has_Through, "Order A has explicit through");
         Assert (Res.Parsed.Through_Date = D ("2026-08-19"),
                 "Through_Date is 2026-08-19");
         Assert (Res.Parsed.Has_Day, "Order A has explicit day");
         Assert (Res.Parsed.Day_Date = D ("2026-08-25"),
                 "Day_Date is 2026-08-25");
         Assert (not Needs_Clock (Res.Parsed), "Order A with explicit through does not need clock");
      end;

      --  1c. Order B: --day then --base then --through (order independent)
      declare
         Args : constant String_Array :=
           [1 => To_Unbounded_String ("--day"),
            2 => To_Unbounded_String ("2026-08-25"),
            3 => To_Unbounded_String ("--base"),
            4 => To_Unbounded_String ("/canonical/root"),
            5 => To_Unbounded_String ("--through"),
            6 => To_Unbounded_String ("2026-08-19")];
         Res  : constant Parse_Resolution := Parse_Arguments (Args);
      begin
         Assert (Res.Status = Success, "Parse_Arguments order B succeeds");
         Assert (To_String (Res.Parsed.Base_Directory) = "/canonical/root",
                 "Base directory parsed correctly in order B");
         Assert (Res.Parsed.Through_Date = D ("2026-08-19"),
                 "Through_Date is 2026-08-19 in order B");
         Assert (Res.Parsed.Day_Date = D ("2026-08-25"),
                 "Day_Date is 2026-08-25 in order B");
         Assert (not Needs_Clock (Res.Parsed), "Order B does not need clock");
      end;

      --  1d. Missing option values at end of argv fail closed
      declare
         Args_No_Base_Val : constant String_Array :=
           [1 => To_Unbounded_String ("--base")];
         Args_No_Through_Val : constant String_Array :=
           [1 => To_Unbounded_String ("--through")];
         Args_No_Day_Val : constant String_Array :=
           [1 => To_Unbounded_String ("--day")];
         Res1 : constant Parse_Resolution := Parse_Arguments (Args_No_Base_Val);
         Res2 : constant Parse_Resolution := Parse_Arguments (Args_No_Through_Val);
         Res3 : constant Parse_Resolution := Parse_Arguments (Args_No_Day_Val);
      begin
         Assert (Res1.Status = Missing_Option_Value,
                 "Parse_Arguments fails on missing --base value at end");
         Assert (To_String (Res1.Message) = "missing value for option --base",
                 "Missing --base diagnostic message");
         Assert (Res2.Status = Missing_Option_Value,
                 "Parse_Arguments fails on missing --through value at end");
         Assert (To_String (Res2.Message) = "missing value for option --through",
                 "Missing --through diagnostic message");
         Assert (Res3.Status = Missing_Option_Value,
                 "Parse_Arguments fails on missing --day value at end");
         Assert (To_String (Res3.Message) = "missing value for option --day",
                 "Missing --day diagnostic message");
      end;

      --  1e. Missing option values followed by another option token fail closed
      declare
         Args_Through_Followed_By_Day : constant String_Array :=
           [1 => To_Unbounded_String ("--through"),
            2 => To_Unbounded_String ("--day"),
            3 => To_Unbounded_String ("2026-08-25")];
         Args_Base_Followed_By_Through : constant String_Array :=
           [1 => To_Unbounded_String ("--base"),
            2 => To_Unbounded_String ("--through"),
            3 => To_Unbounded_String ("2026-08-19")];
         Args_Day_Followed_By_Base : constant String_Array :=
           [1 => To_Unbounded_String ("--day"),
            2 => To_Unbounded_String ("--base"),
            3 => To_Unbounded_String ("/canonical/root")];
         Res1 : constant Parse_Resolution := Parse_Arguments (Args_Through_Followed_By_Day);
         Res2 : constant Parse_Resolution := Parse_Arguments (Args_Base_Followed_By_Through);
         Res3 : constant Parse_Resolution := Parse_Arguments (Args_Day_Followed_By_Base);
      begin
         Assert (Res1.Status = Missing_Option_Value,
                 "Parse_Arguments diagnoses --through followed by --day as Missing_Option_Value");
         Assert (To_String (Res1.Message) = "missing value for option --through",
                 "Missing --through followed by option message");
         Assert (Res2.Status = Missing_Option_Value,
                 "Parse_Arguments diagnoses --base followed by --through as Missing_Option_Value");
         Assert (To_String (Res2.Message) = "missing value for option --base",
                 "Missing --base followed by option message");
         Assert (Res3.Status = Missing_Option_Value,
                 "Parse_Arguments diagnoses --day followed by --base as Missing_Option_Value");
         Assert (To_String (Res3.Message) = "missing value for option --day",
                 "Missing --day followed by option message");
      end;

      --  1f. Duplicate options fail closed as ambiguous CLI input
      declare
         Args_Dup_Through : constant String_Array :=
           [1 => To_Unbounded_String ("--through"),
            2 => To_Unbounded_String ("2026-08-19"),
            3 => To_Unbounded_String ("--through"),
            4 => To_Unbounded_String ("2026-08-20")];
         Args_Dup_Day : constant String_Array :=
           [1 => To_Unbounded_String ("--day"),
            2 => To_Unbounded_String ("2026-08-25"),
            3 => To_Unbounded_String ("--day"),
            4 => To_Unbounded_String ("2026-08-26")];
         Args_Dup_Base : constant String_Array :=
           [1 => To_Unbounded_String ("--base"),
            2 => To_Unbounded_String ("/root1"),
            3 => To_Unbounded_String ("--base"),
            4 => To_Unbounded_String ("/root2")];
         Res1 : constant Parse_Resolution := Parse_Arguments (Args_Dup_Through);
         Res2 : constant Parse_Resolution := Parse_Arguments (Args_Dup_Day);
         Res3 : constant Parse_Resolution := Parse_Arguments (Args_Dup_Base);
      begin
         Assert (Res1.Status = Duplicate_Option,
                 "Duplicate --through rejected as Duplicate_Option");
         Assert (To_String (Res1.Message) = "duplicate option: --through",
                 "Duplicate --through diagnostic message");
         Assert (Res2.Status = Duplicate_Option,
                 "Duplicate --day rejected as Duplicate_Option");
         Assert (To_String (Res2.Message) = "duplicate option: --day",
                 "Duplicate --day diagnostic message");
         Assert (Res3.Status = Duplicate_Option,
                 "Duplicate --base rejected as Duplicate_Option");
         Assert (To_String (Res3.Message) = "duplicate option: --base",
                 "Duplicate --base diagnostic message");
      end;

      --  1g. Invalid Gregorian dates rejected during Stage A before Household load
      declare
         Args_Bad_Through : constant String_Array :=
           [1 => To_Unbounded_String ("--through"),
            2 => To_Unbounded_String ("2026-02-30")];
         Args_Bad_Day : constant String_Array :=
           [1 => To_Unbounded_String ("--day"),
            2 => To_Unbounded_String ("not-a-date")];
         Res1 : constant Parse_Resolution := Parse_Arguments (Args_Bad_Through);
         Res2 : constant Parse_Resolution := Parse_Arguments (Args_Bad_Day);
      begin
         Assert (Res1.Status = Invalid_Through_Date,
                 "Parse_Arguments rejects 2026-02-30 as Invalid_Through_Date");
         Assert (Ada.Strings.Fixed.Index (To_String (Res1.Message), "2026-02-30") > 0,
                 "Invalid through date diagnostic contains bad date string");
         Assert (Res2.Status = Invalid_Day_Date,
                 "Parse_Arguments rejects not-a-date as Invalid_Day_Date");
         Assert (Ada.Strings.Fixed.Index (To_String (Res2.Message), "not-a-date") > 0,
                 "Invalid day date diagnostic contains bad date string");
      end;

      --  1h. Unknown options fail closed
      declare
         Args_Unknown : constant String_Array :=
           [1 => To_Unbounded_String ("--unknown-option")];
         Args_Positional : constant String_Array :=
           [1 => To_Unbounded_String ("unexpected_arg")];
         Res1 : constant Parse_Resolution := Parse_Arguments (Args_Unknown);
         Res2 : constant Parse_Resolution := Parse_Arguments (Args_Positional);
      begin
         Assert (Res1.Status = Unknown_Option,
                 "Parse_Arguments fails on unknown option");
         Assert (To_String (Res1.Message) = "unknown option: --unknown-option",
                 "Unknown option diagnostic message");
         Assert (Res2.Status = Unknown_Option,
                 "Parse_Arguments fails on unexpected positional argument");
         Assert (To_String (Res2.Message) = "unknown option: unexpected_arg",
                 "Unexpected argument diagnostic message");
      end;
   end;

   --  ========================================================================
   --  2. Stage B: Temporal Defaults Resolution & Clock Inquiry Law
   --  ========================================================================
   declare
      Injected_Today : constant HRA.Dates.Date := D ("2026-08-19");
   begin
      --  2a. Explicit through only: clock NOT needed (0 clock reads), day follows through
      declare
         Args : constant String_Array :=
           [1 => To_Unbounded_String ("--through"),
            2 => To_Unbounded_String ("2026-08-15")];
         Parse_Res : constant Parse_Resolution := Parse_Arguments (Args);
      begin
         Assert (Parse_Res.Status = Success, "Stage A parse succeeds for explicit through");
         Assert (not Needs_Clock (Parse_Res.Parsed),
                 "Needs_Clock is False when --through is explicit (0 clock reads)");

         --  Resolve WITHOUT passing Today (pure 1-arg overload)
         declare
            Opts : constant Home_Options := Resolve_Home_Options (Parse_Res.Parsed);
         begin
            Assert (Opts.Observed_Through = D ("2026-08-15"),
                    "Observed_Through is explicit 2026-08-15 without reading clock");
            Assert (Opts.Through_Source = Explicit,
                    "Through source is Explicit");
            Assert (Opts.Selected_Day = D ("2026-08-15"),
                    "Selected_Day defaults to explicit Observed_Through (2026-08-15)");
            Assert (Opts.Day_Source = Defaulted,
                    "Day source is Defaulted");
         end;
      end;

      --  2b. Explicit through + explicit day: clock NOT needed (0 clock reads)
      declare
         Args : constant String_Array :=
           [1 => To_Unbounded_String ("--through"),
            2 => To_Unbounded_String ("2026-08-19"),
            3 => To_Unbounded_String ("--day"),
            4 => To_Unbounded_String ("2026-08-25")];
         Parse_Res : constant Parse_Resolution := Parse_Arguments (Args);
      begin
         Assert (Parse_Res.Status = Success, "Stage A parse succeeds for explicit both");
         Assert (not Needs_Clock (Parse_Res.Parsed),
                 "Needs_Clock is False when both explicit (0 clock reads)");

         --  Resolve WITHOUT passing Today
         declare
            Opts : constant Home_Options := Resolve_Home_Options (Parse_Res.Parsed);
         begin
            Assert (Opts.Observed_Through = D ("2026-08-19"),
                    "Observed_Through is explicit 2026-08-19");
            Assert (Opts.Through_Source = Explicit,
                    "Through source is Explicit");
            Assert (Opts.Selected_Day = D ("2026-08-25"),
                    "Selected_Day is explicit 2026-08-25");
            Assert (Opts.Day_Source = Explicit,
                    "Day source is Explicit");
         end;
      end;

      --  2c. Omitted through + omitted day: clock NEEDED (1 clock read), day follows through
      declare
         Args : String_Array (1 .. 0);
         Parse_Res : constant Parse_Resolution := Parse_Arguments (Args);
      begin
         Assert (Parse_Res.Status = Success, "Stage A parse succeeds for empty args");
         Assert (Needs_Clock (Parse_Res.Parsed),
                 "Needs_Clock is True when --through is omitted (1 clock read required)");

         --  Resolve WITH injected Today
         declare
            Opts : constant Home_Options :=
              Resolve_Home_Options (Parse_Res.Parsed, Injected_Today);
         begin
            Assert (Opts.Observed_Through = Injected_Today,
                    "Observed_Through defaults to injected Today");
            Assert (Opts.Through_Source = Defaulted,
                    "Through source is Defaulted");
            Assert (Opts.Selected_Day = Injected_Today,
                    "Selected_Day defaults to defaulted Observed_Through (Today)");
            Assert (Opts.Day_Source = Defaulted,
                    "Day source is Defaulted");
         end;
      end;

      --  2d. Explicit day only: clock NEEDED (1 clock read because through is defaulted)
      declare
         Args : constant String_Array :=
           [1 => To_Unbounded_String ("--day"),
            2 => To_Unbounded_String ("2026-08-25")];
         Parse_Res : constant Parse_Resolution := Parse_Arguments (Args);
      begin
         Assert (Parse_Res.Status = Success, "Stage A parse succeeds for explicit day only");
         Assert (Needs_Clock (Parse_Res.Parsed),
                 "Needs_Clock is True when only --day is explicit (1 clock read required for through)");

         --  Resolve WITH injected Today
         declare
            Opts : constant Home_Options :=
              Resolve_Home_Options (Parse_Res.Parsed, Injected_Today);
         begin
            Assert (Opts.Observed_Through = Injected_Today,
                    "Observed_Through defaults to injected Today");
            Assert (Opts.Through_Source = Defaulted,
                    "Through source is Defaulted");
            Assert (Opts.Selected_Day = D ("2026-08-25"),
                    "Selected_Day is explicit 2026-08-25");
            Assert (Opts.Day_Source = Explicit,
                    "Day source is Explicit");
         end;
      end;

      --  2e. Explicit through with base directory: clock NOT needed
      declare
         Args : constant String_Array :=
           [1 => To_Unbounded_String ("--base"),
            2 => To_Unbounded_String ("/canonical/root"),
            3 => To_Unbounded_String ("--through"),
            4 => To_Unbounded_String ("2026-08-19")];
         Parse_Res : constant Parse_Resolution := Parse_Arguments (Args);
      begin
         Assert (not Needs_Clock (Parse_Res.Parsed),
                 "Needs_Clock is False with --base and --through");
         declare
            Opts : constant Home_Options := Resolve_Home_Options (Parse_Res.Parsed);
         begin
            Assert (To_String (Opts.Base_Directory) = "/canonical/root",
                    "Base directory resolved: /canonical/root");
            Assert (Opts.Observed_Through = D ("2026-08-19"),
                    "Observed_Through is 2026-08-19");
            Assert (Opts.Selected_Day = D ("2026-08-19"),
                    "Selected_Day defaults to explicit through (2026-08-19)");
         end;
      end;

      --  2f. Guardrail: calling 1-arg Resolve_Home_Options without explicit through fails closed
      declare
         Args : String_Array (1 .. 0);
         Parse_Res : constant Parse_Resolution := Parse_Arguments (Args);
         Raised    : Boolean := False;
      begin
         begin
            declare
               Unused_Opts : constant Home_Options :=
                 Resolve_Home_Options (Parse_Res.Parsed);
            begin
               null;
            end;
         exception
            when Program_Error =>
               Raised := True;
         end;
         Assert (Raised,
                 "Calling 1-arg Resolve_Home_Options without explicit through raises Program_Error");
      end;
   end;

   --  ========================================================================
   --  3. Pipeline Execution: Observation -> Presentation -> Text
   --  ========================================================================
   declare
      Sources : constant HRA.Canonical_Source.Source_Observation :=
        Make_Synthetic_Sources;
      State   : HRA.Household.Household_State;
      Diag    : Unbounded_String;
   begin
      Assert (HRA.Household.Admit_Canonical_Household (Sources, State, Diag),
              "Admit synthetic Household state");

      --  3a. Execute today's Home
      declare
         Home_Text_Today : constant String :=
           Execute_Home
             (State            => State,
              Observed_Through => D ("2026-08-19"),
              Selected_Day     => D ("2026-08-19"));
      begin
         Assert (Home_Text_Today'Length > 0, "Execute_Home produces non-empty output");
         Assert (Ada.Strings.Fixed.Index (Home_Text_Today, "August 2026") > 0,
                 "Output includes August 2026 Calendar");
         Assert (Ada.Strings.Fixed.Index (Home_Text_Today, "Dinner with 3 Postings") > 0,
                 "Output includes today's Actual transaction");
         Assert (Ada.Strings.Fixed.Index (Home_Text_Today, "expenses:food") > 0,
                 "Output includes structured account in Actual");
      end;

      --  3b. Execute future focus day (2026-08-25) with through (2026-08-19)
      declare
         Home_Text_Future : constant String :=
           Execute_Home
             (State            => State,
              Observed_Through => D ("2026-08-19"),
              Selected_Day     => D ("2026-08-25"));
      begin
         Assert (Home_Text_Future'Length > 0,
                 "Execute_Home for future focus day produces output");
         --  Actual is unavailable on future focus day
         Assert (Ada.Strings.Fixed.Index (Home_Text_Future, "Actual Transactions:") > 0,
                 "Output includes Actual Transactions section");
         Assert (Ada.Strings.Fixed.Index (Home_Text_Future, "[Unavailable]") > 0,
                 "Future selected day keeps Actual unavailable");
         --  Known future Plan on 2026-08-25 remains visible
         Assert (Ada.Strings.Fixed.Index (Home_Text_Future, "plan-multi-aug") > 0,
                 "Known future Plan remains visible on scheduled day");
         Assert (Ada.Strings.Fixed.Index (Home_Text_Future, "Planned Multi-Posting Payment") > 0,
                 "Plan description matches");
         --  Known future Issue on 2026-08-25 remains visible
         Assert (Ada.Strings.Fixed.Index (Home_Text_Future, "ISSUE-1") > 0,
                 "Known future Issue remains visible on due date");
      end;

      --  3c. Verify Home command output matches Home_Text.Render_Home exactly
      declare
         Obs  : constant HRA.Household_Home_Observation.Home_Observation :=
           HRA.Household_Home_Observation.Observe
             (Observed_Through => D ("2026-08-19"),
              Selected_Day     => D ("2026-08-19"),
              State            => State);
         Pres : constant HRA.Household_Home_Presentation.Home_Presentation :=
           HRA.Household_Home_Presentation.Present (Obs);
         Expected_Text : constant String :=
           HRA.Household_Home_Text.Render_Home
             (Pres, State.Report_Policy.Presentation.Calendar);
         Actual_Text   : constant String :=
           Execute_Home (State, D ("2026-08-19"), D ("2026-08-19"));
      begin
         Assert (Actual_Text = Expected_Text,
                 "Execute_Home output matches Home_Text.Render_Home exactly");
      end;
   end;

   --  ========================================================================
   --  4. Compatibility: Check and Report Behavior Unchanged
   --  ========================================================================
   declare
      Sources_Report : HRA.Canonical_Source.Source_Observation :=
        Make_Synthetic_Sources;
      State_Report   : HRA.Household.Household_State;
      Diag           : Unbounded_String;
   begin
      Sources_Report.Texts (Plan_Source) := To_Unbounded_String
        ("2026-08-25 Planned Utility Bill" & ASCII.LF &
         "    ; plan-id: plan-util-aug" & ASCII.LF &
         "    expenses:food          8000 JPY" & ASCII.LF &
         "    assets:bank           -8000 JPY" & ASCII.LF & ASCII.LF &
         "2026-08-31 September Salary" & ASCII.LF &
         "    ; plan-id: plan-sep-salary" & ASCII.LF &
         "    assets:bank          300000 JPY" & ASCII.LF &
         "    income:salary       -300000 JPY" & ASCII.LF);

      Assert (HRA.Household.Admit_Canonical_Household (Sources_Report, State_Report, Diag),
              "Admit synthetic Household state for check/report");

      --  4a. Check observation
      declare
         Check_Obs : constant HRA.Household_Check_Observation.Observation :=
           HRA.Household_Check_Observation.Observe (State_Report);
      begin
         Assert (Check_Obs.Actual_Transactions = 5, "Check Actual_Transactions = 5");
         Assert (Check_Obs.Plan_Transactions = 2, "Check Plan_Transactions = 2");
         Assert (Check_Obs.Budget_Transactions = 2, "Check Budget_Transactions = 2");
         Assert (Check_Obs.Registered_Accounts = 8, "Check Registered_Accounts = 8");
         Assert (Check_Obs.Open_Issues = 1, "Check Open_Issues = 1");
      end;

      --  4b. Report observation
      declare
         Report_Obs : HRA.Household_Report_Observation.Report_Observation;
         Err        : Unbounded_String;
         Success    : Boolean;
      begin
         Success := HRA.Household_Report_Observation.Observe
           (D ("2026-08-19"), State_Report, Report_Obs, Err);
         Assert (Success,
                 "Report observation succeeds on admitted state: " & To_String (Err));
         Assert (Report_Obs.Section_Order'Length > 0,
                 "Report observation produces non-empty section order");
      end;
   end;

   --  ========================================================================
   --  Summary
   --  ========================================================================
   Put_Line ("--------------------------------------------------");
   Put_Line ("Summary: Passed = " & Natural'Image (Passed_Count) &
             ", Failed = " & Natural'Image (Failed_Count));

   if Failed_Count > 0 then
      raise Program_Error with "Household Home command tests failed";
   end if;
end Test_Household_Home_Command;
