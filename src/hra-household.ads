with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA.Account;        use HRA.Account;
with HRA.Ledger;         use HRA.Ledger;
with HRA.Issues;         use HRA.Issues;
with HRA.Canonical_Source;
with HRA.Budget_Config;
with HRA.Household_Config;
with HRA.Report_Config;
with HRA.Journal_Evidence;
with HRA.Actual_Admission;
with HRA.Plan;
with HRA.Envelope;
with HRA.Envelope_Routing;
with HRA.Fulfillment_Routing;
with HRA.Backing_Policy;

package HRA.Household is

   --  ========================================================================
   --  Canonical Household Root & 8 Physical Source Topology
   --  ========================================================================

   subtype Source_Paths is HRA.Canonical_Source.Source_Paths;

   function Resolve_Source_Paths (Root_Dir : String) return Source_Paths
     renames HRA.Canonical_Source.Resolve_Source_Paths;

   --  ========================================================================
   --  Household State (Admitted facts from all canonical sources)
   --  ========================================================================

   type Household_State is record
      Root_Path           : Unbounded_String;
      Paths               : Source_Paths;
      Sources             : HRA.Canonical_Source.Source_Observation;
      Budget_Policy       : HRA.Budget_Config.Budget_Policy;
      Household_Policy    : HRA.Household_Config.Household_Configuration;
      Report_Policy       : HRA.Report_Config.Report_Configuration;
      Registry            : Account_Registry;
      Actual_Ledger       : Ledger.Ledger;
      Actual_Evidence     : HRA.Journal_Evidence.Journal_Evidence;
      Actual_Identity     : HRA.Actual_Admission.Actual_Observation;
      Plan_Ledger         : Ledger.Ledger;
      Plan_Evidence       : HRA.Journal_Evidence.Journal_Evidence;
      Plan_Ids            : HRA.Plan.Plan_Id_Universe;
      Budget_Ledger       : Ledger.Ledger;
      Combined_Ledger     : Ledger.Ledger;
      Issues              : Issues_Inventory;
      Envelope_Registry   : HRA.Envelope.Envelope_Registry;
      Routing_History     : HRA.Envelope_Routing.Routing_History;
      Fulfillment_History : HRA.Fulfillment_Routing.Fulfillment_Routing_History;
      Backing_Policy_Spec : HRA.Backing_Policy.Backing_Policy;
   end record;

   function Empty_Household_State return Household_State;

   --  Admit one already-observed canonical source set without reading the
   --  eight root files again. This is the semantic boundary mutation use cases
   --  can exercise before any filesystem publication.
   function Admit_Canonical_Household
     (Observation : HRA.Canonical_Source.Source_Observation;
      State       : out Household_State;
      Error_Msg   : out Unbounded_String) return Boolean;

   --  Filesystem convenience boundary: observe all eight exact root bytes,
   --  then delegate the complete semantic admission to Admit_Canonical_Household.
   function Load_Canonical_Household
     (Root_Dir  : String;
      State     : out Household_State;
      Error_Msg : out Unbounded_String) return Boolean;

end HRA.Household;
