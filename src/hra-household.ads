with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA.Account;        use HRA.Account;
with HRA.Ledger;         use HRA.Ledger;
with HRA.Issues;         use HRA.Issues;
with HRA.Canonical_Source;
with HRA.Envelope_Config;
with HRA.Household_Config;
with HRA.Report_Config;
with HRA.Journal_Evidence;
with HRA.Actual_Admission;
with HRA.Plan;
with HRA.Plan_Admission;
with HRA.Plan_Completion;
with HRA.Daily_Target_Scope;
with HRA.Envelope;
with HRA.Entitlement_Journal;
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

   --  Daily Target is a deliberately narrower projection than general Plan
   --  admission. A valid Household therefore remains admitted when that narrow
   --  scope cannot represent one selected Plan. Retain either the admitted
   --  scope or its exact diagnostic once, so later observers never re-admit
   --  the same policy/Plan evidence or turn a section failure into a Household
   --  failure.
   type Daily_Target_Scope_Availability is
     (Daily_Target_Scope_Available,
      Daily_Target_Scope_Unavailable);

   type Daily_Target_Scope_State
     (Status : Daily_Target_Scope_Availability := Daily_Target_Scope_Available)
   is record
      case Status is
         when Daily_Target_Scope_Available =>
            Value : HRA.Daily_Target_Scope.Scope;
         when Daily_Target_Scope_Unavailable =>
            Diagnostic : HRA.Daily_Target_Scope.Admission_Diagnostic;
      end case;
   end record;

   type Household_State is record
      Root_Path           : Unbounded_String;
      Paths               : Source_Paths;
      Sources             : HRA.Canonical_Source.Source_Observation;
      Envelope_Policy     : HRA.Envelope_Config.Envelope_Policy;
      Household_Policy    : HRA.Household_Config.Household_Configuration;
      Report_Policy       : HRA.Report_Config.Report_Configuration;
      Registry            : Account_Registry;

      --  Actual_Identity is the admitted Actual authority. Actual_Ledger and
      --  Actual_Evidence are materialized read projections built from that
      --  admitted value once at Household admission, so hot observation/TUI
      --  paths do not rebuild vectors on every navigation step. They are not
      --  independent semantic authorities and must never retain loader peers.
      Actual_Ledger       : Ledger.Ledger;
      Actual_Evidence     : HRA.Journal_Evidence.Journal_Evidence;
      Actual_Identity     : HRA.Actual_Admission.Actual_Observation;

      --  These are the admitted Plan authorities. Read projections such as
      --  Ledger, source evidence, and the PlanId universe are derived from
      --  Plan_Journal only at the boundary that needs them.
      Plan_Journal        : HRA.Plan_Admission.Plan_Journal;
      Plan_Completions    : HRA.Plan_Completion.Completion_Relations;

      Daily_Target        : Daily_Target_Scope_State;

      Entitlement_History : HRA.Entitlement_Journal.Entitlement_History;
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
