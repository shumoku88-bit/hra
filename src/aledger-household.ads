with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with ALedger.Account;        use ALedger.Account;
with ALedger.Ledger;         use ALedger.Ledger;
with ALedger.Issues;         use ALedger.Issues;
with ALedger.Canonical_Source;
with ALedger.Budget_Config;
with ALedger.Household_Config;
with ALedger.Report_Config;
with ALedger.Journal_Evidence;
with ALedger.Actual_Admission;
with ALedger.Plan;
with ALedger.Envelope;
with ALedger.Envelope_Routing;
with ALedger.Fulfillment_Routing;
with ALedger.Backing_Policy;

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
      Root_Path           : Unbounded_String;
      Paths               : Source_Paths;
      Sources             : ALedger.Canonical_Source.Source_Observation;
      Budget_Policy       : ALedger.Budget_Config.Budget_Policy;
      Household_Policy    : ALedger.Household_Config.Household_Configuration;
      Report_Policy       : ALedger.Report_Config.Report_Configuration;
      Registry            : Account_Registry;
      Actual_Ledger       : Ledger.Ledger;
      Actual_Evidence     : ALedger.Journal_Evidence.Journal_Evidence;
      Actual_Identity     : ALedger.Actual_Admission.Actual_Observation;
      Plan_Ledger         : Ledger.Ledger;
      Plan_Evidence       : ALedger.Journal_Evidence.Journal_Evidence;
      Plan_Ids            : ALedger.Plan.Plan_Id_Universe;
      Budget_Ledger       : Ledger.Ledger;
      Combined_Ledger     : Ledger.Ledger;
      Issues              : Issues_Inventory;
      Envelope_Registry   : ALedger.Envelope.Envelope_Registry;
      Routing_History     : ALedger.Envelope_Routing.Routing_History;
      Fulfillment_History : ALedger.Fulfillment_Routing.Fulfillment_Routing_History;
      Backing_Policy_Spec : ALedger.Backing_Policy.Backing_Policy;
   end record;

   function Empty_Household_State return Household_State;

   function Load_Canonical_Household
     (Root_Dir  : String;
      State     : out Household_State;
      Error_Msg : out Unbounded_String) return Boolean;

end ALedger.Household;
