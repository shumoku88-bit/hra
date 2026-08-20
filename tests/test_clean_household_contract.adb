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

   Current_Envelope : constant String :=
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
     "[envelope-history]" & ASCII.LF &
     "identities = [""food"", ""retired""]" & ASCII.LF &
     "expense-routing = []" & ASCII.LF;

   Policy : HRA.Budget_Config.Budget_Policy;
   Config : HRA.Household_Config.Household_Configuration;
   Diag   : HRA.Config_Support.Config_Diagnostic;

begin
   Put_Line ("--- Testing current Household / Envelope source contract ---");

   Assert
     (HRA.Budget_Config.Parse_Budget_Policy
        (Current_Envelope, Policy, Diag),
      "envelope.toml admits current Envelope and Backing coordinates");

   Assert
     (HRA.Household_Config.Parse_Household_Configuration
        (Clean_Household, Config, Diag),
      "household.toml admits stable Envelope history without Budget coordinates");
   Assert
     (Natural (Config.Envelope_History.Identities.Length) = 2,
      "stable history may retain a retired Envelope identity");

   declare
      Legacy_Envelope : constant String :=
        Current_Envelope &
        "expense-accounts = [""expenses:food""]" & ASCII.LF;
      Rejected : HRA.Budget_Config.Budget_Policy;
   begin
      Assert
        (not HRA.Budget_Config.Parse_Budget_Policy
           (Legacy_Envelope, Rejected, Diag),
         "retired Expense assignment authority is rejected by envelope.toml admission");
   end;

   declare
      Legacy_Household : constant String :=
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
        "expense-routing = []" & ASCII.LF;
      Rejected : HRA.Household_Config.Household_Configuration;
   begin
      Assert
        (not HRA.Household_Config.Parse_Household_Configuration
           (Legacy_Household, Rejected, Diag),
         "retired household [budget] coordinates are rejected");
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
           (Legacy_Household, Rejected, Diag),
         "retired account-policy authority is rejected");
   end;

   declare
      Invalid_Unmanaged : constant String :=
        "[cycle]" & ASCII.LF &
        "mode = ""income-anchor""" & ASCII.LF &
        "income-account = ""income:pension""" & ASCII.LF &
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
           (Invalid_Unmanaged, Rejected, Diag),
         "unmanaged history cannot carry an Envelope target");
   end;

   Put_Line
     (Natural'Image (Passed_Count) & " passed, " &
      Natural'Image (Failed_Count) & " failed");

   if Failed_Count > 0 then
      raise Program_Error with "Household source contract tests failed";
   end if;
end Test_Clean_Household_Contract;
