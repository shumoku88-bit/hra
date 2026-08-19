with Ada.Containers;
with HRA.Cycle_Observation;
with HRA.Dates;
with HRA.Envelope;
with HRA.Envelope_Position;
with HRA.Household_Envelope_Explanation;
with HRA.Money; use HRA.Money;

package body HRA.Household_Envelope_Change is

   use type Ada.Containers.Count_Type;
   use type HRA.Dates.Date;
   use type HRA.Envelope.Envelope_Id;

   package Explanation renames HRA.Household_Envelope_Explanation;

   function Resolve_Baseline
     (Window   : HRA.Cycle_Observation.Cycle_Window;
      Through  : HRA.Dates.Date;
      Previous : Previous_Observation_Context;
      Request  : Baseline_Request;
      Result   : out Resolved_Change_Baseline;
      Diag     : out Baseline_Diagnostic) return Boolean
   is
      Output : Resolved_Change_Baseline :=
        (Request => Request,
         Day     => Through);
   begin
      if not HRA.Cycle_Observation.Contains (Window, Through) then
         Result := Output;
         Diag :=
           (Status           => Through_Outside_Window,
            Rejected_Through => Through);
         return False;
      end if;

      case Request.Kind is
         when Previous_Observation =>
            case Previous.Kind is
               when No_Previous_Observation =>
                  Result := Output;
                  Diag := (Status => Previous_Observation_Unavailable);
                  return False;

               when Previous_Observation_Available =>
                  declare
                     Candidate : constant HRA.Dates.Date :=
                       Previous.Observed_Through;
                  begin
                     if not HRA.Cycle_Observation.Contains
                       (Window, Candidate)
                     then
                        Result := Output;
                        Diag :=
                          (Status          => Baseline_Day_Outside_Window,
                           Outside_Request => Request,
                           Outside_Day     => Candidate);
                        return False;
                     elsif not (Candidate < Through) then
                        Result := Output;
                        Diag :=
                          (Status             => Previous_Observation_Not_Before,
                           Previous_Day_Value => Candidate,
                           Current_Through    => Through);
                        return False;
                     end if;

                     Output.Day := Candidate;
                  end;
            end case;

         when Previous_Day =>
            if not HRA.Dates.Has_Previous (Through) then
               Result := Output;
               Diag :=
                 (Status           => Previous_Day_Unavailable,
                  Boundary_Through => Through);
               return False;
            end if;

            declare
               Candidate : constant HRA.Dates.Date :=
                 HRA.Dates.Previous (Through);
            begin
               if not HRA.Cycle_Observation.Contains (Window, Candidate) then
                  Result := Output;
                  Diag :=
                    (Status          => Baseline_Day_Outside_Window,
                     Outside_Request => Request,
                     Outside_Day     => Candidate);
                  return False;
               end if;

               Output.Day := Candidate;
            end;

         when Cycle_Start =>
            Output.Day := HRA.Cycle_Observation.Start_Date (Window);

         when Explicit_Day =>
            declare
               Candidate : constant HRA.Dates.Date := Request.Requested_Day;
            begin
               if not HRA.Cycle_Observation.Contains (Window, Candidate) then
                  Result := Output;
                  Diag :=
                    (Status          => Baseline_Day_Outside_Window,
                     Outside_Request => Request,
                     Outside_Day     => Candidate);
                  return False;
               elsif Candidate > Through then
                  Result := Output;
                  Diag :=
                    (Status          => Baseline_Day_After_Observation,
                     Future_Request  => Request,
                     Future_Day      => Candidate,
                     Observation_Day => Through);
                  return False;
               end if;

               Output.Day := Candidate;
            end;
      end case;

      Result := Output;
      Diag := (Status => Success);
      return True;
   end Resolve_Baseline;

   function Resolved_Request
     (Baseline : Resolved_Change_Baseline) return Baseline_Request
   is
   begin
      return Baseline.Request;
   end Resolved_Request;

   function Resolved_Day
     (Baseline : Resolved_Change_Baseline) return HRA.Dates.Date
   is
   begin
      return Baseline.Day;
   end Resolved_Day;

   function Same_Window
     (Left, Right : HRA.Cycle_Observation.Cycle_Window) return Boolean
   is
   begin
      return
        HRA.Cycle_Observation.Start_Date (Left) =
          HRA.Cycle_Observation.Start_Date (Right)
        and then
        HRA.Cycle_Observation.End_Exclusive (Left) =
          HRA.Cycle_Observation.End_Exclusive (Right);
   end Same_Window;

   function Difference (Later, Earlier : Balance) return Balance is
   begin
      return Subtract_Balance (Later, Earlier);
   end Difference;

   function Observe_Change
     (Earlier : Explanation.Explanation_Observation;
      Later   : Explanation.Explanation_Observation;
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
               Before_Line : constant Explanation.Explanation_Line :=
                 Earlier.Lines.Element (I);
               After_Line  : constant Explanation.Explanation_Line :=
                 Later.Lines.Element (I);
               Before_Ev   : constant HRA.Envelope_Position.Arithmetic_Evidence :=
                 Before_Line.Why.Evidence;
               After_Ev    : constant HRA.Envelope_Position.Arithmetic_Evidence :=
                 After_Line.Why.Evidence;
               Before_Pos  : constant HRA.Envelope_Position.Position :=
                 Before_Line.Why.Observed_Position;
               After_Pos   : constant HRA.Envelope_Position.Position :=
                 After_Line.Why.Observed_Position;
            begin
               Output.Lines.Append
                 (Change_Line'
                    (Env_Id               => After_Line.Env_Id,
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

end HRA.Household_Envelope_Change;
