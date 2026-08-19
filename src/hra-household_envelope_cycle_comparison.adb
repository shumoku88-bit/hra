with HRA.Household_Envelope_Explanation;
with HRA.Household_Envelope_Observation;

package body HRA.Household_Envelope_Cycle_Comparison is

   use type HRA.Dates.Date;
   use type HRA.Envelope.Envelope_Id;

   function Consumption_Difference
     (Later   : HRA.Envelope_Consumption.Consumption_Amounts;
      Earlier : HRA.Envelope_Consumption.Consumption_Amounts)
      return HRA.Envelope_Consumption.Consumption_Amounts
   is
   begin
      return
        (Charges => Subtract_Balance (Later.Charges, Earlier.Charges),
         Refunds => Subtract_Balance (Later.Refunds, Earlier.Refunds));
   end Consumption_Difference;

   function Fulfillment_Difference
     (Later   : HRA.Envelope_Fulfillment.Fulfillment_Amounts;
      Earlier : HRA.Envelope_Fulfillment.Fulfillment_Amounts)
      return HRA.Envelope_Fulfillment.Fulfillment_Amounts
   is
   begin
      return
        (Applied  => Subtract_Balance (Later.Applied, Earlier.Applied),
         Reversed => Subtract_Balance (Later.Reversed, Earlier.Reversed));
   end Fulfillment_Difference;

   function Aligned_Day
     (Current_Through : HRA.Dates.Date;
      Current_Window  : HRA.Cycle_Observation.Cycle_Window;
      Baseline_Window : HRA.Cycle_Observation.Cycle_Window)
      return HRA.Dates.Date
   is
      Current_Cursor  : HRA.Dates.Date :=
        HRA.Cycle_Observation.Start_Date (Current_Window);
      Baseline_Cursor : HRA.Dates.Date :=
        HRA.Cycle_Observation.Start_Date (Baseline_Window);
   begin
      while Current_Cursor < Current_Through loop
         Current_Cursor := HRA.Dates.Next (Current_Cursor);
         Baseline_Cursor := HRA.Dates.Next (Baseline_Cursor);
      end loop;
      return Baseline_Cursor;
   end Aligned_Day;

   procedure Set_Diagnostic
     (Diag    : out Observe_Diagnostic;
      Status  : Observe_Status;
      Side    : Comparison_Side := Current_Cycle;
      Message : String := "";
      Index   : Natural := 0)
   is
   begin
      Diag :=
        (Status         => Status,
         Side           => Side,
         Mismatch_Index => Index,
         Message        => To_Unbounded_String (Message));
   end Set_Diagnostic;

   function Observe_Aligned
     (Current_Through : HRA.Dates.Date;
      Current_Window  : HRA.Cycle_Observation.Cycle_Window;
      Baseline_Window : HRA.Cycle_Observation.Cycle_Window;
      State           : HRA.Household.Household_State;
      Result          : out Comparison_Observation;
      Diag            : out Observe_Diagnostic) return Boolean
   is
      Baseline_Through : HRA.Dates.Date :=
        HRA.Cycle_Observation.Start_Date (Baseline_Window);
      Current_Obs  : HRA.Household_Envelope_Observation.Observation;
      Baseline_Obs : HRA.Household_Envelope_Observation.Observation;
      Current_Why  : HRA.Household_Envelope_Explanation.Explanation_Observation;
      Baseline_Why : HRA.Household_Envelope_Explanation.Explanation_Observation;
      Why_Diag     : HRA.Household_Envelope_Explanation.Explain_Diagnostic;
      Error_Msg    : Unbounded_String;

      Current_Consumption_Through : HRA.Envelope_Consumption.Envelope_Consumption;
      Current_Consumption_Before  : HRA.Envelope_Consumption.Envelope_Consumption :=
        HRA.Envelope_Consumption.Empty_Consumption;
      Baseline_Consumption_Through : HRA.Envelope_Consumption.Envelope_Consumption;
      Baseline_Consumption_Before  : HRA.Envelope_Consumption.Envelope_Consumption :=
        HRA.Envelope_Consumption.Empty_Consumption;

      Current_Fulfillment_Through : HRA.Envelope_Fulfillment.Envelope_Fulfillment :=
        HRA.Envelope_Fulfillment.Empty_Fulfillment (Current_Through);
      Current_Fulfillment_Before : HRA.Envelope_Fulfillment.Envelope_Fulfillment :=
        HRA.Envelope_Fulfillment.Empty_Fulfillment (Current_Through);
      Baseline_Fulfillment_Through : HRA.Envelope_Fulfillment.Envelope_Fulfillment :=
        HRA.Envelope_Fulfillment.Empty_Fulfillment (Baseline_Through);
      Baseline_Fulfillment_Before : HRA.Envelope_Fulfillment.Envelope_Fulfillment :=
        HRA.Envelope_Fulfillment.Empty_Fulfillment (Baseline_Through);
      Fulfillment_Diag : HRA.Envelope_Fulfillment.Observe_Diagnostic;

      Output : Comparison_Observation;

      function Fulfillment_Error
        (D : HRA.Envelope_Fulfillment.Observe_Diagnostic) return String
      is
      begin
         return HRA.Envelope_Fulfillment.Observe_Status'Image (D.Status) &
           (if Length (D.Message) > 0 then ": " & To_String (D.Message) else "");
      end Fulfillment_Error;

      function Explanation_Error
        (D : HRA.Household_Envelope_Explanation.Explain_Diagnostic) return String
      is
      begin
         return HRA.Household_Envelope_Explanation.Explain_Status'Image (D.Status);
      end Explanation_Error;

   begin
      Set_Diagnostic (Diag, Success);

      if HRA.Cycle_Observation.Start_Date (Baseline_Window) >=
        HRA.Cycle_Observation.Start_Date (Current_Window)
      then
         Set_Diagnostic
           (Diag,
            Period_Order_Invalid,
            Baseline_Cycle,
            "baseline cycle must start before current cycle");
         return False;
      end if;

      if not HRA.Cycle_Observation.Contains (Current_Window, Current_Through) then
         Set_Diagnostic
           (Diag,
            Current_Observation_Outside_Window,
            Current_Cycle,
            HRA.Dates.Image (Current_Through));
         return False;
      end if;

      Baseline_Through :=
        Aligned_Day (Current_Through, Current_Window, Baseline_Window);

      if not HRA.Cycle_Observation.Contains
        (Baseline_Window, Baseline_Through)
      then
         Set_Diagnostic
           (Diag,
            Aligned_Baseline_Outside_Window,
            Baseline_Cycle,
            HRA.Dates.Image (Baseline_Through));
         return False;
      end if;

      if not HRA.Household_Envelope_Observation.Observe_In_Window
        (Current_Through,
         Current_Window,
         State,
         Current_Obs,
         Error_Msg)
      then
         Set_Diagnostic
           (Diag,
            Current_Observation_Unavailable,
            Current_Cycle,
            To_String (Error_Msg));
         return False;
      end if;

      if not HRA.Household_Envelope_Observation.Observe_In_Window
        (Baseline_Through,
         Baseline_Window,
         State,
         Baseline_Obs,
         Error_Msg)
      then
         Set_Diagnostic
           (Diag,
            Baseline_Observation_Unavailable,
            Baseline_Cycle,
            To_String (Error_Msg));
         return False;
      end if;

      if not HRA.Household_Envelope_Explanation.Capture
        (State.Budget_Policy,
         State.Envelope_Registry,
         Current_Window,
         Current_Through,
         Current_Obs.Envelope_Positions,
         Current_Why,
         Why_Diag)
      then
         Set_Diagnostic
           (Diag,
            Current_Explanation_Unavailable,
            Current_Cycle,
            Explanation_Error (Why_Diag));
         return False;
      end if;

      if not HRA.Household_Envelope_Explanation.Capture
        (State.Budget_Policy,
         State.Envelope_Registry,
         Baseline_Window,
         Baseline_Through,
         Baseline_Obs.Envelope_Positions,
         Baseline_Why,
         Why_Diag)
      then
         Set_Diagnostic
           (Diag,
            Baseline_Explanation_Unavailable,
            Baseline_Cycle,
            Explanation_Error (Why_Diag));
         return False;
      end if;

      Current_Consumption_Through :=
        HRA.Envelope_Consumption.Observe_Consumption
          (State.Actual_Ledger, State.Routing_History, Current_Through);
      Baseline_Consumption_Through :=
        HRA.Envelope_Consumption.Observe_Consumption
          (State.Actual_Ledger, State.Routing_History, Baseline_Through);

      if HRA.Dates.Has_Previous
        (HRA.Cycle_Observation.Start_Date (Current_Window))
      then
         Current_Consumption_Before :=
           HRA.Envelope_Consumption.Observe_Consumption
             (State.Actual_Ledger,
              State.Routing_History,
              HRA.Dates.Previous
                (HRA.Cycle_Observation.Start_Date (Current_Window)));
      end if;

      if HRA.Dates.Has_Previous
        (HRA.Cycle_Observation.Start_Date (Baseline_Window))
      then
         Baseline_Consumption_Before :=
           HRA.Envelope_Consumption.Observe_Consumption
             (State.Actual_Ledger,
              State.Routing_History,
              HRA.Dates.Previous
                (HRA.Cycle_Observation.Start_Date (Baseline_Window)));
      end if;

      if not HRA.Envelope_Fulfillment.Observe
        (Current_Obs.Completed_Plans,
         State.Actual_Ledger,
         State.Registry,
         State.Fulfillment_History,
         Current_Through,
         Current_Fulfillment_Through,
         Fulfillment_Diag)
      then
         Set_Diagnostic
           (Diag,
            Current_Fulfillment_Unavailable,
            Current_Cycle,
            Fulfillment_Error (Fulfillment_Diag));
         return False;
      end if;

      if HRA.Dates.Has_Previous
        (HRA.Cycle_Observation.Start_Date (Current_Window))
        and then not HRA.Envelope_Fulfillment.Observe
          (Current_Obs.Completed_Plans,
           State.Actual_Ledger,
           State.Registry,
           State.Fulfillment_History,
           HRA.Dates.Previous
             (HRA.Cycle_Observation.Start_Date (Current_Window)),
           Current_Fulfillment_Before,
           Fulfillment_Diag)
      then
         Set_Diagnostic
           (Diag,
            Current_Fulfillment_Unavailable,
            Current_Cycle,
            Fulfillment_Error (Fulfillment_Diag));
         return False;
      end if;

      if not HRA.Envelope_Fulfillment.Observe
        (Baseline_Obs.Completed_Plans,
         State.Actual_Ledger,
         State.Registry,
         State.Fulfillment_History,
         Baseline_Through,
         Baseline_Fulfillment_Through,
         Fulfillment_Diag)
      then
         Set_Diagnostic
           (Diag,
            Baseline_Fulfillment_Unavailable,
            Baseline_Cycle,
            Fulfillment_Error (Fulfillment_Diag));
         return False;
      end if;

      if HRA.Dates.Has_Previous
        (HRA.Cycle_Observation.Start_Date (Baseline_Window))
        and then not HRA.Envelope_Fulfillment.Observe
          (Baseline_Obs.Completed_Plans,
           State.Actual_Ledger,
           State.Registry,
           State.Fulfillment_History,
           HRA.Dates.Previous
             (HRA.Cycle_Observation.Start_Date (Baseline_Window)),
           Baseline_Fulfillment_Before,
           Fulfillment_Diag)
      then
         Set_Diagnostic
           (Diag,
            Baseline_Fulfillment_Unavailable,
            Baseline_Cycle,
            Fulfillment_Error (Fulfillment_Diag));
         return False;
      end if;

      Output :=
        (Current_Window   => Current_Window,
         Baseline_Window  => Baseline_Window,
         Current_Through  => Current_Through,
         Baseline_Through => Baseline_Through,
         Lines            => Comparison_Line_Vectors.Empty_Vector);

      if Current_Why.Lines.Length /= Baseline_Why.Lines.Length then
         Result := Output;
         Set_Diagnostic
           (Diag,
            Envelope_Order_Mismatch,
            Baseline_Cycle,
            "current and baseline Envelope counts differ");
         return False;
      end if;

      for I in 1 .. Natural (Current_Why.Lines.Length) loop
         declare
            Current_Line : constant
              HRA.Household_Envelope_Explanation.Explanation_Line :=
                Current_Why.Lines.Element (I);
            Baseline_Line : constant
              HRA.Household_Envelope_Explanation.Explanation_Line :=
                Baseline_Why.Lines.Element (I);
            Env : constant HRA.Envelope.Envelope_Id := Current_Line.Env_Id;
         begin
            if Current_Line.Env_Id /= Baseline_Line.Env_Id then
               Result := Output;
               Set_Diagnostic
                 (Diag,
                  Envelope_Order_Mismatch,
                  Baseline_Cycle,
                  "Envelope identity/order differs at comparison coordinate",
                  I);
               return False;
            end if;

            Output.Lines.Append
              (Comparison_Line'
                 (Env_Id => Env,
                  Current_Consumption => Consumption_Difference
                    (HRA.Envelope_Consumption.Consumption_For
                       (Current_Consumption_Through, Env),
                     HRA.Envelope_Consumption.Consumption_For
                       (Current_Consumption_Before, Env)),
                  Baseline_Consumption => Consumption_Difference
                    (HRA.Envelope_Consumption.Consumption_For
                       (Baseline_Consumption_Through, Env),
                     HRA.Envelope_Consumption.Consumption_For
                       (Baseline_Consumption_Before, Env)),
                  Current_Fulfillment => Fulfillment_Difference
                    (HRA.Envelope_Fulfillment.Fulfillment_For
                       (Current_Fulfillment_Through, Env),
                     HRA.Envelope_Fulfillment.Fulfillment_For
                       (Current_Fulfillment_Before, Env)),
                  Baseline_Fulfillment => Fulfillment_Difference
                    (HRA.Envelope_Fulfillment.Fulfillment_For
                       (Baseline_Fulfillment_Through, Env),
                     HRA.Envelope_Fulfillment.Fulfillment_For
                       (Baseline_Fulfillment_Before, Env)),
                  Current_Entitlement => Current_Line.Why.Evidence.Entitlement,
                  Baseline_Entitlement => Baseline_Line.Why.Evidence.Entitlement,
                  Current_Remaining => Current_Line.Why.Observed_Position.Remaining,
                  Baseline_Remaining => Baseline_Line.Why.Observed_Position.Remaining,
                  Current_Commitment => Current_Line.Why.Evidence.Plan_Commitment,
                  Baseline_Commitment => Baseline_Line.Why.Evidence.Plan_Commitment,
                  Current_Headroom => Current_Line.Why.Observed_Position.Headroom,
                  Baseline_Headroom => Baseline_Line.Why.Observed_Position.Headroom));
         end;
      end loop;

      Result := Output;
      Set_Diagnostic (Diag, Success);
      return True;
   end Observe_Aligned;

   function Consumption_Net_Difference
     (Line : Comparison_Line) return Balance
   is
   begin
      return Subtract_Balance
        (HRA.Envelope_Consumption.Net_Consumption (Line.Current_Consumption),
         HRA.Envelope_Consumption.Net_Consumption (Line.Baseline_Consumption));
   end Consumption_Net_Difference;

   function Fulfillment_Net_Difference
     (Line : Comparison_Line) return Balance
   is
   begin
      return Subtract_Balance
        (HRA.Envelope_Fulfillment.Net_Fulfillment (Line.Current_Fulfillment),
         HRA.Envelope_Fulfillment.Net_Fulfillment (Line.Baseline_Fulfillment));
   end Fulfillment_Net_Difference;

   function Entitlement_Difference
     (Line : Comparison_Line) return Balance
   is
   begin
      return Subtract_Balance
        (Line.Current_Entitlement, Line.Baseline_Entitlement);
   end Entitlement_Difference;

   function Remaining_Difference
     (Line : Comparison_Line) return Balance
   is
   begin
      return Subtract_Balance (Line.Current_Remaining, Line.Baseline_Remaining);
   end Remaining_Difference;

   function Commitment_Difference
     (Line : Comparison_Line) return Balance
   is
   begin
      return Subtract_Balance
        (Line.Current_Commitment, Line.Baseline_Commitment);
   end Commitment_Difference;

   function Headroom_Difference
     (Line : Comparison_Line) return Balance
   is
   begin
      return Subtract_Balance (Line.Current_Headroom, Line.Baseline_Headroom);
   end Headroom_Difference;

end HRA.Household_Envelope_Cycle_Comparison;
