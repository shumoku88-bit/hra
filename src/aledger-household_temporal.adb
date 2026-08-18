with ALedger.Household_Envelope_Observation;

package body ALedger.Household_Temporal is

   function Observe_Envelope_Change
     (Observed_Through : ALedger.Dates.Date;
      Previous         : ALedger.Household_Envelope_Change.Previous_Observation_Context;
      Baseline         : ALedger.Household_Envelope_Change.Baseline_Request;
      State            : ALedger.Household.Household_State;
      Result           : out ALedger.Household_Envelope_Change.Change_Observation;
      Diag             : out Observe_Diagnostic) return Boolean
   is
      Current : ALedger.Household_Envelope_Observation.Observation;
      Earlier : ALedger.Household_Envelope_Observation.Observation;
      Observation_Error : Unbounded_String;

      Resolved : ALedger.Household_Envelope_Change.Resolved_Change_Baseline;
      Baseline_Diag : ALedger.Household_Envelope_Change.Baseline_Diagnostic;

      Current_Snapshot : ALedger.Household_Envelope_Change.Explanation_Snapshot;
      Earlier_Snapshot : ALedger.Household_Envelope_Change.Explanation_Snapshot;
      Snapshot_Diag    : ALedger.Household_Envelope_Change.Snapshot_Diagnostic;
      Change_Diag      : ALedger.Household_Envelope_Change.Change_Diagnostic;
   begin
      if not ALedger.Household_Envelope_Observation.Observe
        (Observed_Through, State, Current, Observation_Error)
      then
         Diag :=
           (Status            => Current_Observation_Unavailable,
            Observation_Error => Observation_Error);
         return False;
      end if;

      if not ALedger.Household_Envelope_Change.Resolve_Baseline
        (Current.Current_Cycle,
         Observed_Through,
         Previous,
         Baseline,
         Resolved,
         Baseline_Diag)
      then
         Diag :=
           (Status   => Baseline_Unavailable,
            Baseline => Baseline_Diag);
         return False;
      end if;

      if not ALedger.Household_Envelope_Observation.Observe
        (ALedger.Household_Envelope_Change.Resolved_Day (Resolved),
         State,
         Earlier,
         Observation_Error)
      then
         Diag :=
           (Status            => Earlier_Observation_Unavailable,
            Observation_Error => Observation_Error);
         return False;
      end if;

      if not ALedger.Household_Envelope_Change.Capture
        (State.Budget_Policy,
         State.Envelope_Registry,
         Earlier.Current_Cycle,
         Earlier.Observed_Through,
         Earlier.Envelope_Positions,
         Earlier_Snapshot,
         Snapshot_Diag)
      then
         Diag :=
           (Status   => Earlier_Snapshot_Unavailable,
            Snapshot => Snapshot_Diag);
         return False;
      end if;

      if not ALedger.Household_Envelope_Change.Capture
        (State.Budget_Policy,
         State.Envelope_Registry,
         Current.Current_Cycle,
         Current.Observed_Through,
         Current.Envelope_Positions,
         Current_Snapshot,
         Snapshot_Diag)
      then
         Diag :=
           (Status   => Current_Snapshot_Unavailable,
            Snapshot => Snapshot_Diag);
         return False;
      end if;

      if not ALedger.Household_Envelope_Change.Observe_Change
        (Earlier_Snapshot, Current_Snapshot, Result, Change_Diag)
      then
         Diag :=
           (Status => Change_Rejected,
            Change => Change_Diag);
         return False;
      end if;

      Diag := (Status => Success);
      return True;
   end Observe_Envelope_Change;

end ALedger.Household_Temporal;
