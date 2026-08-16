with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with ALedger.Backing_Policy;
with ALedger.Cycle_Observation;
with ALedger.Dates;
with ALedger.Envelope_Commitment;
with ALedger.Envelope_Consumption;
with ALedger.Envelope_Fulfillment;
with ALedger.Envelope_Position;
with ALedger.Household;
with ALedger.Plan_Observation;
with ALedger.Recent_Journal;
with ALedger.Report_Plan;

package ALedger.Household_Report_Observation is

   type Report_Observation is record
      Observed_Through   : ALedger.Dates.Date;
      Query_Plan         : ALedger.Report_Plan.Resolved_Report_Plan;
      Recent_Journal     : ALedger.Recent_Journal.Observation;
      Open_Plans         : ALedger.Plan_Observation.Open_Plan_Vectors.Vector;
      Completed_Plans    : ALedger.Plan_Observation.Completed_Plan_Vectors.Vector;
      Current_Cycle      : ALedger.Cycle_Observation.Cycle_Window;
      Consumption        : ALedger.Envelope_Consumption.Envelope_Consumption;
      Fulfillment        : ALedger.Envelope_Fulfillment.Envelope_Fulfillment;
      Commitment         : ALedger.Envelope_Commitment.Commitment_Observation;
      Envelope_Positions : ALedger.Envelope_Position.Observation;
      Funding_Commitment : ALedger.Backing_Policy.Funding_Commitment_Observation;
      Backing            : ALedger.Backing_Policy.Backing_Observation;
   end record;

   function Observe
     (Observed_Through : ALedger.Dates.Date;
      State            : ALedger.Household.Household_State;
      Result           : out Report_Observation;
      Error_Msg        : out Unbounded_String) return Boolean;

end ALedger.Household_Report_Observation;
