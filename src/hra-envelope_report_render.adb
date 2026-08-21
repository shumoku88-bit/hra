with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA.Backing_Policy;
with HRA.Cycle_Observation;
with HRA.Dates;
with HRA.Envelope;
with HRA.Envelope_Consumption;
with HRA.Envelope_Fulfillment;
with HRA.Household_Envelope_Cycle_Comparison;
with HRA.Money; use HRA.Money;

package body HRA.Envelope_Report_Render is

   function Render_Amount
     (Q : Quantity; Commodity_Code : String) return String
   is
   begin
      if Q < Zero_Quantity then
         return "(" & Render_Quantity (-Q) & " " & Commodity_Code & ")";
      elsif Is_Zero (Q) then
         return "0";
      else
         return Render_Quantity (Q) & " " & Commodity_Code;
      end if;
   end Render_Amount;

   function Render_Balance (Value : Balance) return String is
      Values : constant Balance_Entry_Array := Entries (Value);
      Result : Unbounded_String;
   begin
      if Values'Length = 0 then
         return "0";
      end if;

      for Index in Values'Range loop
         if Index > Values'First then
            Append (Result, ", ");
         end if;
         Append
           (Result,
            Render_Amount
              (Values (Index).Val, Code (Values (Index).Comm)));
      end loop;
      return To_String (Result);
   end Render_Balance;

   procedure Append_Window
     (Buf    : in out Unbounded_String;
      Label  : String;
      Window : HRA.Cycle_Observation.Cycle_Window)
   is
   begin
      Append
        (Buf,
         Label & ": [" &
         HRA.Dates.Image (HRA.Cycle_Observation.Start_Date (Window)) & ", " &
         HRA.Dates.Image (HRA.Cycle_Observation.End_Exclusive (Window)) &
         ")" & ASCII.LF);
   end Append_Window;

   function Render
     (Observation :
        HRA.Household_Report_Observation.Envelope_Report_Observation)
      return String
   is
      Buf : Unbounded_String;
   begin
      Append (Buf, "== Envelope & Backing ==" & ASCII.LF);
      Append
        (Buf,
         "Observed through: " &
         HRA.Dates.Image (Observation.Observed_Through) & ASCII.LF);
      Append_Window (Buf, "Current cycle", Observation.Current_Cycle);
      Append (Buf, ASCII.LF);

      Append
        (Buf,
         "Envelope | Entitlement | Consumption | Refunds | Fulfillment | Remaining | Plan reserve | Headroom" &
         ASCII.LF);
      Append
        (Buf,
         "------------------------------------------------------------------------------------------------" &
         ASCII.LF);

      for Line of Observation.Lines loop
         Append (Buf, HRA.Envelope.Image (Line.Env_Id) & " | ");
         Append (Buf, Render_Balance (Line.Entitlement) & " | ");
         Append (Buf, Render_Balance (Line.Consumption_Charges) & " | ");
         Append (Buf, Render_Balance (Line.Consumption_Refunds) & " | ");
         Append (Buf, Render_Balance (Line.Net_Fulfillment) & " | ");
         Append (Buf, Render_Balance (Line.Remaining) & " | ");
         Append (Buf, Render_Balance (Line.Plan_Commitment) & " | ");
         Append (Buf, Render_Balance (Line.Headroom) & ASCII.LF);
      end loop;

      if not Observation.Unmanaged_Consumption.Is_Empty
        or else not Observation.Unrouted_Consumption.Is_Empty
      then
         Append (Buf, ASCII.LF & "Expense activity outside an envelope" & ASCII.LF);
         Append (Buf, "Account | Movement" & ASCII.LF);
         Append (Buf, "------------------" & ASCII.LF);

         for Line of Observation.Unmanaged_Consumption loop
            Append
              (Buf,
               To_String (Line.Account_Name) & " | " &
               Render_Balance (Line.Net) & ASCII.LF);
         end loop;

         for Line of Observation.Unrouted_Consumption loop
            Append
              (Buf,
               To_String (Line.Account_Name) & " (unrouted) | " &
               Render_Balance (Line.Net) & ASCII.LF);
         end loop;
      end if;

      if not Observation.Unmanaged_Commitment.Is_Empty
        or else not Observation.Unrouted_Commitment.Is_Empty
      then
         Append (Buf, ASCII.LF & "Plan commitments outside an envelope" & ASCII.LF);
         Append (Buf, "Account | Commitment" & ASCII.LF);
         Append (Buf, "--------------------" & ASCII.LF);

         for Line of Observation.Unmanaged_Commitment loop
            Append
              (Buf,
               To_String (Line.Account_Name) & " | " &
               Render_Balance (Line.Commitment) & ASCII.LF);
         end loop;

         for Line of Observation.Unrouted_Commitment loop
            Append
              (Buf,
               To_String (Line.Account_Name) & " (unrouted) | " &
               Render_Balance (Line.Commitment) & ASCII.LF);
         end loop;
      end if;

      Append (Buf, ASCII.LF & "Backing evidence" & ASCII.LF);
      Append (Buf, "Coordinate | Amount" & ASCII.LF);
      Append (Buf, "-------------------" & ASCII.LF);

      for Line of Observation.Backing_Lines loop
         declare
            Pool : constant String := To_String (Line.Pool_Id);
         begin
            Append
              (Buf,
               "Funding balance (" & Pool & ") | " &
               Render_Balance (Line.Funding_Balance) & ASCII.LF);
            Append
              (Buf,
               "Funding commitment (" & Pool & ") | " &
               Render_Balance (Line.Funding_Commitment) & ASCII.LF);
            Append
              (Buf,
               "Available funding (" & Pool & ") | " &
               Render_Balance (Line.Available_Funding) & ASCII.LF);
            Append
              (Buf,
               "Positive backing required (" & Pool & ") | " &
               Render_Balance (Line.Gross_Envelope_Required) & ASCII.LF);
            Append
              (Buf,
               "Available headroom required (" & Pool & ") | " &
               Render_Balance (Line.Available_Envelope_Required) & ASCII.LF);
            Append
              (Buf,
               "Gross backing surplus (" & Pool & ") | " &
               Render_Balance (Line.Gross_Surplus) & ASCII.LF);
            Append
              (Buf,
               "Available backing surplus (" & Pool & ") | " &
               Render_Balance (Line.Available_Surplus) & ASCII.LF);
         end;
      end loop;

      Append
        (Buf,
         "Signed envelope total | " &
         Render_Balance (Observation.Signed_Envelope_Total) & ASCII.LF);
      Append
        (Buf,
         "Unallocated | " & Render_Balance (Observation.Unallocated) &
         ASCII.LF);
      Append
        (Buf,
         "Total funding assets | " &
         Render_Balance (Observation.Total_Funding_Assets) & ASCII.LF);
      Append
        (Buf,
         "Status: " &
         (case Observation.Backing_Status is
             when HRA.Backing_Policy.Fully_Backed => "fully_backed",
             when HRA.Backing_Policy.Under_Backed => "under_backed") &
         ASCII.LF);

      return To_String (Buf);
   end Render;

   function Render
     (Observation : HRA.Household_Envelope_Change.Change_Observation)
      return String
   is
      Buf : Unbounded_String;
   begin
      Append (Buf, "== Envelope Change ==" & ASCII.LF);
      Append_Window (Buf, "Cycle", Observation.Window);
      Append
        (Buf,
         "From: " & HRA.Dates.Image (Observation.From_Date) & ASCII.LF &
         "Through: " & HRA.Dates.Image (Observation.Through_Date) &
         ASCII.LF & ASCII.LF);

      if Observation.Lines.Is_Empty then
         Append (Buf, "(no Envelope coordinates)" & ASCII.LF);
         return To_String (Buf);
      end if;

      for Line of Observation.Lines loop
         Append
           (Buf,
            "Envelope: " & HRA.Envelope.Image (Line.Env_Id) & ASCII.LF &
            "  Entitlement change       : " &
            Render_Balance (Line.Entitlement) & ASCII.LF &
            "  Consumption charges change: " &
            Render_Balance (Line.Consumption_Charges) & ASCII.LF &
            "  Consumption refunds change: " &
            Render_Balance (Line.Consumption_Refunds) & ASCII.LF &
            "  Net consumption change   : " &
            Render_Balance (Line.Net_Consumption) & ASCII.LF &
            "  Fulfillment applied change: " &
            Render_Balance (Line.Fulfillment_Applied) & ASCII.LF &
            "  Fulfillment reversed change: " &
            Render_Balance (Line.Fulfillment_Reversed) & ASCII.LF &
            "  Net fulfillment change   : " &
            Render_Balance (Line.Net_Fulfillment) & ASCII.LF &
            "  Remaining change         : " &
            Render_Balance (Line.Remaining) & ASCII.LF &
            "  Plan commitment change   : " &
            Render_Balance (Line.Plan_Commitment) & ASCII.LF &
            "  Headroom change          : " &
            Render_Balance (Line.Headroom) & ASCII.LF & ASCII.LF);
      end loop;

      return To_String (Buf);
   end Render;

   function Render
     (Observation :
        HRA.Household_Envelope_Cycle_Comparison.Comparison_Observation)
      return String
   is
      package Comparison renames HRA.Household_Envelope_Cycle_Comparison;
      Buf : Unbounded_String;
   begin
      Append (Buf, "== Envelope Aligned Previous Cycle ==" & ASCII.LF);
      Append_Window (Buf, "Current cycle", Observation.Current_Window);
      Append_Window (Buf, "Baseline cycle", Observation.Baseline_Window);
      Append
        (Buf,
         "Current through: " & HRA.Dates.Image (Observation.Current_Through) &
         ASCII.LF &
         "Baseline through: " & HRA.Dates.Image (Observation.Baseline_Through) &
         ASCII.LF & ASCII.LF);

      if Observation.Lines.Is_Empty then
         Append (Buf, "(no Envelope coordinates)" & ASCII.LF);
         return To_String (Buf);
      end if;

      for Line of Observation.Lines loop
         Append
           (Buf,
            "Envelope: " & HRA.Envelope.Image (Line.Env_Id) & ASCII.LF &
            "  Consumption net          : " &
            Render_Balance
              (HRA.Envelope_Consumption.Net_Consumption
                 (Line.Current_Consumption)) &
            " current | " &
            Render_Balance
              (HRA.Envelope_Consumption.Net_Consumption
                 (Line.Baseline_Consumption)) &
            " baseline | " &
            Render_Balance (Comparison.Consumption_Net_Difference (Line)) &
            " difference" & ASCII.LF &
            "  Fulfillment net          : " &
            Render_Balance
              (HRA.Envelope_Fulfillment.Net_Fulfillment
                 (Line.Current_Fulfillment)) &
            " current | " &
            Render_Balance
              (HRA.Envelope_Fulfillment.Net_Fulfillment
                 (Line.Baseline_Fulfillment)) &
            " baseline | " &
            Render_Balance (Comparison.Fulfillment_Net_Difference (Line)) &
            " difference" & ASCII.LF &
            "  Entitlement              : " &
            Render_Balance (Line.Current_Entitlement) & " current | " &
            Render_Balance (Line.Baseline_Entitlement) & " baseline | " &
            Render_Balance (Comparison.Entitlement_Difference (Line)) &
            " difference" & ASCII.LF &
            "  Remaining                : " &
            Render_Balance (Line.Current_Remaining) & " current | " &
            Render_Balance (Line.Baseline_Remaining) & " baseline | " &
            Render_Balance (Comparison.Remaining_Difference (Line)) &
            " difference" & ASCII.LF &
            "  Plan commitment          : " &
            Render_Balance (Line.Current_Commitment) & " current | " &
            Render_Balance (Line.Baseline_Commitment) & " baseline | " &
            Render_Balance (Comparison.Commitment_Difference (Line)) &
            " difference" & ASCII.LF &
            "  Headroom                 : " &
            Render_Balance (Line.Current_Headroom) & " current | " &
            Render_Balance (Line.Baseline_Headroom) & " baseline | " &
            Render_Balance (Comparison.Headroom_Difference (Line)) &
            " difference" & ASCII.LF & ASCII.LF);
      end loop;

      return To_String (Buf);
   end Render;

end HRA.Envelope_Report_Render;
