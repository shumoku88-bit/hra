with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with ALedger.Cycle_Observation;
with ALedger.Dates;
with ALedger.Envelope_Commitment;
with ALedger.Envelope_Consumption;
with ALedger.Envelope_Entitlement;
with ALedger.Envelope_Fulfillment;
with ALedger.Envelope_Position;
with ALedger.Household;
with ALedger.Plan_Observation;

--  Focused Envelope observation over one already-admitted Household state.
--  This package owns use-case composition only. Source admission remains in
--  ALedger.Household and arithmetic remains in the named Envelope owners.
package ALedger.Household_Envelope_Observation is

   type Observation is record
      Observed_Through   : ALedger.Dates.Date;
      Open_Plans         : ALedger.Plan_Observation.Open_Plan_Vectors.Vector;
      Completed_Plans    : ALedger.Plan_Observation.Completed_Plan_Vectors.Vector;
      Current_Cycle      : ALedger.Cycle_Observation.Cycle_Window;
      Entitlement        : ALedger.Envelope_Entitlement.Entitlement_Observation;
      Consumption        : ALedger.Envelope_Consumption.Envelope_Consumption;
      Fulfillment        : ALedger.Envelope_Fulfillment.Envelope_Fulfillment;
      Commitment         : ALedger.Envelope_Commitment.Commitment_Observation;
      Envelope_Positions : ALedger.Envelope_Position.Observation;
   end record;

   function Observe
     (Observed_Through : ALedger.Dates.Date;
      State            : ALedger.Household.Household_State;
      Result           : out Observation;
      Error_Msg        : out Unbounded_String) return Boolean;

end ALedger.Household_Envelope_Observation;
