with Ada.Strings.Fixed;     use Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO;           use Ada.Text_IO;
with HRA.Account;
with HRA.Actual_Admission;
with HRA.Config_Support;
with HRA.Cycle_Accounts_Observation;
with HRA.Cycle_Observation;
with HRA.Daily_Target_Observation;
with HRA.Daily_Target_Render;
with HRA.Daily_Target_Scope;
with HRA.Dates;
with HRA.Household_Config;
with HRA.Household_Daily_Target_View;
with HRA.Journal;
with HRA.Journal_Evidence;
with HRA.Ledger;
with HRA.Plan_Admission;
with HRA.Plan_Completion;
with HRA.Plan_Temporal_Observation;
with HRA.Terminal_UTF8;

procedure Test_Daily_Target_Render is
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

begin
   HRA.Terminal_UTF8.Initialize;
   Put_Line ("--- Testing HRA.Daily_Target_Render ---");

   --  1. Unconfigured render
   declare
      V   : constant HRA.Household_Daily_Target_View.View :=
        (Status => HRA.Household_Daily_Target_View.Unconfigured);
      Txt : constant String := HRA.Daily_Target_Render.Render (V);
   begin
      Assert
        (Index (Txt, "Daily Target") > 0
         and then Index (Txt, "(not configured)") > 0,
         "Unconfigured renders friendly not-configured message");
   end;

   --  2. Scope_Unavailable render
   declare
      V   : constant HRA.Household_Daily_Target_View.View :=
        (Status           => HRA.Household_Daily_Target_View.Scope_Unavailable,
         Scope_Diagnostic =>
           (Status      => HRA.Daily_Target_Scope.Unsupported_Selected_Plan_Shape,
            Line_Number => 15,
            Selection   => To_Unbounded_String ("target-lunch"),
            Plan_Id     => To_Unbounded_String ("plan-123"),
            Message     => Null_Unbounded_String));
      Txt : constant String := HRA.Daily_Target_Render.Render (V);
   begin
      Assert
        (Index (Txt, "Daily Target") > 0
         and then Index (Txt, "(unavailable: selected plan does not match a supported daily target shape (one asset source and one expense/liability destination))") > 0
         and then Index (Txt, "plan-id=") = 0
         and then Index (Txt, "selection=") = 0
         and then Index (Txt, "UNSUPPORTED_SELECTED_PLAN_SHAPE") = 0,
         "Scope_Unavailable renders gentle explanation without raw enum 'Image or internal identifiers");
   end;

   --  3. Observation_Unavailable render
   declare
      V   : constant HRA.Household_Daily_Target_View.View :=
        (Status                 => HRA.Household_Daily_Target_View.Observation_Unavailable,
         Observation_Diagnostic =>
           (Status       => HRA.Daily_Target_Observation.Eligible_Asset_Missing_From_Account_State,
            Account_Name => To_Unbounded_String ("assets:wallet"),
            Message      => Null_Unbounded_String));
      Txt : constant String := HRA.Daily_Target_Render.Render (V);
   begin
      Assert
        (Index (Txt, "Daily Target") > 0
         and then Index (Txt, "(unavailable: configured eligible asset is not present in cycle account state)") > 0
         and then Index (Txt, "account=") = 0
         and then Index (Txt, "ELIGIBLE_ASSET_MISSING") = 0,
         "Observation_Unavailable renders gentle explanation without raw enum 'Image or internal identifiers");
   end;

   --  4. Available render (populated scenario via View)
   declare
      Registry      : HRA.Account.Account_Registry;
      Actual_Ledger : HRA.Ledger.Ledger;
      Plan_Ledger   : HRA.Ledger.Ledger;
      Actual_Ev     : HRA.Journal_Evidence.Journal_Evidence;
      Plan_Ev       : HRA.Journal_Evidence.Journal_Evidence;
      Actual_Id     : HRA.Actual_Admission.Actual_Observation;
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
      Scope         : HRA.Daily_Target_Scope.Scope;
      Active_Plans  : HRA.Plan_Temporal_Observation.Observation;
      Active_Acc    : HRA.Cycle_Accounts_Observation.Observation;
      Obs           : HRA.Daily_Target_Observation.Observation;
      Obs_Diag      : HRA.Daily_Target_Observation.Observe_Diagnostic;
      Cycle_Win     : HRA.Cycle_Observation.Cycle_Window;
      Actual_Txt    : constant String :=
        "2026-08-01 Salary" & ASCII.LF &
        "    assets:cash              3000 JPY" & ASCII.LF &
        "    income:salary           -3000 JPY" & ASCII.LF;
      Plan_Txt      : constant String :=
        "2026-08-15 Dinner" & ASCII.LF &
        "    ; plan-id: plan-dinner" & ASCII.LF &
        "    ; daily-target-id: sel-dinner" & ASCII.LF &
        "    assets:cash              -600 JPY" & ASCII.LF &
        "    expenses:food             600 JPY" & ASCII.LF;
   begin
      Register (Registry, "assets:cash", HRA.Account.Asset);
      Register (Registry, "income:salary", HRA.Account.Income);
      Register (Registry, "expenses:food", HRA.Account.Expense);

      Assert
        (HRA.Journal.Parse_Journal_Text
           (Actual_Txt, "actual.journal", Actual_Ledger, Journal_Diag),
         "setup parses actual");
      Assert
        (HRA.Journal_Evidence.Extract
           (Actual_Txt, Actual_Ledger, Actual_Ev, Evidence_Diag),
         "setup extracts actual");
      Actual_Ledger.Registry := Registry;
      Assert
        (HRA.Actual_Admission.Admit
           (Actual_Ledger, Actual_Ev, Actual_Id, Actual_Diag),
         "setup admits actual");

      Assert
        (HRA.Journal.Parse_Journal_Text
           (Plan_Txt, "plan.journal", Plan_Ledger, Journal_Diag),
         "setup parses plan");
      Assert
        (HRA.Journal_Evidence.Extract
           (Plan_Txt, Plan_Ledger, Plan_Ev, Evidence_Diag),
         "setup extracts plan");
      Plan_Ledger.Registry := Registry;
      Assert
        (HRA.Plan_Admission.Admit
           (Plan_Ledger, Plan_Ev, Plan_Jour, Plan_Diag),
         "setup admits plan");
      Assert
        (HRA.Plan_Completion.Admit
           (Plan_Jour, Actual_Id, Completions, Compl_Diag),
         "setup admits completions");

      Assert
        (HRA.Household_Config.Parse_Household_Configuration
           ("[cycle]" & ASCII.LF &
            "mode = ""income-anchor""" & ASCII.LF &
            "income-account = ""income:salary""" & ASCII.LF &
            "[money]" & ASCII.LF &
            "primary-commodity = ""JPY""" & ASCII.LF &
            "[daily-target]" & ASCII.LF &
            "assets = [{ id = ""cash"", account = ""assets:cash"" }]" & ASCII.LF &
            "[envelope-history]" & ASCII.LF &
            "identities = []" & ASCII.LF &
            "expense-routing = []" & ASCII.LF &
            "fulfillment-routing = []" & ASCII.LF,
            Config_State,
            Config_Diag),
         "setup admits config");

      Assert
        (HRA.Daily_Target_Scope.Admit
           (Config_State, Registry, Plan_Jour, Scope, Scope_Diag),
         "setup admits scope");

      Assert
        (HRA.Dates.Make_Half_Open_Period
           (D ("2026-08-01"), D ("2026-09-01"), Cycle_Win),
         "setup makes cycle window");
      Active_Plans := HRA.Plan_Temporal_Observation.Observe
        (Plan_Jour, Completions, D ("2026-08-20"));
      Assert
        (HRA.Cycle_Accounts_Observation.Observe
           (Actual_Ledger, Cycle_Win, D ("2026-08-20"), Active_Acc, Acc_Diag),
         "setup observes cycle accounts");

      Assert
        (HRA.Daily_Target_Observation.Observe
           (Scope, Active_Plans, Active_Acc, Obs, Obs_Diag),
         "setup observes daily target");

      declare
         V   : constant HRA.Household_Daily_Target_View.View :=
           (Status      => HRA.Household_Daily_Target_View.Available,
            Observation => Obs);
         Txt : constant String := HRA.Daily_Target_Render.Render (V);
      begin
         Assert
           (Index (Txt, "Daily Target") > 0
            and then Index (Txt, "Capacity: 2,400 JPY over 12 remaining days in cycle") > 0
            and then Index (Txt, "Eligible assets:       3,000 JPY") > 0
            and then Index (Txt, "Open obligations:      600 JPY") > 0
            and then Index (Txt, "Net obligations:       600 JPY") > 0
            and then Index (Txt, "Capacity:              2,400 JPY") > 0
            and then Index (Txt, "Remaining days:        12") > 0,
            "Available renders exact multi-commodity capacity, basis, and breakdown via View");
      end;
   end;

   Put_Line
     (Natural'Image (Passed_Count) & " passed, " &
      Natural'Image (Failed_Count) & " failed");
   if Failed_Count > 0 then
      raise Program_Error with "Daily Target Render tests failed";
   end if;
end Test_Daily_Target_Render;
