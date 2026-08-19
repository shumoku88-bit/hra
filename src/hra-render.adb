with Ada.Strings.Fixed;      use Ada.Strings.Fixed;
with Ada.Strings.Unbounded;  use Ada.Strings.Unbounded;
with HRA.Money;          use HRA.Money;
with HRA.Account;        use HRA.Account;
with HRA.Report;         use HRA.Report;

package body HRA.Render is

   function Render_Amount_Or_Paren (Q : Quantity; Comm_Code : String) return String is
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
         Append (Buf, Render_Amount_Or_Paren (Ents (I).Val, Code (Ents (I).Comm)));
      end loop;

      return To_String (Buf);
   end Render_Multi_Balance;

   function Render_Account_Balances
     (L          : Ledger.Ledger;
      As_Of_Date : HRA.Dates.Date) return String
   is
      Buf : Unbounded_String;
      TB  : constant Trial_Balance := Generate_Trial_Balance_As_Of (L, As_Of_Date);
   begin
      Append (Buf, "== Account Balances (hra Engine) ==" & ASCII.LF);
      Append (Buf, "As of: " & HRA.Dates.Image (As_Of_Date) & ASCII.LF);
      Append (Buf, ASCII.LF);
      Append (Buf, "Account         |      Balance" & ASCII.LF);
      Append (Buf, "------------------------------" & ASCII.LF);

      for Line of TB.Lines loop
         if not Is_Zero_Balance (Line.Bal) then
            Append (Buf, Name (Line.Acc) & " | ");
            Append (Buf, Render_Multi_Balance (Line.Bal) & ASCII.LF);
         end if;
      end loop;

      Append (Buf, ASCII.LF);
      if Is_Zero_Balance (TB.Total) then
         Append (Buf, "Balanced: YES" & ASCII.LF);
      else
         Append (Buf, "Balanced: NO" & ASCII.LF);
      end if;

      return To_String (Buf);
   end Render_Account_Balances;

   function Render_Account_Balances
     (L : Ledger.Ledger) return String
   is
      Buf : Unbounded_String;
      TB  : constant Trial_Balance := Generate_Trial_Balance (L);
   begin
      Append (Buf, "== Account Balances (hra Engine) ==" & ASCII.LF);
      Append (Buf, "As of: all transactions" & ASCII.LF);
      Append (Buf, ASCII.LF);
      Append (Buf, "Account         |      Balance" & ASCII.LF);
      Append (Buf, "------------------------------" & ASCII.LF);

      for Line of TB.Lines loop
         if not Is_Zero_Balance (Line.Bal) then
            Append (Buf, Name (Line.Acc) & " | ");
            Append (Buf, Render_Multi_Balance (Line.Bal) & ASCII.LF);
         end if;
      end loop;

      Append (Buf, ASCII.LF);
      if Is_Zero_Balance (TB.Total) then
         Append (Buf, "Balanced: YES" & ASCII.LF);
      else
         Append (Buf, "Balanced: NO" & ASCII.LF);
      end if;

      return To_String (Buf);
   end Render_Account_Balances;

   function Render_Balance_Sheet
     (L          : Ledger.Ledger;
      As_Of_Date : HRA.Dates.Date) return String
   is
      Buf : Unbounded_String;
      BS  : constant Balance_Sheet := Generate_Balance_Sheet_As_Of (L, As_Of_Date);
   begin
      Append (Buf, "== Balance Sheet (hra Engine) ==" & ASCII.LF);
      Append (Buf, "As of: " & HRA.Dates.Image (As_Of_Date) & ASCII.LF);
      Append (Buf, ASCII.LF);
      Append (Buf, "Assets" & ASCII.LF);
      Append (Buf, "Account      |    Balance" & ASCII.LF);
      Append (Buf, "-------------------------" & ASCII.LF);

      for Line of BS.Asset_Lines loop
         Append (Buf, Name (Line.Acc) & " | " & Render_Multi_Balance (Line.Bal) & ASCII.LF);
      end loop;
      Append (Buf, "Total assets | " & Render_Multi_Balance (BS.Total_Assets) & ASCII.LF);
      Append (Buf, ASCII.LF);

      Append (Buf, "Liabilities" & ASCII.LF);
      Append (Buf, "Account           | Balance" & ASCII.LF);
      Append (Buf, "---------------------------" & ASCII.LF);
      for Line of BS.Liability_Lines loop
         Append (Buf, Name (Line.Acc) & " | " & Render_Multi_Balance (Line.Bal) & ASCII.LF);
      end loop;
      Append (Buf, "Total liabilities | " & Render_Multi_Balance (BS.Total_Liabilities) & ASCII.LF);
      Append (Buf, ASCII.LF);

      Append (Buf, "Equity" & ASCII.LF);
      Append (Buf, "Account          |    Balance" & ASCII.LF);
      Append (Buf, "-----------------------------" & ASCII.LF);
      for Line of BS.Equity_Lines loop
         Append (Buf, Name (Line.Acc) & " | " & Render_Multi_Balance (Line.Bal) & ASCII.LF);
      end loop;
      Append (Buf, "Total equity     | " & Render_Multi_Balance (BS.Total_Equity) & ASCII.LF);
      Append (Buf, ASCII.LF);

      Append (Buf, "Current earnings | " & Render_Multi_Balance (BS.Current_Earnings) & ASCII.LF);
      Append (Buf, "Accounting Equation (Assets = Liabilities + Equity): ");
      if Is_Zero_Balance (BS.Accounting_Equation_Delta) then
         Append (Buf, "BALANCED (delta is strictly ZERO)" & ASCII.LF);
      else
         Append (Buf, "UNBALANCED" & ASCII.LF);
      end if;

      return To_String (Buf);
   end Render_Balance_Sheet;

   function Render_Balance_Sheet
     (L : Ledger.Ledger) return String
   is
      Buf : Unbounded_String;
      BS  : constant Balance_Sheet := Generate_Balance_Sheet (L);
   begin
      Append (Buf, "== Balance Sheet (hra Engine) ==" & ASCII.LF);
      Append (Buf, "As of: all transactions" & ASCII.LF);
      Append (Buf, ASCII.LF);
      Append (Buf, "Assets" & ASCII.LF);
      Append (Buf, "Account      |    Balance" & ASCII.LF);
      Append (Buf, "-------------------------" & ASCII.LF);

      for Line of BS.Asset_Lines loop
         Append (Buf, Name (Line.Acc) & " | " & Render_Multi_Balance (Line.Bal) & ASCII.LF);
      end loop;
      Append (Buf, "Total assets | " & Render_Multi_Balance (BS.Total_Assets) & ASCII.LF);
      Append (Buf, ASCII.LF);

      Append (Buf, "Liabilities" & ASCII.LF);
      Append (Buf, "Account           | Balance" & ASCII.LF);
      Append (Buf, "---------------------------" & ASCII.LF);
      for Line of BS.Liability_Lines loop
         Append (Buf, Name (Line.Acc) & " | " & Render_Multi_Balance (Line.Bal) & ASCII.LF);
      end loop;
      Append (Buf, "Total liabilities | " & Render_Multi_Balance (BS.Total_Liabilities) & ASCII.LF);
      Append (Buf, ASCII.LF);

      Append (Buf, "Equity" & ASCII.LF);
      Append (Buf, "Account          |    Balance" & ASCII.LF);
      Append (Buf, "-----------------------------" & ASCII.LF);
      for Line of BS.Equity_Lines loop
         Append (Buf, Name (Line.Acc) & " | " & Render_Multi_Balance (Line.Bal) & ASCII.LF);
      end loop;
      Append (Buf, "Total equity     | " & Render_Multi_Balance (BS.Total_Equity) & ASCII.LF);
      Append (Buf, ASCII.LF);

      Append (Buf, "Current earnings | " & Render_Multi_Balance (BS.Current_Earnings) & ASCII.LF);
      Append (Buf, "Accounting Equation (Assets = Liabilities + Equity): ");
      if Is_Zero_Balance (BS.Accounting_Equation_Delta) then
         Append (Buf, "BALANCED (delta is strictly ZERO)" & ASCII.LF);
      else
         Append (Buf, "UNBALANCED" & ASCII.LF);
      end if;

      return To_String (Buf);
   end Render_Balance_Sheet;

   function Render_Profit_And_Loss
     (L      : Ledger.Ledger;
      Period : HRA.Dates.Closed_Period) return String
   is
      Buf : Unbounded_String;
      PL  : constant Profit_And_Loss := Generate_Profit_And_Loss_Period (L, Period);
   begin
      Append (Buf, "== Profit & Loss Statement (hra Engine) ==" & ASCII.LF);
      Append (Buf, "Period: " &
              HRA.Dates.Image (HRA.Dates.First (Period)) & ".." &
              HRA.Dates.Image (HRA.Dates.Last (Period)) & ASCII.LF);
      Append (Buf, ASCII.LF);

      Append (Buf, "Income" & ASCII.LF);
      Append (Buf, "Account       |    Amount" & ASCII.LF);
      Append (Buf, "-------------------------" & ASCII.LF);
      for Line of PL.Income_Lines loop
         Append (Buf, Name (Line.Acc) & " | " & Render_Multi_Balance (Line.Bal) & ASCII.LF);
      end loop;
      Append (Buf, "Total Income  | " & Render_Multi_Balance (PL.Total_Income) & ASCII.LF);
      Append (Buf, ASCII.LF);

      Append (Buf, "Expenses" & ASCII.LF);
      Append (Buf, "Account                        |    Amount" & ASCII.LF);
      Append (Buf, "------------------------------------------" & ASCII.LF);
      for Line of PL.Expense_Lines loop
         Append (Buf, Name (Line.Acc) & " | " & Render_Multi_Balance (Line.Bal) & ASCII.LF);
      end loop;
      Append (Buf, "Total Expenses                 | " & Render_Multi_Balance (PL.Total_Expenses) & ASCII.LF);
      Append (Buf, "------------------------------------------" & ASCII.LF);
      Append (Buf, "Net Profit (Income - Expenses) | " & Render_Multi_Balance (PL.Net_Income) & ASCII.LF);

      return To_String (Buf);
   end Render_Profit_And_Loss;

   function Render_Profit_And_Loss
     (L : Ledger.Ledger) return String
   is
      Buf : Unbounded_String;
      PL  : constant Profit_And_Loss := Generate_Profit_And_Loss (L);
   begin
      Append (Buf, "== Profit & Loss Statement (hra Engine) ==" & ASCII.LF);
      Append (Buf, "Period: all transactions" & ASCII.LF);
      Append (Buf, ASCII.LF);

      Append (Buf, "Income" & ASCII.LF);
      Append (Buf, "Account       |    Amount" & ASCII.LF);
      Append (Buf, "-------------------------" & ASCII.LF);
      for Line of PL.Income_Lines loop
         Append (Buf, Name (Line.Acc) & " | " & Render_Multi_Balance (Line.Bal) & ASCII.LF);
      end loop;
      Append (Buf, "Total Income  | " & Render_Multi_Balance (PL.Total_Income) & ASCII.LF);
      Append (Buf, ASCII.LF);

      Append (Buf, "Expenses" & ASCII.LF);
      Append (Buf, "Account                        |    Amount" & ASCII.LF);
      Append (Buf, "------------------------------------------" & ASCII.LF);
      for Line of PL.Expense_Lines loop
         Append (Buf, Name (Line.Acc) & " | " & Render_Multi_Balance (Line.Bal) & ASCII.LF);
      end loop;
      Append (Buf, "Total Expenses                 | " & Render_Multi_Balance (PL.Total_Expenses) & ASCII.LF);
      Append (Buf, "------------------------------------------" & ASCII.LF);
      Append (Buf, "Net Profit (Income - Expenses) | " & Render_Multi_Balance (PL.Net_Income) & ASCII.LF);

      return To_String (Buf);
   end Render_Profit_And_Loss;

   function Render_Household_Issues (Inv : Issues_Inventory) return String is
      Buf   : Unbounded_String;
      Opens : constant Issue_Vectors.Vector := Open_Issues (Inv);
      Total : constant Natural := Natural (Inv.Items.Length);
      Open_C: constant Natural := Natural (Opens.Length);
      Res_C : constant Natural := Total - Open_C;
   begin
      Append (Buf, "== Household Issues ==" & ASCII.LF);
      Append (Buf, "Source: issues.tsv | open issues only | Displayed: " &
              Trim (Natural'Image (Open_C), Ada.Strings.Both) & " | Resolved hidden: " &
              Trim (Natural'Image (Res_C), Ada.Strings.Both) & ASCII.LF);
      Append (Buf, "Issues do not change accounting or budget values" & ASCII.LF);
      Append (Buf, ASCII.LF);

      for Issue of Opens loop
         Append (Buf, "+- OPEN -------------------------------------------------------------------------------+" & ASCII.LF);
         Append (Buf, "| ID       : " & To_String (Issue.Issue_ID) & ASCII.LF);
         Append (Buf, "| Recorded : " & To_String (Issue.Date_Str) & ASCII.LF);
         Append (Buf, "| Amount   : " & Render_Quantity (Issue.Amt.Val) & " " & Code (Issue.Amt.Comm) & ASCII.LF);
         Append (Buf, "| Title    : " & To_String (Issue.Title) & ASCII.LF);
         Append (Buf, "| Details  : [" & To_String (Issue.Category) & "] " & To_String (Issue.Details) & ASCII.LF);
         Append (Buf, "+--------------------------------------------------------------------------------------+" & ASCII.LF);
         Append (Buf, ASCII.LF);
      end loop;

      return To_String (Buf);
   end Render_Household_Issues;

   function Render_Recent_Transactions
     (L     : Ledger.Ledger;
      Count : Positive := 5) return String
   is
      Buf   : Unbounded_String;
      Total : constant Natural := Natural (L.Transactions.Length);
      Start : constant Natural := (if Total > Count then Total - Count + 1 else 1);
   begin
      Append (Buf, "== Recent Transactions (Latest " & Trim (Natural'Image (Count), Ada.Strings.Both) & ") ==" & ASCII.LF);
      Append (Buf, ASCII.LF);

      for I in reverse Start .. Total loop
         declare
            Tx : constant Transaction := L.Transactions.Element (I);
         begin
            Append (Buf, HRA.Dates.Image (Tx.Date) & " " & To_String (Tx.Code_Or_Payee) & ASCII.LF);
            for P of Tx.Postings loop
               Append (Buf, "    " & Name (P.Acc) & "    " & Render_Amount_Or_Paren (P.Amt.Val, Code (P.Amt.Comm)) & ASCII.LF);
            end loop;
            Append (Buf, ASCII.LF);
         end;
      end loop;

      return To_String (Buf);
   end Render_Recent_Transactions;

end HRA.Render;
