with Ada.Strings.Fixed;     use Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO;           use Ada.Text_IO;
with HRA.Account;
with HRA.Actual_Admission;
with HRA.Config_Support;
with HRA.Cycle_Accounts_Observation;
with HRA.Cycle_Observation;
with HRA.Daily_Target_Observation;
with HRA.Daily_Target_Rate;
with HRA.Daily_Target_Scope;
with HRA.Dates;
with HRA.Household;
with HRA.Household_Config;
with HRA.Household_Daily_Target_View;
with HRA.Journal;
with HRA.Journal_Evidence;
with HRA.Ledger;
with HRA.Plan_Admission;
with HRA.Plan_Completion;
with HRA.Plan_Temporal_Observation;

procedure Test_Household_Daily_Target_View is
   use type HRA.Cycle_Accounts_Observation.Observe_Status;
   use type HRA.Cycle_Observation.Resolve_Status;
   use type HRA.Daily_Target_Observation.Observe_Status;
   use type HRA.Daily_Target_Scope.Admission_Status;
   use type HRA.Dates.Date;
   use type HRA.Household.Daily_Target_Scope_Availability;
   use type HRA.Household_Daily_Target_View.View_Status;

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
         raise Program_Error with "invalid test date: " & Text;
      end if;
      return Value;
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
         raise Program_Error with "account registration failed: " & Name;
      end if;
   end Register;

   Registry      : HRA.Account.Account_Registry;
   Empty_Plans   : HRA.Plan_Temporal_Observation.Observation;
   Empty_Account : HRA.Cycle_Accounts_Observation.Observation;
   Unconfig_Scope : constant HRA.Household.Daily_Target_Scope_State :=
     (Status => HRA.Household.Daily_Target_Scope_Available,
      Value  => HRA.Daily_Target_Scope.Empty_Scope);
   Unavail_Scope  : constant HRA.Household.Daily_Target_Scope_State :=
     (Status     => HRA.Household.Daily_Target_Scope_Unavailable,
      Diagnostic =>
        (Status      => HRA.Daily_Target_Scope.Unsupported_Selected_Plan_Shape,
         Line_Number => 10,
         Selection   => To_Unbounded_String ("sel-bad"),
         Plan_Id     => To_Unbounded_String ("plan-bad"),
         Message     => To_Unbounded_String ("three postings")));

   View : HRA.Household_Daily_Target_View.View;

   --  Populated scenario
   Actual_Text : constant String :=
     "2026-08-01 Opening" & ASCII.LF &
     "    assets:bank              1000 JPY" & ASCII.LF &
     "    income:salary           -1000 JPY" & ASCII.LF;
   Plan_Text : constant String :=
     "2026-08-15 Planned Bill" & ASCII.LF &
     "    ; plan-id: plan-bill" & ASCII.LF &
     "    ; daily-target-id: sel-bill" & ASCII.LF &
     "    assets:bank              -200 JPY" & ASCII.LF &
     "    expenses:utilities        200 JPY" & ASCII.LF;

   Actual_Ledger : HRA.Ledger.Ledger;
   Actual_Ev     : HRA.Journal_Evidence.Journal_Evidence;
   Actual_Id     : HRA.Actual_Admission.Actual_Observation;
   Plan_Ledger   : HRA.Ledger.Ledger;
   Plan_Ev       : HRA.Journal_Evidence.Journal_Evidence;
   Plan_Jour     : HRA.Plan_Admission.Plan_Journal;
   Completions   : HRA.Plan_Completion.Completion_Relations;
   Config_State  : HRA.Household_Config.Household_Configuration;
   Config_Diag   : HRA.Config_Support.Config_Diagnostic;
   Journal_Diag  : HRA.Journal.Parse_Diagnostic;
   Evidence_Diag : HRA.Journal_Evidence.Evidence_Diagnostic;
   Actual_Diag   : HRA.Actual_Admission.Admission_Diagnostic;
   Plan_Diag     : HRA.Plan_Admission.Admission_Diagnostic;
   Compl_Diag    : HRA.Plan_Completion.Admission_Diagnostic;
   Scope_Diag    : HRA.Daily_Target_Scope.Admission_Diagnostic;
   Acc_Diag      : HRA.Cycle_Accounts_Observation.Observe_Diagnostic;

   Configured_Scope_State : HRA.Household.Daily_Target_Scope_State;
   Active_Plans           : HRA.Plan_Temporal_Observation.Observation;
   Active_Accounts        : HRA.Cycle_Accounts_Observation.Observation;
   Mismatched_Accounts    : HRA.Cycle_Accounts_Observation.Observation;
   Cycle_Win              : HRA.Cycle_Observation.Cycle_Window;

begin
   Put_Line ("--- Testing HRA.Household_Daily_Target_View ---");

   Register (Registry, "assets:bank", HRA.Account.Asset);
   Register (Registry, "income:salary", HRA.Account.Income);
   Register (Registry, "expenses:utilities", HRA.Account.Expense);

   --  === 1. Existing Project (Scope_State, Plans, Account_State) laws ===

   --  Law 1: Scope_Unavailable projects directly to Scope_Unavailable
   View := HRA.Household_Daily_Target_View.Project
     (Unavail_Scope, Empty_Plans, Empty_Account);
   Assert
     (View.Status = HRA.Household_Daily_Target_View.Scope_Unavailable
      and then View.Scope_Diagnostic.Status =
        HRA.Daily_Target_Scope.Unsupported_Selected_Plan_Shape
      and then To_String (View.Scope_Diagnostic.Plan_Id) = "plan-bad",
      "Scope_Unavailable retains exact diagnostic without calling observe");

   --  Law 2: Unconfigured Scope projects directly to Unconfigured
   View := HRA.Household_Daily_Target_View.Project
     (Unconfig_Scope, Empty_Plans, Empty_Account);
   Assert
     (View.Status = HRA.Household_Daily_Target_View.Unconfigured,
      "Unconfigured scope projects to Unconfigured without calling observe");

   --  Setup populated scenario
   Assert
     (HRA.Journal.Parse_Journal_Text
        (Actual_Text, "actual.journal", Actual_Ledger, Journal_Diag),
      "setup parses actual journal");
   Assert
     (HRA.Journal_Evidence.Extract
        (Actual_Text, Actual_Ledger, Actual_Ev, Evidence_Diag),
      "setup extracts actual evidence");
   Actual_Ledger.Registry := Registry;
   Assert
     (HRA.Actual_Admission.Admit
        (Actual_Ledger, Actual_Ev, Actual_Id, Actual_Diag),
      "setup admits actual authority");

   Assert
     (HRA.Journal.Parse_Journal_Text
        (Plan_Text, "plan.journal", Plan_Ledger, Journal_Diag),
      "setup parses plan journal");
   Assert
     (HRA.Journal_Evidence.Extract
        (Plan_Text, Plan_Ledger, Plan_Ev, Evidence_Diag),
      "setup extracts plan evidence");
   Plan_Ledger.Registry := Registry;
   Assert
     (HRA.Plan_Admission.Admit
        (Plan_Ledger, Plan_Ev, Plan_Jour, Plan_Diag),
      "setup admits plan authority");
   Assert
     (HRA.Plan_Completion.Admit
        (Plan_Jour, Actual_Id, Completions, Compl_Diag),
      "setup admits plan completions");

   Assert
     (HRA.Household_Config.Parse_Household_Configuration
        ("[cycle]" & ASCII.LF &
         "mode = ""income-anchor""" & ASCII.LF &
         "income-account = ""income:salary""" & ASCII.LF &
         "[money]" & ASCII.LF &
         "primary-commodity = ""JPY""" & ASCII.LF &
         "[daily-target]" & ASCII.LF &
         "assets = [{ id = ""bank"", account = ""assets:bank"" }]" & ASCII.LF &
         "[envelope-history]" & ASCII.LF &
         "identities = []" & ASCII.LF &
         "expense-routing = []" & ASCII.LF &
         "fulfillment-routing = []" & ASCII.LF,
         Config_State,
         Config_Diag),
      "setup admits household config with daily-target");

   declare
      Admitted_Scope : HRA.Daily_Target_Scope.Scope;
   begin
      Assert
        (HRA.Daily_Target_Scope.Admit
           (Config_State, Registry, Plan_Jour, Admitted_Scope, Scope_Diag),
         "setup admits daily target scope");
      Configured_Scope_State :=
        (Status => HRA.Household.Daily_Target_Scope_Available,
         Value  => Admitted_Scope);
   end;

   Assert
     (HRA.Dates.Make_Half_Open_Period
        (D ("2026-08-01"), D ("2026-09-01"), Cycle_Win),
      "setup makes cycle window");

   Active_Plans := HRA.Plan_Temporal_Observation.Observe
     (Plan_Jour, Completions, D ("2026-08-10"));

   Assert
     (HRA.Cycle_Accounts_Observation.Observe
        (Actual_Ledger, Cycle_Win, D ("2026-08-10"), Active_Accounts, Acc_Diag),
      "setup observes cycle accounts through 2026-08-10");

   --  Law 3: Configured scope + matching observations -> Available
   View := HRA.Household_Daily_Target_View.Project
     (Configured_Scope_State, Active_Plans, Active_Accounts);
   Assert
     (View.Status = HRA.Household_Daily_Target_View.Available
      and then HRA.Daily_Target_Observation.Observed_Through (View.Observation) =
        D ("2026-08-10"),
      "Configured scope projects to Available holding Observation");

   --  Check that Rate can be derived purely without storing duplicate authority
   declare
      Rate : constant HRA.Daily_Target_Rate.Rate :=
        HRA.Daily_Target_Rate.Derive (View.Observation);
   begin
      Assert
        (HRA.Daily_Target_Rate.Is_Configured (Rate)
         and then HRA.Daily_Target_Rate.Remaining_Days (Rate) = 22,
         "Rate is purely derivable from Available View observation");
   end;

   --  Law 4: Configured scope + mismatched observation -> Observation_Unavailable
   Assert
     (HRA.Cycle_Accounts_Observation.Observe
        (Actual_Ledger, Cycle_Win, D ("2026-08-05"), Mismatched_Accounts, Acc_Diag),
      "setup observes cycle accounts through 2026-08-05");

   View := HRA.Household_Daily_Target_View.Project
     (Configured_Scope_State, Active_Plans, Mismatched_Accounts);
   Assert
     (View.Status = HRA.Household_Daily_Target_View.Observation_Unavailable
      and then View.Observation_Diagnostic.Status =
        HRA.Daily_Target_Observation.Observation_Date_Mismatch,
      "Temporal mismatch produces Observation_Unavailable with exact diagnostic");

   --  === 2. Project_From_Cycle short-circuiting laws ===

   --  Law 5: Project_From_Cycle with Scope_Unavailable short-circuits before Cycle check
   declare
      Unavail_Cycle_Opt : constant
        HRA.Household_Daily_Target_View.Cycle_Window_Option :=
          (Status => HRA.Household_Daily_Target_View.Cycle_Window_Unavailable,
           Error  => HRA.Cycle_Observation.Missing_Future_Plan_Anchor);
   begin
      View := HRA.Household_Daily_Target_View.Project_From_Cycle
        (Scope_State   => Unavail_Scope,
         Plans         => Empty_Plans,
         Ledger        => Actual_Ledger,
         Cycle_Window  => Unavail_Cycle_Opt,
         Known_Through => D ("2026-08-10"));
      Assert
        (View.Status = HRA.Household_Daily_Target_View.Scope_Unavailable
         and then View.Scope_Diagnostic.Status =
           HRA.Daily_Target_Scope.Unsupported_Selected_Plan_Shape,
         "Project_From_Cycle with Scope_Unavailable short-circuits without checking Cycle");
   end;

   --  Law 6: Project_From_Cycle with Unconfigured short-circuits before Cycle check
   declare
      Unavail_Cycle_Opt : constant
        HRA.Household_Daily_Target_View.Cycle_Window_Option :=
          (Status => HRA.Household_Daily_Target_View.Cycle_Window_Unavailable,
           Error  => HRA.Cycle_Observation.Missing_Future_Plan_Anchor);
   begin
      View := HRA.Household_Daily_Target_View.Project_From_Cycle
        (Scope_State   => Unconfig_Scope,
         Plans         => Empty_Plans,
         Ledger        => Actual_Ledger,
         Cycle_Window  => Unavail_Cycle_Opt,
         Known_Through => D ("2026-08-10"));
      Assert
        (View.Status = HRA.Household_Daily_Target_View.Unconfigured,
         "Project_From_Cycle with Unconfigured short-circuits without checking Cycle");
   end;

   --  Law 7: Configured scope + Cycle Unavailable -> Cycle_Unavailable retaining error
   declare
      Unavail_Cycle_Opt : constant
        HRA.Household_Daily_Target_View.Cycle_Window_Option :=
          (Status => HRA.Household_Daily_Target_View.Cycle_Window_Unavailable,
           Error  => HRA.Cycle_Observation.Missing_Future_Plan_Anchor);
   begin
      View := HRA.Household_Daily_Target_View.Project_From_Cycle
        (Scope_State   => Configured_Scope_State,
         Plans         => Active_Plans,
         Ledger        => Actual_Ledger,
         Cycle_Window  => Unavail_Cycle_Opt,
         Known_Through => D ("2026-08-10"));
      Assert
        (View.Status = HRA.Household_Daily_Target_View.Cycle_Unavailable
         and then View.Cycle_Error =
           HRA.Cycle_Observation.Missing_Future_Plan_Anchor,
         "Configured scope + Cycle Unavailable returns Cycle_Unavailable retaining Resolve_Status");
   end;

   --  Law 8: Configured scope + Cycle Available + Cycle Accounts failure -> Cycle_Accounts_Unavailable
   declare
      Avail_Cycle_Opt : constant
        HRA.Household_Daily_Target_View.Cycle_Window_Option :=
          (Status => HRA.Household_Daily_Target_View.Cycle_Window_Available,
           Window => Cycle_Win);
   begin
      --  Observation date outside cycle (2026-09-10 > 2026-09-01 limit)
      View := HRA.Household_Daily_Target_View.Project_From_Cycle
        (Scope_State   => Configured_Scope_State,
         Plans         => Active_Plans,
         Ledger        => Actual_Ledger,
         Cycle_Window  => Avail_Cycle_Opt,
         Known_Through => D ("2026-09-10"));
      Assert
        (View.Status = HRA.Household_Daily_Target_View.Cycle_Accounts_Unavailable
         and then View.Cycle_Accounts_Diagnostic.Status =
           HRA.Cycle_Accounts_Observation.Observation_Outside_Cycle,
         "Cycle Accounts failure returns Cycle_Accounts_Unavailable retaining diagnostic");
   end;

   --  Law 9: Configured scope + Cycle Available + Cycle Accounts success -> delegates to Project (Available)
   declare
      Avail_Cycle_Opt : constant
        HRA.Household_Daily_Target_View.Cycle_Window_Option :=
          (Status => HRA.Household_Daily_Target_View.Cycle_Window_Available,
           Window => Cycle_Win);
   begin
      View := HRA.Household_Daily_Target_View.Project_From_Cycle
        (Scope_State   => Configured_Scope_State,
         Plans         => Active_Plans,
         Ledger        => Actual_Ledger,
         Cycle_Window  => Avail_Cycle_Opt,
         Known_Through => D ("2026-08-10"));
      Assert
        (View.Status = HRA.Household_Daily_Target_View.Available
         and then HRA.Daily_Target_Observation.Observed_Through (View.Observation) =
           D ("2026-08-10"),
         "Project_From_Cycle successfully delegates to Project yielding Available View");
   end;

   Put_Line
     (Natural'Image (Passed_Count) & " passed, " &
      Natural'Image (Failed_Count) & " failed");
   if Failed_Count > 0 then
      raise Program_Error with "Household Daily Target View tests failed";
   end if;
end Test_Household_Daily_Target_View;
