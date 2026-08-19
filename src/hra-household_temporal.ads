with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA.Dates;
with HRA.Household;
with HRA.Household_Envelope_Change;
with HRA.Household_Envelope_Explanation;

--  Pure temporal use-case composition over one already-admitted Household.
--  This package selects temporal coordinates and delegates all Envelope
--  observation, explanation, and Change arithmetic to their named owners.
package HRA.Household_Temporal is

   type Observe_Status is
     (Success,
      Current_Observation_Unavailable,
      Baseline_Unavailable,
      Earlier_Observation_Unavailable,
      Current_Explanation_Unavailable,
      Earlier_Explanation_Unavailable,
      Change_Rejected);

   type Observe_Diagnostic (Status : Observe_Status := Success) is record
      case Status is
         when Success =>
            null;
         when Current_Observation_Unavailable |
              Earlier_Observation_Unavailable =>
            Observation_Error : Unbounded_String;
         when Baseline_Unavailable =>
            Baseline : HRA.Household_Envelope_Change.Baseline_Diagnostic;
         when Current_Explanation_Unavailable |
              Earlier_Explanation_Unavailable =>
            Explanation :
              HRA.Household_Envelope_Explanation.Explain_Diagnostic;
         when Change_Rejected =>
            Change : HRA.Household_Envelope_Change.Change_Diagnostic;
      end case;
   end record;

   function Observe_Envelope_Change
     (Observed_Through : HRA.Dates.Date;
      Previous         : HRA.Household_Envelope_Change.Previous_Observation_Context;
      Baseline         : HRA.Household_Envelope_Change.Baseline_Request;
      State            : HRA.Household.Household_State;
      Result           : out HRA.Household_Envelope_Change.Change_Observation;
      Diag             : out Observe_Diagnostic) return Boolean;

end HRA.Household_Temporal;
