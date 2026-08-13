with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with ALedger.Account;        use ALedger.Account;
with ALedger.Ledger;         use ALedger.Ledger;
with ALedger.Issues;         use ALedger.Issues;

package ALedger.Household is

   --  ========================================================================
   --  Canonical Household Root & 8 Physical Source Topology
   --  ========================================================================

   type Source_Paths is record
      Accounts_Journal : Unbounded_String;
      Actual_Journal   : Unbounded_String;
      Plan_Journal     : Unbounded_String;
      Budget_Journal   : Unbounded_String;
      Budget_TOML      : Unbounded_String;
      Household_TOML   : Unbounded_String;
      Report_TOML      : Unbounded_String;
      Issues_TSV       : Unbounded_String;
   end record;

   function Resolve_Source_Paths (Root_Dir : String) return Source_Paths;

   --  ========================================================================
   --  Household State (Admitted facts from all canonical sources)
   --  ========================================================================

   type Household_State is record
      Root_Path       : Unbounded_String;
      Paths           : Source_Paths;
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
