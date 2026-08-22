with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA.Account;
with HRA.Cycle_Accounts_Observation;
with HRA.Cycle_Observation;
with HRA.Dates;
with HRA.Money; use HRA.Money;
with HRA.Terminal_Layout;

package body HRA.Cycle_Accounts_Render is

   function Render_Amount_Or_Paren
     (Q : Quantity; Comm_Code : String) return String
   is
   begin
      if Is_Zero (Q) then
         return "0";
      elsif Q < Zero_Quantity then
         return "(" & Render_Quantity (-Q) & " " & Comm_Code & ")";
      else
         return Render_Quantity (Q) & " " & Comm_Code;
      end if;
   end Render_Amount_Or_Paren;

   function Render_Balance (B : Balance) return String is
      Ents : constant Balance_Entry_Array := Entries (B);
      Buf  : Unbounded_String;
   begin
      if Ents'Length = 0 then
         return "0";
      end if;

      for I in Ents'Range loop
         if I > Ents'First then
            Append (Buf, ", ");
         end if;
         Append
           (Buf,
            Render_Amount_Or_Paren
              (Ents (I).Val, Code (Ents (I).Comm)));
      end loop;
      return To_String (Buf);
   end Render_Balance;

   function Yes_No (Value : Boolean) return String is
     (if Value then "yes" else "no");

   function Render_Current
     (Value : HRA.Cycle_Accounts_Observation.Observation) return String
   is
      Buf            : Unbounded_String;
      Account_Width  : Natural := HRA.Terminal_Layout.Display_Width ("Account");
      Opening_Width  : Natural := HRA.Terminal_Layout.Display_Width ("Opening");
      Debit_Width    : Natural := HRA.Terminal_Layout.Display_Width ("Debit");
      Credit_Width   : Natural := HRA.Terminal_Layout.Display_Width ("Credit");
      Movement_Width : Natural := HRA.Terminal_Layout.Display_Width ("Movement");
      Closing_Width  : Natural := HRA.Terminal_Layout.Display_Width ("Closing");

      procedure Append_Row
        (Account, Opening, Debit, Credit, Movement, Closing : String)
      is
      begin
         Append
           (Buf,
            HRA.Terminal_Layout.Pad_Right (Account, Account_Width) & " | " &
            HRA.Terminal_Layout.Pad_Left (Opening, Opening_Width) & " | " &
            HRA.Terminal_Layout.Pad_Left (Debit, Debit_Width) & " | " &
            HRA.Terminal_Layout.Pad_Left (Credit, Credit_Width) & " | " &
            HRA.Terminal_Layout.Pad_Left (Movement, Movement_Width) & " | " &
            HRA.Terminal_Layout.Pad_Left (Closing, Closing_Width) & ASCII.LF);
      end Append_Row;
   begin
      for Row of Value.Rows loop
         Account_Width := Natural'Max
           (Account_Width,
            HRA.Terminal_Layout.Display_Width (HRA.Account.Name (Row.Acc)));
         Opening_Width := Natural'Max
           (Opening_Width,
            HRA.Terminal_Layout.Display_Width (Render_Balance (Row.Opening)));
         Debit_Width := Natural'Max
           (Debit_Width,
            HRA.Terminal_Layout.Display_Width (Render_Balance (Row.Debit)));
         Credit_Width := Natural'Max
           (Credit_Width,
            HRA.Terminal_Layout.Display_Width (Render_Balance (Row.Credit)));
         Movement_Width := Natural'Max
           (Movement_Width,
            HRA.Terminal_Layout.Display_Width
              (Render_Balance
                 (HRA.Cycle_Accounts_Observation.Movement (Row))));
         Closing_Width := Natural'Max
           (Closing_Width,
            HRA.Terminal_Layout.Display_Width
              (Render_Balance (HRA.Cycle_Accounts_Observation.Closing (Row))));
      end loop;
      Opening_Width := Natural'Max
        (Opening_Width,
         HRA.Terminal_Layout.Display_Width
           (Render_Balance
              (HRA.Cycle_Accounts_Observation.Opening_Total (Value))));
      Debit_Width := Natural'Max
        (Debit_Width,
         HRA.Terminal_Layout.Display_Width
           (Render_Balance
              (HRA.Cycle_Accounts_Observation.Debit_Total (Value))));
      Credit_Width := Natural'Max
        (Credit_Width,
         HRA.Terminal_Layout.Display_Width
           (Render_Balance
              (HRA.Cycle_Accounts_Observation.Credit_Total (Value))));
      Movement_Width := Natural'Max
        (Movement_Width,
         HRA.Terminal_Layout.Display_Width
           (Render_Balance
              (HRA.Cycle_Accounts_Observation.Movement_Total (Value))));
      Closing_Width := Natural'Max
        (Closing_Width,
         HRA.Terminal_Layout.Display_Width
           (Render_Balance
              (HRA.Cycle_Accounts_Observation.Closing_Total (Value))));

      Append (Buf, "== Current Cycle Accounts ==" & ASCII.LF);
      Append
        (Buf,
         "Cycle: " &
         HRA.Dates.Image (HRA.Cycle_Observation.Start_Date (Value.Window)) &
         ".." &
         HRA.Dates.Image (HRA.Cycle_Observation.End_Exclusive (Value.Window)) &
         " (end exclusive) | Observed through: " &
         HRA.Dates.Image (Value.Observed_Through) & ASCII.LF & ASCII.LF);
      Append_Row
        ("Account", "Opening", "Debit", "Credit", "Movement", "Closing");
      Append
        (Buf,
         [1 .. Account_Width + Opening_Width + Debit_Width + Credit_Width +
                Movement_Width + Closing_Width + 15 => '-'] & ASCII.LF);

      for Row of Value.Rows loop
         Append_Row
           (HRA.Account.Name (Row.Acc),
            Render_Balance (Row.Opening),
            Render_Balance (Row.Debit),
            Render_Balance (Row.Credit),
            Render_Balance (HRA.Cycle_Accounts_Observation.Movement (Row)),
            Render_Balance (HRA.Cycle_Accounts_Observation.Closing (Row)));
      end loop;

      Append_Row
        ("Total",
         Render_Balance (HRA.Cycle_Accounts_Observation.Opening_Total (Value)),
         Render_Balance (HRA.Cycle_Accounts_Observation.Debit_Total (Value)),
         Render_Balance (HRA.Cycle_Accounts_Observation.Credit_Total (Value)),
         Render_Balance (HRA.Cycle_Accounts_Observation.Movement_Total (Value)),
         Render_Balance (HRA.Cycle_Accounts_Observation.Closing_Total (Value)));
      Append
        (Buf,
         "Double-entry balanced: " &
         Yes_No (HRA.Cycle_Accounts_Observation.Is_Balanced (Value)) &
         ASCII.LF);
      return To_String (Buf);
   end Render_Current;

   function Render_Comparison
     (Value : HRA.Report_Cycle_Accounts.Cycle_Comparison_Observation)
      return String
   is
      Buf              : Unbounded_String;
      Account_Width    : Natural := HRA.Terminal_Layout.Display_Width ("Account");
      Current_Width    : Natural :=
        HRA.Terminal_Layout.Display_Width ("Current movement");
      Previous_Width   : Natural :=
        HRA.Terminal_Layout.Display_Width ("Previous same-day");
      Difference_Width : Natural :=
        HRA.Terminal_Layout.Display_Width ("Difference");

      procedure Append_Row
        (Account, Current, Previous, Difference : String)
      is
      begin
         Append
           (Buf,
            HRA.Terminal_Layout.Pad_Right (Account, Account_Width) & " | " &
            HRA.Terminal_Layout.Pad_Left (Current, Current_Width) & " | " &
            HRA.Terminal_Layout.Pad_Left (Previous, Previous_Width) & " | " &
            HRA.Terminal_Layout.Pad_Left (Difference, Difference_Width) &
            ASCII.LF);
      end Append_Row;
   begin
      for Row of Value.Rows loop
         Account_Width := Natural'Max
           (Account_Width,
            HRA.Terminal_Layout.Display_Width (HRA.Account.Name (Row.Acc)));
         Current_Width := Natural'Max
           (Current_Width,
            HRA.Terminal_Layout.Display_Width
              (Render_Balance (Row.Current_Movement)));
         Previous_Width := Natural'Max
           (Previous_Width,
            HRA.Terminal_Layout.Display_Width
              (Render_Balance (Row.Baseline_Movement)));
         Difference_Width := Natural'Max
           (Difference_Width,
            HRA.Terminal_Layout.Display_Width
              (Render_Balance
                 (HRA.Report_Cycle_Accounts.Difference (Row))));
      end loop;
      Current_Width := Natural'Max
        (Current_Width,
         HRA.Terminal_Layout.Display_Width
           (Render_Balance
              (HRA.Report_Cycle_Accounts.Current_Total (Value))));
      Previous_Width := Natural'Max
        (Previous_Width,
         HRA.Terminal_Layout.Display_Width
           (Render_Balance
              (HRA.Report_Cycle_Accounts.Baseline_Total (Value))));
      Difference_Width := Natural'Max
        (Difference_Width,
         HRA.Terminal_Layout.Display_Width
           (Render_Balance
              (HRA.Report_Cycle_Accounts.Difference_Total (Value))));

      Append (Buf, "== Cycle Comparison (Aligned Elapsed) ==" & ASCII.LF);
      Append
        (Buf,
         "Current: " &
         HRA.Dates.Image
           (HRA.Cycle_Observation.Start_Date (Value.Current.Window)) &
         ".." &
         HRA.Dates.Image
           (HRA.Cycle_Observation.End_Exclusive (Value.Current.Window)) &
         " through " & HRA.Dates.Image (Value.Current.Observed_Through) &
         " | Previous: " &
         HRA.Dates.Image
           (HRA.Cycle_Observation.Start_Date (Value.Baseline.Window)) &
         ".." &
         HRA.Dates.Image
           (HRA.Cycle_Observation.End_Exclusive (Value.Baseline.Window)) &
         " through " & HRA.Dates.Image (Value.Baseline.Observed_Through) &
         ASCII.LF & ASCII.LF);
      Append_Row
        ("Account", "Current movement", "Previous same-day", "Difference");
      Append
        (Buf,
         [1 .. Account_Width + Current_Width + Previous_Width +
                Difference_Width + 9 => '-'] & ASCII.LF);

      for Row of Value.Rows loop
         Append_Row
           (HRA.Account.Name (Row.Acc),
            Render_Balance (Row.Current_Movement),
            Render_Balance (Row.Baseline_Movement),
            Render_Balance (HRA.Report_Cycle_Accounts.Difference (Row)));
      end loop;

      Append_Row
        ("Total",
         Render_Balance (HRA.Report_Cycle_Accounts.Current_Total (Value)),
         Render_Balance (HRA.Report_Cycle_Accounts.Baseline_Total (Value)),
         Render_Balance (HRA.Report_Cycle_Accounts.Difference_Total (Value)));
      Append
        (Buf,
         "Double-entry balanced: " &
         Yes_No (HRA.Report_Cycle_Accounts.Is_Balanced (Value)) &
         ASCII.LF);
      return To_String (Buf);
   end Render_Comparison;

   function Render
     (Value : HRA.Report_Cycle_Accounts.Report_Observation) return String
   is
      Buf : Unbounded_String;
   begin
      Append (Buf, Render_Current (Value.Current));
      Append (Buf, ASCII.LF);

      case Value.Comparison.Status is
         when HRA.Report_Cycle_Accounts.Comparison_Available =>
            Append (Buf, Render_Comparison (Value.Comparison.Value));
         when HRA.Report_Cycle_Accounts.Comparison_Unavailable =>
            Append (Buf, "== Cycle Comparison (Aligned Elapsed) ==" & ASCII.LF);
            Append (Buf, "Status: NOT AVAILABLE" & ASCII.LF);
            Append
              (Buf,
               HRA.Report_Cycle_Accounts.Comparison_Status'Image
                 (Value.Comparison.Diagnostic.Status));
            if Length (Value.Comparison.Diagnostic.Account_Name) > 0 then
               Append
                 (Buf,
                  " [account=" &
                  To_String (Value.Comparison.Diagnostic.Account_Name) & "]");
            end if;
            if Length (Value.Comparison.Diagnostic.Message) > 0 then
               Append
                 (Buf,
                  ": " & To_String (Value.Comparison.Diagnostic.Message));
            end if;
            Append (Buf, ASCII.LF);
      end case;

      return To_String (Buf);
   end Render;

end HRA.Cycle_Accounts_Render;
