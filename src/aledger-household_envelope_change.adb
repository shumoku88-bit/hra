with Ada.Containers;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with ALedger.Cycle_Observation;
with ALedger.Dates;
with ALedger.Envelope;
with ALedger.Envelope_Position;
with ALedger.Money; use ALedger.Money;

package body ALedger.Household_Envelope_Change is

   use type Ada.Containers.Count_Type;
   use type ALedger.Dates.Date;
   use type ALedger.Envelope.Envelope_Id;

   function Capture
     (Policy           : ALedger.Budget_Config.Budget_Policy;
      Registry         : ALedger.Envelope.Envelope_Registry;
      Window           : ALedger.Cycle_Observation.Cycle_Window;
      Observed_Through : ALedger.Dates.Date;
      Positions        : ALedger.Envelope_Position.Observation;
      Result           : out Explanation_Snapshot;
      Diag             : out Snapshot_Diagnostic) return Boolean
   is
      Output : Explanation_Snapshot :=
        (Window           => Window,
         Observed_Through => Observed_Through,
         Lines            => Explanation_Line_Vectors.Empty_Vector);
   begin
      if not ALedger.Cycle_Observation.Contains (Window, Observed_Through) then
         Result := Output;
         Diag :=
           (Status           => Observation_Outside_Window,
            Envelope_Id_Text => Null_Unbounded_String);
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
              ((Env_Id => Env,
                Why    => ALedger.Envelope_Position.Explain (Positions, Env)));
         end;
      end loop;

      Result := Output;
      Diag :=
        (Status           => Success,
         Envelope_Id_Text => Null_Unbounded_String);
      return True;
   end Capture;

   function Observed_Through
     (Snapshot : Explanation_Snapshot) return ALedger.Dates.Date
   is
   begin
      return Snapshot.Observed_Through;
   end Observed_Through;

   function Window_Of
     (Snapshot : Explanation_Snapshot)
      return ALedger.Cycle_Observation.Cycle_Window
   is
   begin
      return Snapshot.Window;
   end Window_Of;

   function Same_Window
     (Left, Right : ALedger.Cycle_Observation.Cycle_Window) return Boolean
   is
   begin
      return
        ALedger.Cycle_Observation.Start_Date (Left) =
          ALedger.Cycle_Observation.Start_Date (Right)
        and then
        ALedger.Cycle_Observation.End_Exclusive (Left) =
          ALedger.Cycle_Observation.End_Exclusive (Right);
   end Same_Window;

   function Difference (Later, Earlier : Balance) return Balance is
   begin
      return Subtract_Balance (Later, Earlier);
   end Difference;

   function Observe_Change
     (Earlier : Explanation_Snapshot;
      Later   : Explanation_Snapshot;
      Result  : out Change_Observation;
      Diag    : out Change_Diagnostic) return Boolean
   is
      Output : Change_Observation :=
        (Window       => Earlier.Window,
         From_Date    => Earlier.Observed_Through,
         Through_Date => Later.Observed_Through,
         Lines        => Change_Line_Vectors.Empty_Vector);
   begin
      if not Same_Window (Earlier.Window, Later.Window) then
         Result := Output;
         Diag := (Status => Window_Mismatch, Mismatch_Index => 0);
         return False;
      end if;

      if Earlier.Observed_Through > Later.Observed_Through then
         Result := Output;
         Diag := (Status => Observation_Order_Invalid, Mismatch_Index => 0);
         return False;
      end if;

      if Earlier.Lines.Length /= Later.Lines.Length then
         Result := Output;
         Diag := (Status => Envelope_Order_Mismatch, Mismatch_Index => 0);
         return False;
      end if;

      if not Earlier.Lines.Is_Empty then
         for I in Earlier.Lines.First_Index .. Earlier.Lines.Last_Index loop
            if Earlier.Lines.Element (I).Env_Id /= Later.Lines.Element (I).Env_Id then
               Result := Output;
               Diag :=
                 (Status         => Envelope_Order_Mismatch,
                  Mismatch_Index => Natural (I));
               return False;
            end if;
         end loop;

         for I in Earlier.Lines.First_Index .. Earlier.Lines.Last_Index loop
            declare
               Before_Line : constant Explanation_Line := Earlier.Lines.Element (I);
               After_Line  : constant Explanation_Line := Later.Lines.Element (I);
               Before_Ev   : constant ALedger.Envelope_Position.Arithmetic_Evidence :=
                 Before_Line.Why.Evidence;
               After_Ev    : constant ALedger.Envelope_Position.Arithmetic_Evidence :=
                 After_Line.Why.Evidence;
               Before_Pos  : constant ALedger.Envelope_Position.Position :=
                 Before_Line.Why.Observed_Position;
               After_Pos   : constant ALedger.Envelope_Position.Position :=
                 After_Line.Why.Observed_Position;
            begin
               Output.Lines.Append
                 ((Env_Id               => After_Line.Env_Id,
                   Entitlement          =>
                     Difference (After_Ev.Entitlement, Before_Ev.Entitlement),
                   Consumption_Charges  =>
                     Difference
                       (After_Ev.Consumption_Charges,
                        Before_Ev.Consumption_Charges),
                   Consumption_Refunds  =>
                     Difference
                       (After_Ev.Consumption_Refunds,
                        Before_Ev.Consumption_Refunds),
                   Net_Consumption      =>
                     Difference
                       (After_Ev.Net_Consumption, Before_Ev.Net_Consumption),
                   Fulfillment_Applied  =>
                     Difference
                       (After_Ev.Fulfillment_Applied,
                        Before_Ev.Fulfillment_Applied),
                   Fulfillment_Reversed =>
                     Difference
                       (After_Ev.Fulfillment_Reversed,
                        Before_Ev.Fulfillment_Reversed),
                   Net_Fulfillment      =>
                     Difference
                       (After_Ev.Net_Fulfillment, Before_Ev.Net_Fulfillment),
                   Remaining            =>
                     Difference (After_Pos.Remaining, Before_Pos.Remaining),
                   Plan_Commitment      =>
                     Difference
                       (After_Ev.Plan_Commitment, Before_Ev.Plan_Commitment),
                   Headroom             =>
                     Difference (After_Pos.Headroom, Before_Pos.Headroom)));
            end;
         end loop;
      end if;

      Result := Output;
      Diag := (Status => Success, Mismatch_Index => 0);
      return True;
   end Observe_Change;

end ALedger.Household_Envelope_Change;
