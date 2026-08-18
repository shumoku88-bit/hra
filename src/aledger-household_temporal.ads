with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with ALedger.Dates;
with ALedger.Household;
with ALedger.Household_Envelope_Change;

--  Pure temporal use-case composition over one already-admitted Household.
--  This package selects temporal coordinates and delegates all Envelope
--  observation and Change arithmetic to their named owners.
package ALedger.Household_Temporal is

   type Observe_Status is
     (Success,
      Current_Observation_Unavailable,
      Baseline_Unavailable,
      Earlier_Observation_Unavailable,
      Current_Snapshot_Unavailable,
      Earlier_Snapshot_Unavailable,
      Change_Rejected);

   type Observe_Diagnostic (Status : Observe_Status := Success) is record
      case Status is
         when Success =>
            null;
         when Current_Observation_Unavailable |
              Earlier_Observation_Unavailable =>
            Observation_Error : Unbounded_String;
         when Baseline_Unavailable =>
            Baseline : ALedger.Household_Envelope_Change.Baseline_Diagnostic;
         when Current_Snapshot_Unavailable |
              Earlier_Snapshot_Unavailable =>
            Snapshot : ALedger.Household_Envelope_Change.Snapshot_Diagnostic;
         when Change_Rejected =>
            Change : ALedger.Household_Envelope_Change.Change_Diagnostic;
      end case;
   end record;

   function Observe_Envelope_Change
     (Observed_Through : ALedger.Dates.Date;
      Previous         : ALedger.Household_Envelope_Change.Previous_Observation_Context;
      Baseline         : ALedger.Household_Envelope_Change.Baseline_Request;
      State            : ALedger.Household.Household_State;
      Result           : out ALedger.Household_Envelope_Change.Change_Observation;
      Diag             : out Observe_Diagnostic) return Boolean;

end ALedger.Household_Temporal;
