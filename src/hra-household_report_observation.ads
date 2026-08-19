with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA.Backing_Policy;
with HRA.Cycle_Observation;
with HRA.Dates;
with HRA.Envelope_Commitment;
with HRA.Envelope_Consumption;
with HRA.Envelope_Entitlement;
with HRA.Envelope_Fulfillment;
with HRA.Envelope_Position;
with HRA.Household;
with HRA.Plan_Observation;
with HRA.Recent_Journal;
with HRA.Report_Plan;

package HRA.Household_Report_Observation is

   type Report_Observation is record
      Observed_Through   : HRA.Dates.Date;
      Query_Plan         : HRA.Report_Plan.Resolved_Report_Plan;
      Recent_Journal     : HRA.Recent_Journal.Observation;
      Open_Plans         : HRA.Plan_Observation.Open_Plan_Vectors.Vector;
      Completed_Plans    : HRA.Plan_Observation.Completed_Plan_Vectors.Vector;
      Current_Cycle      : HRA.Cycle_Observation.Cycle_Window;
      Entitlement        : HRA.Envelope_Entitlement.Entitlement_Observation;
      Consumption        : HRA.Envelope_Consumption.Envelope_Consumption;
      Fulfillment        : HRA.Envelope_Fulfillment.Envelope_Fulfillment;
      Commitment         : HRA.Envelope_Commitment.Commitment_Observation;
      Envelope_Positions : HRA.Envelope_Position.Observation;
      Funding_Commitment : HRA.Backing_Policy.Funding_Commitment_Observation;
      Backing            : HRA.Backing_Policy.Backing_Observation;
   end record;

   function Observe
     (Observed_Through : HRA.Dates.Date;
      State            : HRA.Household.Household_State;
      Result           : out Report_Observation;
      Error_Msg        : out Unbounded_String) return Boolean;

end HRA.Household_Report_Observation;
