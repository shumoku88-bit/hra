with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA.Cycle_Observation;
with HRA.Dates;
with HRA.Envelope_Commitment;
with HRA.Envelope_Consumption;
with HRA.Envelope_Entitlement;
with HRA.Envelope_Fulfillment;
with HRA.Envelope_Position;
with HRA.Household;
with HRA.Plan_Observation;

--  Focused Envelope observation over one already-admitted Household state.
--  This package owns use-case composition only. Source admission remains in
--  HRA.Household and arithmetic remains in the named Envelope owners.
package HRA.Household_Envelope_Observation is

   type Observation is record
      Observed_Through   : HRA.Dates.Date;
      Open_Plans         : HRA.Plan_Observation.Open_Plan_Vectors.Vector;
      Completed_Plans    : HRA.Plan_Observation.Completed_Plan_Vectors.Vector;
      Current_Cycle      : HRA.Cycle_Observation.Cycle_Window;
      Entitlement        : HRA.Envelope_Entitlement.Entitlement_Observation;
      Consumption        : HRA.Envelope_Consumption.Envelope_Consumption;
      Fulfillment        : HRA.Envelope_Fulfillment.Envelope_Fulfillment;
      Commitment         : HRA.Envelope_Commitment.Commitment_Observation;
      Envelope_Positions : HRA.Envelope_Position.Observation;
   end record;

   function Observe
     (Observed_Through : HRA.Dates.Date;
      State            : HRA.Household.Household_State;
      Result           : out Observation;
      Error_Msg        : out Unbounded_String) return Boolean;

end HRA.Household_Envelope_Observation;
