with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA.Cycle_Observation;
with HRA.Envelope;
with HRA.Envelope_Position;
with HRA.Household_Envelope_Observation;

package body HRA.Household_Envelope_Explanation is

   function Capture
     (Policy           : HRA.Budget_Config.Budget_Policy;
      Registry         : HRA.Envelope.Envelope_Registry;
      Window           : HRA.Cycle_Observation.Cycle_Window;
      Observed_Through : HRA.Dates.Date;
      Positions        : HRA.Envelope_Position.Observation;
      Result           : out Explanation_Observation;
      Diag             : out Explain_Diagnostic) return Boolean
   is
      Output : Explanation_Observation :=
        (Window           => Window,
         Observed_Through => Observed_Through,
         Lines            => Explanation_Line_Vectors.Empty_Vector);
   begin
      if not HRA.Cycle_Observation.Contains (Window, Observed_Through) then
         Result := Output;
         Diag :=
           (Status           => Observation_Outside_Window,
            Rejected_Through => Observed_Through);
         return False;
      end if;

      for Def of Policy.Envelopes loop
         declare
            Env_Text : constant String := To_String (Def.ID);
            Env      : HRA.Envelope.Envelope_Id;
         begin
            if not HRA.Envelope.Lookup (Registry, Env_Text, Env) then
               Result := Output;
               Diag :=
                 (Status           => Unknown_Current_Envelope,
                  Envelope_Id_Text => To_Unbounded_String (Env_Text));
               return False;
            end if;

            if not HRA.Envelope_Position.Has_Explanation (Positions, Env) then
               Result := Output;
               Diag :=
                 (Status           => Missing_Envelope_Explanation,
                  Envelope_Id_Text => To_Unbounded_String (Env_Text));
               return False;
            end if;

            Output.Lines.Append
              (Explanation_Line'
                 (Env_Id => Env,
                  Why    => HRA.Envelope_Position.Explain (Positions, Env)));
         end;
      end loop;

      Result := Output;
      Diag := (Status => Success);
      return True;
   end Capture;

   function Explain
     (Observed_Through : HRA.Dates.Date;
      State            : HRA.Household.Household_State;
      Result           : out Explanation_Observation;
      Diag             : out Explain_Diagnostic) return Boolean
   is
      Observation : HRA.Household_Envelope_Observation.Observation;
      Error_Msg   : Unbounded_String;
   begin
      if not HRA.Household_Envelope_Observation.Observe
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

end HRA.Household_Envelope_Explanation;
