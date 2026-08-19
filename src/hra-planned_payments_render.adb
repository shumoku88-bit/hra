with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA.Dates;
with HRA.Money;
with HRA.Account;
with HRA.Plan;

package body HRA.Planned_Payments_Render is

   function Timing_Image
     (Value : HRA.Planned_Payments.Temporal_Status) return String
   is
   begin
      case Value is
         when HRA.Planned_Payments.Overdue   => return "OVERDUE";
         when HRA.Planned_Payments.Due_Today => return "DUE";
         when HRA.Planned_Payments.Upcoming  => return "UPCOMING";
      end case;
   end Timing_Image;

   function Render
     (Value : HRA.Planned_Payments.Observation) return String
   is
      Result : Unbounded_String :=
        To_Unbounded_String
          ("Planned Payments" & ASCII.LF &
           "----------------" & ASCII.LF);
   begin
      if Value.Payments.Is_Empty then
         Append (Result, "  (none)" & ASCII.LF);
         return To_String (Result);
      end if;

      for Payment of Value.Payments loop
         Append
           (Result,
            HRA.Dates.Image (Payment.Due_Date) & "  " &
            Timing_Image (Payment.Timing) & "  " &
            HRA.Money.Render_Quantity (Payment.Amt.Val) & " " &
            HRA.Money.Code (Payment.Amt.Comm) & ASCII.LF);
         Append
           (Result,
            "  " & To_String (Payment.Memo) & ASCII.LF &
            "  plan-id: " & HRA.Plan.Text (Payment.ID) & ASCII.LF &
            "  from: " & HRA.Account.Name (Payment.Source) & ASCII.LF &
            "  to:   " & HRA.Account.Name (Payment.Destination) & ASCII.LF);
      end loop;

      return To_String (Result);
   end Render;

end HRA.Planned_Payments_Render;
