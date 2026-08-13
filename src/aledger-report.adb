with Ada.Containers.Indefinite_Ordered_Maps;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

package body ALedger.Report is

   --  Map helper for account balances
   package Account_Balance_Maps is new Ada.Containers.Indefinite_Ordered_Maps
     (Key_Type     => String,
      Element_Type => Balance);

   procedure Collect_Account_Balances_Filtered
     (L          : Ledger.Ledger;
      Start_Date : String;
      End_Date   : String;
      Map        : out Account_Balance_Maps.Map)
   is
      Tx_Cursor : Transaction_Vectors.Cursor := L.Transactions.First;
   begin
      while Transaction_Vectors.Has_Element (Tx_Cursor) loop
         declare
            Tx      : constant Transaction := Transaction_Vectors.Element (Tx_Cursor);
            Tx_Date : constant String := To_String (Tx.Date_Text);
         begin
            if (Start_Date'Length = 0 or else Tx_Date >= Start_Date) and then
               (End_Date'Length = 0 or else Tx_Date <= End_Date) then
               declare
                  P_Cursor : Posting_Vectors.Cursor := Tx.Postings.First;
               begin
                  while Posting_Vectors.Has_Element (P_Cursor) loop
                     declare
                        P       : constant Posting := Posting_Vectors.Element (P_Cursor);
                        Acc_Key : constant String := Name (P.Acc);
                        Amt_Bal : constant Balance := Singleton_Balance (P.Amt);
                     begin
                        if Map.Contains (Acc_Key) then
                           Map.Replace (Acc_Key, Add_Balance (Map.Element (Acc_Key), Amt_Bal));
                        else
                           Map.Insert (Acc_Key, Amt_Bal);
                        end if;
                     end;
                     Posting_Vectors.Next (P_Cursor);
                  end loop;
               end;
            end if;
         end;
         Transaction_Vectors.Next (Tx_Cursor);
      end loop;
   end Collect_Account_Balances_Filtered;

   function Generate_Trial_Balance_As_Of
     (L          : Ledger.Ledger;
      As_Of_Date : String) return Trial_Balance
   is
      TB     : Trial_Balance;
      Map    : Account_Balance_Maps.Map;
      Cursor : Account_Balance_Maps.Cursor;
      Tot    : Balance := Empty_Balance;
   begin
      Collect_Account_Balances_Filtered (L, "", As_Of_Date, Map);
      Cursor := Map.First;
      while Account_Balance_Maps.Has_Element (Cursor) loop
         declare
            Acc_Key : constant String := Account_Balance_Maps.Key (Cursor);
            Bal     : constant Balance := Account_Balance_Maps.Element (Cursor);
            Acc     : constant Account.Account := Make_Account (Acc_Key);
         begin
            TB.Lines.Append (Account_Line'(Acc => Acc, Bal => Bal));
            Tot := Add_Balance (Tot, Bal);
         end;
         Account_Balance_Maps.Next (Cursor);
      end loop;
      TB.Total := Tot;
      return TB;
   end Generate_Trial_Balance_As_Of;

   function Generate_Trial_Balance (L : Ledger.Ledger) return Trial_Balance is
   begin
      return Generate_Trial_Balance_As_Of (L, "");
   end Generate_Trial_Balance;

   function Generate_Profit_And_Loss_Period
     (L          : Ledger.Ledger;
      Start_Date : String;
      End_Date   : String) return Profit_And_Loss
   is
      PL      : Profit_And_Loss;
      Map     : Account_Balance_Maps.Map;
      Cursor  : Account_Balance_Maps.Cursor;
      Tot_Inc : Balance := Empty_Balance;
      Tot_Exp : Balance := Empty_Balance;
   begin
      Collect_Account_Balances_Filtered (L, Start_Date, End_Date, Map);
      Cursor := Map.First;
      while Account_Balance_Maps.Has_Element (Cursor) loop
         declare
            Acc_Key : constant String := Account_Balance_Maps.Key (Cursor);
            Bal     : constant Balance := Account_Balance_Maps.Element (Cursor);
            Acc     : constant Account.Account := Make_Account (Acc_Key);
            Cat     : Account_Type;
         begin
            if Account_Type_For (L.Registry, Acc, Cat) then
               if Cat = Income then
                  declare
                     Norm_Bal : constant Balance := Negate_Balance (Bal);
                  begin
                     PL.Income_Lines.Append (Account_Line'(Acc => Acc, Bal => Norm_Bal));
                     Tot_Inc := Add_Balance (Tot_Inc, Norm_Bal);
                  end;
               elsif Cat = Expense then
                  PL.Expense_Lines.Append (Account_Line'(Acc => Acc, Bal => Bal));
                  Tot_Exp := Add_Balance (Tot_Exp, Bal);
               end if;
            end if;
         end;
         Account_Balance_Maps.Next (Cursor);
      end loop;

      PL.Total_Income   := Tot_Inc;
      PL.Total_Expenses := Tot_Exp;
      PL.Net_Income     := Subtract_Balance (Tot_Inc, Tot_Exp);
      return PL;
   end Generate_Profit_And_Loss_Period;

   function Generate_Profit_And_Loss (L : Ledger.Ledger) return Profit_And_Loss is
   begin
      return Generate_Profit_And_Loss_Period (L, "", "");
   end Generate_Profit_And_Loss;

   function Generate_Balance_Sheet_As_Of
     (L          : Ledger.Ledger;
      As_Of_Date : String) return Balance_Sheet
   is
      BS      : Balance_Sheet;
      Map     : Account_Balance_Maps.Map;
      Cursor  : Account_Balance_Maps.Cursor;
      Tot_Ast : Balance := Empty_Balance;
      Tot_Lia : Balance := Empty_Balance;
      Tot_Eq  : Balance := Empty_Balance;

      --  Current earnings for Balance Sheet as of Date: Profit & Loss through As_Of_Date
      PL : constant Profit_And_Loss := Generate_Profit_And_Loss_Period (L, "", As_Of_Date);
   begin
      Collect_Account_Balances_Filtered (L, "", As_Of_Date, Map);
      Cursor := Map.First;
      while Account_Balance_Maps.Has_Element (Cursor) loop
         declare
            Acc_Key : constant String := Account_Balance_Maps.Key (Cursor);
            Bal     : constant Balance := Account_Balance_Maps.Element (Cursor);
            Acc     : constant Account.Account := Make_Account (Acc_Key);
            Cat     : Account_Type;
         begin
            if Account_Type_For (L.Registry, Acc, Cat) then
               if Cat = Asset then
                  BS.Asset_Lines.Append (Account_Line'(Acc => Acc, Bal => Bal));
                  Tot_Ast := Add_Balance (Tot_Ast, Bal);
               elsif Cat = Liability then
                  declare
                     Norm_Bal : constant Balance := Negate_Balance (Bal);
                  begin
                     BS.Liability_Lines.Append (Account_Line'(Acc => Acc, Bal => Norm_Bal));
                     Tot_Lia := Add_Balance (Tot_Lia, Norm_Bal);
                  end;
               elsif Cat = Equity then
                  declare
                     Norm_Bal : constant Balance := Negate_Balance (Bal);
                  begin
                     BS.Equity_Lines.Append (Account_Line'(Acc => Acc, Bal => Norm_Bal));
                     Tot_Eq := Add_Balance (Tot_Eq, Norm_Bal);
                  end;
               end if;
            end if;
         end;
         Account_Balance_Maps.Next (Cursor);
      end loop;

      BS.Total_Assets      := Tot_Ast;
      BS.Total_Liabilities := Tot_Lia;
      BS.Posted_Equity     := Tot_Eq;
      BS.Current_Earnings  := PL.Net_Income;
      BS.Total_Equity      := Add_Balance (Tot_Eq, PL.Net_Income);

      --  Accounting Equation Delta: Assets - Liabilities - Equity (Must be 0!)
      BS.Accounting_Equation_Delta :=
        Subtract_Balance (Subtract_Balance (Tot_Ast, Tot_Lia), BS.Total_Equity);

      return BS;
   end Generate_Balance_Sheet_As_Of;

   function Generate_Balance_Sheet (L : Ledger.Ledger) return Balance_Sheet is
   begin
      return Generate_Balance_Sheet_As_Of (L, "");
   end Generate_Balance_Sheet;

end ALedger.Report;
