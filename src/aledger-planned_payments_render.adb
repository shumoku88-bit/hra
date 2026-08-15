with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with ALedger.Money;
with ALedger.Account;
with ALedger.Plan;

package body ALedger.Planned_Payments_Render is

   function Timing_Image
     (Value : ALedger.Planned_Payments.Temporal_Status) return String
   is
   begin
      case Value is
         when ALedger.Planned_Payments.Overdue   => return "OVERDUE";
         when ALedger.Planned_Payments.Due_Today => return "DUE";
         when ALedger.Planned_Payments.Upcoming  => return "UPCOMING";
      end case;
   end Timing_Image;

   function Render
     (Value : ALedger.Planned_Payments.Observation) return String
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
            To_String (Payment.Due_Date) & "  " &
            Timing_Image (Payment.Timing) & "  " &
            ALedger.Money.Render_Quantity (Payment.Amt.Val) & " " &
            ALedger.Money.Code (Payment.Amt.Comm) & ASCII.LF);
         Append
           (Result,
            "  " & To_String (Payment.Memo) & ASCII.LF &
            "  plan-id: " & ALedger.Plan.Text (Payment.ID) & ASCII.LF &
            "  from: " & ALedger.Account.Name (Payment.Source) & ASCII.LF &
            "  to:   " & ALedger.Account.Name (Payment.Destination) & ASCII.LF);
      end loop;

      return To_String (Result);
   end Render;

end ALedger.Planned_Payments_Render;
