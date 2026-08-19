with HRA.Account;
with HRA.Cycle_Observation;
with HRA.Household_Envelope_Cycle_Comparison;
with HRA.Household_Envelope_Explanation;
with HRA.Household_Envelope_Observation;

package body HRA.Household_Temporal is

   function Observe_Envelope_Change
     (Observed_Through : HRA.Dates.Date;
      Previous         : HRA.Household_Envelope_Change.Previous_Observation_Context;
      Baseline         : HRA.Household_Envelope_Change.Baseline_Request;
      State            : HRA.Household.Household_State;
      Result           : out HRA.Household_Envelope_Change.Change_Observation;
      Diag             : out Observe_Diagnostic) return Boolean
   is
      Current : HRA.Household_Envelope_Observation.Observation;
      Earlier : HRA.Household_Envelope_Observation.Observation;
      Observation_Error : Unbounded_String;

      Resolved : HRA.Household_Envelope_Change.Resolved_Change_Baseline;
      Baseline_Diag : HRA.Household_Envelope_Change.Baseline_Diagnostic;

      Current_Explanation :
        HRA.Household_Envelope_Explanation.Explanation_Observation;
      Earlier_Explanation :
        HRA.Household_Envelope_Explanation.Explanation_Observation;
      Explanation_Diag :
        HRA.Household_Envelope_Explanation.Explain_Diagnostic;
      Change_Diag : HRA.Household_Envelope_Change.Change_Diagnostic;
   begin
      if not HRA.Household_Envelope_Observation.Observe
        (Observed_Through, State, Current, Observation_Error)
      then
         Diag :=
           (Status            => Current_Observation_Unavailable,
            Observation_Error => Observation_Error);
         return False;
      end if;

      if not HRA.Household_Envelope_Change.Resolve_Baseline
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

      --  Resolve_Baseline has already proved the earlier coordinate belongs to
      --  Current.Current_Cycle. Re-observing through the generic current-cycle
      --  resolver would throw away that typed temporal evidence and infer it
      --  again from source anchors.
      if not HRA.Household_Envelope_Observation.Observe_In_Window
        (HRA.Household_Envelope_Change.Resolved_Day (Resolved),
         Current.Current_Cycle,
         State,
         Earlier,
         Observation_Error)
      then
         Diag :=
           (Status            => Earlier_Observation_Unavailable,
            Observation_Error => Observation_Error);
         return False;
      end if;

      if not HRA.Household_Envelope_Explanation.Capture
        (State.Budget_Policy,
         State.Envelope_Registry,
         Earlier.Current_Cycle,
         Earlier.Observed_Through,
         Earlier.Envelope_Positions,
         Earlier_Explanation,
         Explanation_Diag)
      then
         Diag :=
           (Status      => Earlier_Explanation_Unavailable,
            Explanation => Explanation_Diag);
         return False;
      end if;

      if not HRA.Household_Envelope_Explanation.Capture
        (State.Budget_Policy,
         State.Envelope_Registry,
         Current.Current_Cycle,
         Current.Observed_Through,
         Current.Envelope_Positions,
         Current_Explanation,
         Explanation_Diag)
      then
         Diag :=
           (Status      => Current_Explanation_Unavailable,
            Explanation => Explanation_Diag);
         return False;
      end if;

      if not HRA.Household_Envelope_Change.Observe_Change
        (Earlier_Explanation, Current_Explanation, Result, Change_Diag)
      then
         Diag :=
           (Status => Change_Rejected,
            Change => Change_Diag);
         return False;
      end if;

      Diag := (Status => Success);
      return True;
   end Observe_Envelope_Change;

   function Observe_Envelope_Aligned_Previous_Cycle
     (Observed_Through : HRA.Dates.Date;
      State            : HRA.Household.Household_State;
      Result           : out
        HRA.Household_Envelope_Cycle_Comparison.Comparison_Observation;
      Diag             : out Cycle_Comparison_View_Diagnostic) return Boolean
   is
      Current : HRA.Household_Envelope_Observation.Observation;
      Observation_Error : Unbounded_String;
      Cycle_Context : HRA.Cycle_Observation.Observation;
      Cycle_Status  : HRA.Cycle_Observation.Resolve_Status;
      Comparison_Diag :
        HRA.Household_Envelope_Cycle_Comparison.Observe_Diagnostic;
      Income_Account : constant HRA.Account.Account :=
        HRA.Account.Make_Account
          (To_String (State.Household_Policy.Cycle_Income_Account));
   begin
      --  The current observation already owns role-neutral Plan observation, so
      --  reuse its admitted Open Plans when selecting the temporal cycle pair.
      --  Cycle_Observation remains the sole anchor resolver.
      if not HRA.Household_Envelope_Observation.Observe
        (Observed_Through, State, Current, Observation_Error)
      then
         Diag :=
           (Status            => Cycle_Current_Observation_Unavailable,
            Observation_Error => Observation_Error);
         return False;
      end if;

      if not HRA.Cycle_Observation.Observe
        (Observed_Through,
         State.Actual_Ledger,
         Current.Open_Plans,
         State.Registry,
         Income_Account,
         Cycle_Context,
         Cycle_Status)
      then
         Diag :=
           (Status       => Cycle_Context_Unavailable,
            Cycle_Status => Cycle_Status);
         return False;
      end if;

      if not HRA.Household_Envelope_Cycle_Comparison.Observe_Aligned
        (Observed_Through,
         Cycle_Context.Current_Window,
         Cycle_Context.Previous_Window,
         State,
         Result,
         Comparison_Diag)
      then
         Diag :=
           (Status           => Cycle_Comparison_Rejected,
            Cycle_Comparison => Comparison_Diag);
         return False;
      end if;

      Diag := (Status => Cycle_Comparison_View_Success);
      return True;
   end Observe_Envelope_Aligned_Previous_Cycle;

end HRA.Household_Temporal;
