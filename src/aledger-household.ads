with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with ALedger.Account;        use ALedger.Account;
with ALedger.Ledger;         use ALedger.Ledger;
with ALedger.Issues;         use ALedger.Issues;
with ALedger.Canonical_Source;
with ALedger.Budget_Config;
with ALedger.Household_Config;
with ALedger.Report_Config;

package ALedger.Household is

   --  ========================================================================
   --  Canonical Household Root & 8 Physical Source Topology
   --  ========================================================================

   subtype Source_Paths is ALedger.Canonical_Source.Source_Paths;

   function Resolve_Source_Paths (Root_Dir : String) return Source_Paths
     renames ALedger.Canonical_Source.Resolve_Source_Paths;

   --  ========================================================================
   --  Household State (Admitted facts from all canonical sources)
   --  ========================================================================

   type Household_State is record
      Root_Path       : Unbounded_String;
      Paths           : Source_Paths;
      Sources         : ALedger.Canonical_Source.Source_Observation;
      Budget_Policy   : ALedger.Budget_Config.Budget_Policy;
      Household_Policy : ALedger.Household_Config.Household_Configuration;
      Report_Policy   : ALedger.Report_Config.Report_Configuration;
      Registry        : Account_Registry;
      Actual_Ledger   : Ledger.Ledger;
      Plan_Ledger     : Ledger.Ledger;
      Budget_Ledger   : Ledger.Ledger;
      Combined_Ledger : Ledger.Ledger;
      Issues          : Issues_Inventory;
   end record;

   function Empty_Household_State return Household_State;

   function Load_Canonical_Household
     (Root_Dir  : String;
      State     : out Household_State;
      Error_Msg : out Unbounded_String) return Boolean;

end ALedger.Household;
