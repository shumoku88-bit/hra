with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA.Cycle_Observation;
with HRA.Dates;
with HRA.Household;
with HRA.Household_Envelope_Change;
with HRA.Household_Envelope_Cycle_Comparison;
with HRA.Household_Envelope_Explanation;

--  Pure temporal use-case composition over one already-admitted Household.
--  This package selects temporal coordinates and delegates all Envelope
--  observation, explanation, Change, and cycle-comparison arithmetic to their
--  named owners.
package HRA.Household_Temporal is

   --  Same-cycle Change diagnostics remain specific to that temporal question.
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

   --  Cross-cycle comparison is a distinct temporal question and therefore has
   --  its own diagnostic algebra instead of widening the meaning of Change.
   type Cycle_Comparison_View_Status is
     (Cycle_Comparison_View_Success,
      Cycle_Current_Observation_Unavailable,
      Cycle_Context_Unavailable,
      Cycle_Comparison_Rejected);

   type Cycle_Comparison_View_Diagnostic
     (Status : Cycle_Comparison_View_Status := Cycle_Comparison_View_Success)
   is record
      case Status is
         when Cycle_Comparison_View_Success =>
            null;
         when Cycle_Current_Observation_Unavailable =>
            Observation_Error : Unbounded_String;
         when Cycle_Context_Unavailable =>
            Cycle_Status : HRA.Cycle_Observation.Resolve_Status;
         when Cycle_Comparison_Rejected =>
            Cycle_Comparison :
              HRA.Household_Envelope_Cycle_Comparison.Observe_Diagnostic;
      end case;
   end record;

   function Observe_Envelope_Change
     (Observed_Through : HRA.Dates.Date;
      Previous         : HRA.Household_Envelope_Change.Previous_Observation_Context;
      Baseline         : HRA.Household_Envelope_Change.Baseline_Request;
      State            : HRA.Household.Household_State;
      Result           : out HRA.Household_Envelope_Change.Change_Observation;
      Diag             : out Observe_Diagnostic) return Boolean;

   --  Compare the current Envelope cycle with the immediately previous admitted
   --  income-anchor cycle at equal elapsed day. This is a distinct temporal
   --  view, never a cross-cycle weakening of Change.
   function Observe_Envelope_Aligned_Previous_Cycle
     (Observed_Through : HRA.Dates.Date;
      State            : HRA.Household.Household_State;
      Result           : out
        HRA.Household_Envelope_Cycle_Comparison.Comparison_Observation;
      Diag             : out Cycle_Comparison_View_Diagnostic) return Boolean;

end HRA.Household_Temporal;
