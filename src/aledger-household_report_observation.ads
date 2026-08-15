with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with ALedger.Backing_Policy;
with ALedger.Cycle_Observation;
with ALedger.Envelope_Commitment;
with ALedger.Envelope_Consumption;
with ALedger.Household;
with ALedger.Plan_Observation;

package ALedger.Household_Report_Observation is

   --  One report-time semantic observation derived from an already admitted
   --  Household snapshot. No source is reread and no clock is captured here.
   type Report_Observation is record
      Observed_Through : Unbounded_String;
      Open_Plans       : ALedger.Plan_Observation.Open_Plan_Vectors.Vector;
      Current_Cycle    : ALedger.Cycle_Observation.Cycle_Window;
      Consumption     : ALedger.Envelope_Consumption.Envelope_Consumption;
      Commitment      : ALedger.Envelope_Commitment.Commitment_Observation;
      Backing         : ALedger.Backing_Policy.Backing_Observation;
   end record;

   function Observe
     (Observed_Through : String;
      State            : ALedger.Household.Household_State;
      Result           : out Report_Observation;
      Error_Msg        : out Unbounded_String) return Boolean;

end ALedger.Household_Report_Observation;
