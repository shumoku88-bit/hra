with Ada.Text_IO; use Ada.Text_IO;
with HRA.Budget_Config;
with HRA.Config_Support;
with HRA.Household_Config;

procedure Test_Clean_Household_Contract is
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

   Current_Budget : constant String :=
     "[[backing-pools]]" & ASCII.LF &
     "id = ""liquid""" & ASCII.LF &
     "asset-accounts = [""assets:cash""]" & ASCII.LF &
     "[[envelopes]]" & ASCII.LF &
     "id = ""food""" & ASCII.LF &
     "label = ""Food""" & ASCII.LF &
     "pacing = ""daily""" & ASCII.LF &
     "backing-pool = ""liquid""" & ASCII.LF;

   Clean_Household : constant String :=
     "[cycle]" & ASCII.LF &
     "mode = ""income-anchor""" & ASCII.LF &
     "income-account = ""income:pension""" & ASCII.LF &
     "[budget]" & ASCII.LF &
     "opening-accounts = [""budget:opening""]" & ASCII.LF &
     "unassigned-accounts = [""budget:unassigned""]" & ASCII.LF &
     "[[budget.envelopes]]" & ASCII.LF &
     "id = ""food""" & ASCII.LF &
     "allocation-account = ""budget:food""" & ASCII.LF &
     "[[budget.envelopes]]" & ASCII.LF &
     "id = ""retired""" & ASCII.LF &
     "allocation-account = ""budget:retired""" & ASCII.LF &
     "[envelope-history]" & ASCII.LF &
     "identities = [""food"", ""retired""]" & ASCII.LF &
     "expense-routing = []" & ASCII.LF;

   Policy : HRA.Budget_Config.Budget_Policy;
   Config : HRA.Household_Config.Household_Configuration;
   Diag   : HRA.Config_Support.Config_Diagnostic;

begin
   Put_Line ("--- Testing clean Household / Envelope source contract ---");

   Assert
     (HRA.Budget_Config.Parse_Budget_Policy
        (Current_Budget, Policy, Diag),
      "budget.toml admits current Envelope and Backing coordinates only");

   Assert
     (HRA.Household_Config.Parse_Household_Configuration
        (Clean_Household, Policy, Config, Diag),
      "household.toml admits current plus retired allocation coordinates");
   Assert
     (Natural (Config.Envelopes.Length) = 2,
      "retired allocation coordinate remains historically interpretable");

   declare
      Legacy_Budget : constant String :=
        Current_Budget &
        "expense-accounts = [""expenses:food""]" & ASCII.LF;
      Rejected : HRA.Budget_Config.Budget_Policy;
   begin
      Assert
        (not HRA.Budget_Config.Parse_Budget_Policy
           (Legacy_Budget, Rejected, Diag),
         "retired budget.toml expense-accounts authority is rejected");
   end;

   declare
      Legacy_Household : constant String :=
        Clean_Household &
        "[account-policy]" & ASCII.LF &
        "opening-budget = [""budget:opening""]" & ASCII.LF;
      Rejected : HRA.Household_Config.Household_Configuration;
   begin
      Assert
        (not HRA.Household_Config.Parse_Household_Configuration
           (Legacy_Household, Policy, Rejected, Diag),
         "retired account-policy authority is rejected");
   end;

   declare
      Legacy_Household : constant String :=
        "[cycle]" & ASCII.LF &
        "mode = ""income-anchor""" & ASCII.LF &
        "income-account = ""income:pension""" & ASCII.LF &
        "[budget]" & ASCII.LF &
        "opening-accounts = [""budget:opening""]" & ASCII.LF &
        "unassigned-accounts = [""budget:unassigned""]" & ASCII.LF &
        "plan-destination-accounts = [""assets:cash""]" & ASCII.LF &
        "[[budget.envelopes]]" & ASCII.LF &
        "id = ""food""" & ASCII.LF &
        "allocation-account = ""budget:food""" & ASCII.LF &
        "[envelope-history]" & ASCII.LF &
        "identities = [""food""]" & ASCII.LF &
        "expense-routing = []" & ASCII.LF;
      Rejected : HRA.Household_Config.Household_Configuration;
   begin
      Assert
        (not HRA.Household_Config.Parse_Household_Configuration
           (Legacy_Household, Policy, Rejected, Diag),
         "retired Plan destination authority is rejected");
   end;

   declare
      Missing_Current_Coordinate : constant String :=
        "[cycle]" & ASCII.LF &
        "mode = ""income-anchor""" & ASCII.LF &
        "income-account = ""income:pension""" & ASCII.LF &
        "[budget]" & ASCII.LF &
        "opening-accounts = [""budget:opening""]" & ASCII.LF &
        "unassigned-accounts = [""budget:unassigned""]" & ASCII.LF &
        "[[budget.envelopes]]" & ASCII.LF &
        "id = ""retired""" & ASCII.LF &
        "allocation-account = ""budget:retired""" & ASCII.LF &
        "[envelope-history]" & ASCII.LF &
        "identities = [""food"", ""retired""]" & ASCII.LF &
        "expense-routing = []" & ASCII.LF;
      Rejected : HRA.Household_Config.Household_Configuration;
   begin
      Assert
        (not HRA.Household_Config.Parse_Household_Configuration
           (Missing_Current_Coordinate, Policy, Rejected, Diag),
         "every current Envelope requires an explicit allocation coordinate");
   end;

   declare
      Invalid_Unmanaged : constant String :=
        "[cycle]" & ASCII.LF &
        "mode = ""income-anchor""" & ASCII.LF &
        "income-account = ""income:pension""" & ASCII.LF &
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
        "route = ""unmanaged""" & ASCII.LF &
        "target = ""food""" & ASCII.LF &
        "note = ""invalid target on unmanaged route""" & ASCII.LF;
      Rejected : HRA.Household_Config.Household_Configuration;
   begin
      Assert
        (not HRA.Household_Config.Parse_Household_Configuration
           (Invalid_Unmanaged, Policy, Rejected, Diag),
         "unmanaged history cannot carry an Envelope target");
   end;

   Put_Line
     (Natural'Image (Passed_Count) & " passed, " &
      Natural'Image (Failed_Count) & " failed");

   if Failed_Count > 0 then
      raise Program_Error with "clean Household contract tests failed";
   end if;
end Test_Clean_Household_Contract;
