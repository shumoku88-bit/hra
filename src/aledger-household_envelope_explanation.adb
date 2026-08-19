with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with ALedger.Cycle_Observation;
with ALedger.Envelope;
with ALedger.Envelope_Position;
with ALedger.Household_Envelope_Observation;

package body ALedger.Household_Envelope_Explanation is

   function Capture
     (Policy           : ALedger.Budget_Config.Budget_Policy;
      Registry         : ALedger.Envelope.Envelope_Registry;
      Window           : ALedger.Cycle_Observation.Cycle_Window;
      Observed_Through : ALedger.Dates.Date;
      Positions        : ALedger.Envelope_Position.Observation;
      Result           : out Explanation_Observation;
      Diag             : out Explain_Diagnostic) return Boolean
   is
      Output : Explanation_Observation :=
        (Window           => Window,
         Observed_Through => Observed_Through,
         Lines            => Explanation_Line_Vectors.Empty_Vector);
   begin
      if not ALedger.Cycle_Observation.Contains (Window, Observed_Through) then
         Result := Output;
         Diag :=
           (Status           => Observation_Outside_Window,
            Rejected_Through => Observed_Through);
         return False;
      end if;

      for Def of Policy.Envelopes loop
         declare
            Env_Text : constant String := To_String (Def.ID);
            Env      : ALedger.Envelope.Envelope_Id;
         begin
            if not ALedger.Envelope.Lookup (Registry, Env_Text, Env) then
               Result := Output;
               Diag :=
                 (Status           => Unknown_Current_Envelope,
                  Envelope_Id_Text => To_Unbounded_String (Env_Text));
               return False;
            end if;

            if not ALedger.Envelope_Position.Has_Explanation (Positions, Env) then
               Result := Output;
               Diag :=
                 (Status           => Missing_Envelope_Explanation,
                  Envelope_Id_Text => To_Unbounded_String (Env_Text));
               return False;
            end if;

            Output.Lines.Append
              (Explanation_Line'
                 (Env_Id => Env,
                  Why    => ALedger.Envelope_Position.Explain (Positions, Env)));
         end;
      end loop;

      Result := Output;
      Diag := (Status => Success);
      return True;
   end Capture;

   function Explain
     (Observed_Through : ALedger.Dates.Date;
      State            : ALedger.Household.Household_State;
      Result           : out Explanation_Observation;
      Diag             : out Explain_Diagnostic) return Boolean
   is
      Observation : ALedger.Household_Envelope_Observation.Observation;
      Error_Msg   : Unbounded_String;
   begin
      if not ALedger.Household_Envelope_Observation.Observe
        (Observed_Through, State, Observation, Error_Msg)
      then
         Diag :=
           (Status            => Observation_Unavailable,
            Observation_Error => Error_Msg);
         return False;
      end if;

      return Capture
        (State.Budget_Policy,
         State.Envelope_Registry,
         Observation.Current_Cycle,
         Observation.Observed_Through,
         Observation.Envelope_Positions,
         Result,
         Diag);
   end Explain;

end ALedger.Household_Envelope_Explanation;
