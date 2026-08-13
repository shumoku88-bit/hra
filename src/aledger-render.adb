with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with ALedger.Money;          use ALedger.Money;
with ALedger.Account;        use ALedger.Account;
with ALedger.Report;         use ALedger.Report;
with ALedger.Budget;         use ALedger.Budget;

package body ALedger.Render is

   function Render_Account_Balances
     (L          : Ledger.Ledger;
      As_Of_Date : String) return String
   is
      Buf : Unbounded_String;
      TB  : constant Trial_Balance := Generate_Trial_Balance (L);
      JPY : constant Commodity := Make_Commodity ("JPY");
   begin
      Append (Buf, "== Account Balances (aledger Engine) ==" & ASCII.LF);
      Append (Buf, "As of: " & As_Of_Date & ASCII.LF);
      Append (Buf, ASCII.LF);
      Append (Buf, "Account         |      Balance" & ASCII.LF);
      Append (Buf, "------------------------------" & ASCII.LF);

      for Decl of Declarations (L.Registry) loop
         declare
            Acc_Bal : constant Balance := Compute_Account_Balance (L, Decl.Acc);
            Val_Q   : constant Quantity := Lookup_Balance (Acc_Bal, JPY);
         begin
            if not Is_Zero (Val_Q) then
               Append (Buf, Name (Decl.Acc) & " | ");
               if Val_Q < Zero_Quantity then
                  Append (Buf, "(" & Render_Quantity (-Val_Q) & " JPY)" & ASCII.LF);
               else
                  Append (Buf, Render_Quantity (Val_Q) & " JPY" & ASCII.LF);
               end if;
            end if;
         end;
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
      As_Of_Date : String) return String
   is
      Buf : Unbounded_String;
      BS  : constant Balance_Sheet := Generate_Balance_Sheet (L);
      JPY : constant Commodity := Make_Commodity ("JPY");
   begin
      Append (Buf, "== Balance Sheet (aledger Engine) ==" & ASCII.LF);
      Append (Buf, "As of: " & As_Of_Date & ASCII.LF);
      Append (Buf, ASCII.LF);
      Append (Buf, "Assets" & ASCII.LF);
      Append (Buf, "Account      |    Balance" & ASCII.LF);
      Append (Buf, "-------------------------" & ASCII.LF);

      for Line of BS.Asset_Lines loop
         Append (Buf, Name (Line.Acc) & " | " & Render_Quantity (Lookup_Balance (Line.Bal, JPY)) & " JPY" & ASCII.LF);
      end loop;
      Append (Buf, "Total assets | " & Render_Quantity (Lookup_Balance (BS.Total_Assets, JPY)) & " JPY" & ASCII.LF);
      Append (Buf, ASCII.LF);

      Append (Buf, "Liabilities" & ASCII.LF);
      Append (Buf, "Account           | Balance" & ASCII.LF);
      Append (Buf, "---------------------------" & ASCII.LF);
      Append (Buf, "Total liabilities |       0" & ASCII.LF);
      Append (Buf, ASCII.LF);

      Append (Buf, "Equity" & ASCII.LF);
      Append (Buf, "Account          |    Balance" & ASCII.LF);
      Append (Buf, "-----------------------------" & ASCII.LF);
      Append (Buf, "Current earnings | " & Render_Quantity (Lookup_Balance (BS.Current_Earnings, JPY)) & " JPY" & ASCII.LF);
      Append (Buf, "Total equity     | " & Render_Quantity (Lookup_Balance (BS.Total_Equity, JPY)) & " JPY" & ASCII.LF);
      Append (Buf, ASCII.LF);

      if Is_Zero_Balance (BS.Accounting_Equation_Delta) then
         Append (Buf, "Balanced: YES (Net Check: 0)" & ASCII.LF);
      else
         Append (Buf, "Balanced: NO" & ASCII.LF);
      end if;

      return To_String (Buf);
   end Render_Balance_Sheet;

   function Render_Profit_And_Loss
     (L          : Ledger.Ledger;
      Start_Date : String;
      End_Date   : String) return String
   is
      Buf : Unbounded_String;
      PL  : constant Profit_And_Loss := Generate_Profit_And_Loss (L);
      JPY : constant Commodity := Make_Commodity ("JPY");
   begin
      Append (Buf, "== Profit & Loss Statement (aledger Engine) ==" & ASCII.LF);
      Append (Buf, "Period: " & Start_Date & ".." & End_Date & ASCII.LF);
      Append (Buf, ASCII.LF);
      Append (Buf, "Income" & ASCII.LF);
      Append (Buf, "Account       |    Amount" & ASCII.LF);
      Append (Buf, "-------------------------" & ASCII.LF);

      for Line of PL.Income_Lines loop
         Append (Buf, Name (Line.Acc) & " | " & Render_Quantity (Lookup_Balance (Line.Bal, JPY)) & " JPY" & ASCII.LF);
      end loop;
      Append (Buf, "Total Income  | " & Render_Quantity (Lookup_Balance (PL.Total_Income, JPY)) & " JPY" & ASCII.LF);
      Append (Buf, ASCII.LF);

      Append (Buf, "Expenses" & ASCII.LF);
      Append (Buf, "Account                        |    Amount" & ASCII.LF);
      Append (Buf, "------------------------------------------" & ASCII.LF);

      for Line of PL.Expense_Lines loop
         Append (Buf, Name (Line.Acc) & " | " & Render_Quantity (Lookup_Balance (Line.Bal, JPY)) & " JPY" & ASCII.LF);
      end loop;
      Append (Buf, "Total Expenses                 | " & Render_Quantity (Lookup_Balance (PL.Total_Expenses, JPY)) & " JPY" & ASCII.LF);
      Append (Buf, "------------------------------------------" & ASCII.LF);
      Append (Buf, "Net Profit (Income - Expenses) | " & Render_Quantity (Lookup_Balance (PL.Net_Income, JPY)) & " JPY" & ASCII.LF);

      return To_String (Buf);
   end Render_Profit_And_Loss;

   function Render_Budget_Status
     (L : Ledger.Ledger) return String
   is
      Buf : Unbounded_String;
      BSR : constant Budget_Status_Report := Generate_Budget_Status (L);
      JPY : constant Commodity := Make_Commodity ("JPY");
   begin
      Append (Buf, "== Budget Envelope Status (aledger Engine) ==" & ASCII.LF);
      Append (Buf, ASCII.LF);
      Append (Buf, "Envelope Account        | Allocated     | Spent         | Remaining" & ASCII.LF);
      Append (Buf, "-------------------------------------------------------------------" & ASCII.LF);

      for Env of BSR.Envelopes loop
         declare
            Ent   : constant Quantity := Lookup_Balance (Env.Entitlement, JPY);
            Con   : constant Quantity := Lookup_Balance (Env.Consumption, JPY);
            Rem_Q : constant Quantity := Lookup_Balance (Remaining (Env), JPY);
         begin
            Append (Buf, Name (Env.Acc) & " | ");
            Append (Buf, Render_Quantity (Ent) & " JPY | ");
            Append (Buf, Render_Quantity (Con) & " JPY | ");
            Append (Buf, Render_Quantity (Rem_Q) & " JPY" & ASCII.LF);
         end;
      end loop;

      Append (Buf, "-------------------------------------------------------------------" & ASCII.LF);
      Append (Buf, "Total Envelope Status   | " &
              Render_Quantity (Lookup_Balance (BSR.Total_Entitlement, JPY)) & " JPY | " &
              Render_Quantity (Lookup_Balance (BSR.Total_Consumption, JPY)) & " JPY | " &
              Render_Quantity (Lookup_Balance (BSR.Total_Remaining, JPY)) & " JPY" & ASCII.LF);

      return To_String (Buf);
   end Render_Budget_Status;

end ALedger.Render;
