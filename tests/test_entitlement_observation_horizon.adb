with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO; use Ada.Text_IO;
with HRA.Budget_Config;
with HRA.Budget_Source_Adapter;
with HRA.Config_Support;
with HRA.Dates;
with HRA.Envelope;
with HRA.Envelope_Entitlement;
with HRA.Household_Config;
with HRA.Journal;
with HRA.Ledger;
with HRA.Money; use HRA.Money;

procedure Test_Entitlement_Observation_Horizon is
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
      Result : HRA.Dates.Date;
      Status : HRA.Dates.Date_Status;
   begin
      if not HRA.Dates.Parse (S, Result, Status) then
         raise Program_Error with "invalid test date: " & S;
      end if;
      return Result;
   end D;

   Budget_TOML : constant String :=
     "[[backing-pools]]" & ASCII.LF &
     "id = ""liquid""" & ASCII.LF &
     "asset-accounts = [""assets:cash""]" & ASCII.LF &
     "[[envelopes]]" & ASCII.LF &
     "id = ""food""" & ASCII.LF &
     "label = ""Food""" & ASCII.LF &
     "pacing = ""daily""" & ASCII.LF &
     "backing-pool = ""liquid""" & ASCII.LF &
     "[[envelopes]]" & ASCII.LF &
     "id = ""daily""" & ASCII.LF &
     "label = ""Daily""" & ASCII.LF &
     "pacing = ""daily""" & ASCII.LF &
     "backing-pool = ""liquid""" & ASCII.LF;

   Household_TOML : constant String :=
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
     "id = ""daily""" & ASCII.LF &
     "allocation-account = ""budget:daily""" & ASCII.LF &
     "[envelope-history]" & ASCII.LF &
     "identities = [""food"", ""daily""]" & ASCII.LF &
     "expense-routing = []" & ASCII.LF;

   Budget_Journal : constant String :=
     "2026-07-31 Clean epoch" & ASCII.LF &
     "    budget:opening          0 JPY" & ASCII.LF &
     "    budget:unassigned       0 JPY" & ASCII.LF & ASCII.LF &
     "2026-08-01 Food grant" & ASCII.LF &
     "    budget:unassigned  -10000 JPY" & ASCII.LF &
     "    budget:food         10000 JPY" & ASCII.LF & ASCII.LF &
     "2026-08-02 Future transfer" & ASCII.LF &
     "    budget:food         -2000 JPY" & ASCII.LF &
     "    budget:daily         2000 JPY" & ASCII.LF;

   Policy       : HRA.Budget_Config.Budget_Policy;
   Config       : HRA.Household_Config.Household_Configuration;
   Config_Diag  : HRA.Config_Support.Config_Diagnostic;
   Budget_Ledger : HRA.Ledger.Ledger;
   Parse_Error  : Unbounded_String;
   Registry     : HRA.Envelope.Envelope_Registry;
   Names        : HRA.Config_Support.String_Vectors.Vector;
   Food         : HRA.Envelope.Envelope_Id;
   Daily        : HRA.Envelope.Envelope_Id;
   Obs          : HRA.Envelope_Entitlement.Entitlement_Observation;
   Adapter_Diag : HRA.Budget_Source_Adapter.Adapter_Diagnostic;
   JPY          : constant Commodity := Make_Commodity ("JPY");

begin
   Put_Line ("--- Testing dated Entitlement observation horizon ---");

   Assert
     (HRA.Budget_Config.Parse_Budget_Policy
        (Budget_TOML, Policy, Config_Diag),
      "parse current Budget policy");
   Assert
     (HRA.Household_Config.Parse_Household_Configuration
        (Household_TOML, Policy, Config, Config_Diag),
      "parse clean Household coordinates");
   Assert
     (HRA.Journal.Parse_Journal_Text
        (Budget_Journal, Budget_Ledger, Parse_Error),
      "parse Budget history with future movement");

   Names.Append ("food");
   Names.Append ("daily");
   Assert
     (HRA.Envelope.Admit_Registry (Names, Registry, Config_Diag),
      "admit Envelope registry");
   Assert
     (HRA.Envelope.Lookup (Registry, "food", Food)
        and then HRA.Envelope.Lookup (Registry, "daily", Daily),
      "resolve Envelope identities");

   Assert
     (HRA.Budget_Source_Adapter.Observe_Entitlements
        (Budget_Ledger.Transactions,
         Config,
         Registry,
         D ("2026-07-30"),
         Obs,
         Adapter_Diag),
      "observe before clean epoch");
   Assert
     (not HRA.Envelope_Entitlement.Has_Origin (Obs, JPY)
        and then Is_Zero_Balance
          (HRA.Envelope_Entitlement.Entitlement_For (Obs, Food))
        and then Is_Zero_Balance
          (HRA.Envelope_Entitlement.Entitlement_For (Obs, Daily)),
      "origin and stock are absent before the Budget epoch");

   Assert
     (HRA.Budget_Source_Adapter.Observe_Entitlements
        (Budget_Ledger.Transactions,
         Config,
         Registry,
         D ("2026-08-01"),
         Obs,
         Adapter_Diag),
      "observe through first grant");
   Assert
     (HRA.Envelope_Entitlement.Has_Origin (Obs, JPY)
        and then HRA.Dates.Image
          (HRA.Envelope_Entitlement.Origin_For (Obs, JPY)) = "2026-07-31",
      "zero movement establishes origin once observation reaches it");
   Assert
     (Lookup_Balance
        (HRA.Envelope_Entitlement.Entitlement_For (Obs, Food), JPY) = 10000.0
        and then Is_Zero_Balance
          (HRA.Envelope_Entitlement.Entitlement_For (Obs, Daily))
        and then Lookup_Balance
          (HRA.Envelope_Entitlement.Unallocated_Balance (Obs), JPY) = -10000.0,
      "future Budget transfer does not leak into earlier Entitlement");

   Assert
     (HRA.Budget_Source_Adapter.Observe_Entitlements
        (Budget_Ledger.Transactions,
         Config,
         Registry,
         D ("2026-08-02"),
         Obs,
         Adapter_Diag),
      "observe through future transfer day");
   Assert
     (Lookup_Balance
        (HRA.Envelope_Entitlement.Entitlement_For (Obs, Food), JPY) = 8000.0
        and then Lookup_Balance
          (HRA.Envelope_Entitlement.Entitlement_For (Obs, Daily), JPY) = 2000.0,
      "Budget transfer becomes visible on its own observation day");

   Put_Line
     (Natural'Image (Passed_Count) & " passed, " &
      Natural'Image (Failed_Count) & " failed");

   if Failed_Count > 0 then
      raise Program_Error with "dated Entitlement observation tests failed";
   end if;
end Test_Entitlement_Observation_Horizon;
