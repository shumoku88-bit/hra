with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA.Backing_Policy;
with HRA.Cycle_Observation;
with HRA.Dates;
with HRA.Envelope;
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
      Append
        (Buf,
         "Current cycle: [" &
         HRA.Dates.Image
           (HRA.Cycle_Observation.Start_Date (Observation.Current_Cycle)) & ", " &
         HRA.Dates.Image
           (HRA.Cycle_Observation.End_Exclusive (Observation.Current_Cycle)) &
         ")" & ASCII.LF & ASCII.LF);

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

end HRA.Envelope_Report_Render;
