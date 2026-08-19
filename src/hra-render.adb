with Ada.Strings;           use Ada.Strings;
with Ada.Strings.Fixed;     use Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA.Account;           use HRA.Account;
with HRA.Dates;
with HRA.Money;             use HRA.Money;

package body HRA.Render is

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

   function Render_Multi_Balance (B : Balance) return String is
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
   end Render_Multi_Balance;

   function Render_Account_Balances
     (Value :
        HRA.Household_Report_Observation.Account_Balances_Report_Observation)
      return String
   is
      Buf : Unbounded_String;
   begin
      Append (Buf, "== Account Balances (hra Engine) ==" & ASCII.LF);
      Append (Buf, "As of: " & HRA.Dates.Image (Value.As_Of) & ASCII.LF);
      Append (Buf, ASCII.LF);
      Append (Buf, "Account         |      Balance" & ASCII.LF);
      Append (Buf, "------------------------------" & ASCII.LF);

      for Line of Value.Display_Lines loop
         Append (Buf, Name (Line.Acc) & " | ");
         Append (Buf, Render_Multi_Balance (Line.Bal) & ASCII.LF);
      end loop;

      Append (Buf, ASCII.LF);
      Append
        (Buf,
         (if Value.Is_Balanced then "Balanced: YES" else "Balanced: NO") &
         ASCII.LF);
      return To_String (Buf);
   end Render_Account_Balances;

   function Render_Balance_Sheet
     (Value : HRA.Household_Report_Observation.Balance_Sheet_Report_Observation)
      return String
   is
      Buf : Unbounded_String;
   begin
      Append (Buf, "== Balance Sheet (hra Engine) ==" & ASCII.LF);
      Append (Buf, "As of: " & HRA.Dates.Image (Value.As_Of) & ASCII.LF);
      Append (Buf, ASCII.LF & "Assets" & ASCII.LF);
      Append (Buf, "Account      |    Balance" & ASCII.LF);
      Append (Buf, "-------------------------" & ASCII.LF);
      for Line of Value.Value.Asset_Lines loop
         Append
           (Buf,
            Name (Line.Acc) & " | " & Render_Multi_Balance (Line.Bal) &
            ASCII.LF);
      end loop;
      Append
        (Buf,
         "Total assets | " & Render_Multi_Balance (Value.Value.Total_Assets) &
         ASCII.LF & ASCII.LF);

      Append (Buf, "Liabilities" & ASCII.LF);
      Append (Buf, "Account           | Balance" & ASCII.LF);
      Append (Buf, "---------------------------" & ASCII.LF);
      for Line of Value.Value.Liability_Lines loop
         Append
           (Buf,
            Name (Line.Acc) & " | " & Render_Multi_Balance (Line.Bal) &
            ASCII.LF);
      end loop;
      Append
        (Buf,
         "Total liabilities | " &
         Render_Multi_Balance (Value.Value.Total_Liabilities) & ASCII.LF & ASCII.LF);

      Append (Buf, "Equity" & ASCII.LF);
      Append (Buf, "Account          |    Balance" & ASCII.LF);
      Append (Buf, "-----------------------------" & ASCII.LF);
      for Line of Value.Value.Equity_Lines loop
         Append
           (Buf,
            Name (Line.Acc) & " | " & Render_Multi_Balance (Line.Bal) &
            ASCII.LF);
      end loop;
      Append
        (Buf,
         "Total equity     | " & Render_Multi_Balance (Value.Value.Total_Equity) &
         ASCII.LF & ASCII.LF);
      Append
        (Buf,
         "Current earnings | " &
         Render_Multi_Balance (Value.Value.Current_Earnings) & ASCII.LF);
      Append
        (Buf,
         "Accounting Equation (Assets = Liabilities + Equity): " &
         (if Value.Equation_Is_Balanced
          then "BALANCED (delta is strictly ZERO)"
          else "UNBALANCED") & ASCII.LF);
      return To_String (Buf);
   end Render_Balance_Sheet;

   function Render_Profit_And_Loss
     (Value :
        HRA.Household_Report_Observation.Profit_And_Loss_Report_Observation)
      return String
   is
      Buf : Unbounded_String;
   begin
      Append (Buf, "== Profit & Loss Statement (hra Engine) ==" & ASCII.LF);
      Append
        (Buf,
         "Period: " & HRA.Dates.Image (HRA.Dates.First (Value.Period)) & ".." &
         HRA.Dates.Image (HRA.Dates.Last (Value.Period)) & ASCII.LF & ASCII.LF);

      Append (Buf, "Income" & ASCII.LF);
      Append (Buf, "Account       |    Amount" & ASCII.LF);
      Append (Buf, "-------------------------" & ASCII.LF);
      for Line of Value.Value.Income_Lines loop
         Append
           (Buf,
            Name (Line.Acc) & " | " & Render_Multi_Balance (Line.Bal) &
            ASCII.LF);
      end loop;
      Append
        (Buf,
         "Total Income  | " & Render_Multi_Balance (Value.Value.Total_Income) &
         ASCII.LF & ASCII.LF);

      Append (Buf, "Expenses" & ASCII.LF);
      Append (Buf, "Account                        |    Amount" & ASCII.LF);
      Append (Buf, "------------------------------------------" & ASCII.LF);
      for Line of Value.Value.Expense_Lines loop
         Append
           (Buf,
            Name (Line.Acc) & " | " & Render_Multi_Balance (Line.Bal) &
            ASCII.LF);
      end loop;
      Append
        (Buf,
         "Total Expenses                 | " &
         Render_Multi_Balance (Value.Value.Total_Expenses) & ASCII.LF);
      Append (Buf, "------------------------------------------" & ASCII.LF);
      Append
        (Buf,
         "Net Profit (Income - Expenses) | " &
         Render_Multi_Balance (Value.Value.Net_Income) & ASCII.LF);
      return To_String (Buf);
   end Render_Profit_And_Loss;

   function Render_Household_Issues
     (Value : HRA.Household_Report_Observation.Issues_Report_Observation)
      return String
   is
      Buf : Unbounded_String;
   begin
      Append (Buf, "== Household Issues ==" & ASCII.LF);
      Append
        (Buf,
         "Open issues only | Displayed: " &
         Trim (Natural'Image (Natural (Value.Open_Items.Length)), Both) &
         " | Resolved hidden: " &
         Trim (Natural'Image (Value.Resolved_Count), Both) & ASCII.LF);
      Append
        (Buf,
         "Issues do not change accounting or budget values" &
         ASCII.LF & ASCII.LF);

      for Issue of Value.Open_Items loop
         Append
           (Buf,
            "+- OPEN -------------------------------------------------------------------------------+" &
            ASCII.LF);
         Append (Buf, "| ID       : " & To_String (Issue.Issue_ID) & ASCII.LF);
         Append (Buf, "| Recorded : " & To_String (Issue.Date_Str) & ASCII.LF);
         Append
           (Buf,
            "| Amount   : " & Render_Quantity (Issue.Amt.Val) & " " &
            Code (Issue.Amt.Comm) & ASCII.LF);
         Append (Buf, "| Title    : " & To_String (Issue.Title) & ASCII.LF);
         Append
           (Buf,
            "| Details  : [" & To_String (Issue.Category) & "] " &
            To_String (Issue.Details) & ASCII.LF);
         Append
           (Buf,
            "+--------------------------------------------------------------------------------------+" &
            ASCII.LF & ASCII.LF);
      end loop;

      return To_String (Buf);
   end Render_Household_Issues;

end HRA.Render;
