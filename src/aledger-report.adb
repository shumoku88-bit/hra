with Ada.Containers.Indefinite_Ordered_Maps;
with ALedger.Dates;

package body ALedger.Report is

   use type ALedger.Dates.Date;

   package Account_Balance_Maps is new Ada.Containers.Indefinite_Ordered_Maps
     (Key_Type     => String,
      Element_Type => Balance);

   procedure Add_Transaction_Postings
     (Tx  : Transaction;
      Map : in out Account_Balance_Maps.Map)
   is
   begin
      for P of Tx.Postings loop
         declare
            Acc_Key : constant String := Name (P.Acc);
            Amt_Bal : constant Balance := Singleton_Balance (P.Amt);
         begin
            if Map.Contains (Acc_Key) then
               Map.Replace
                 (Acc_Key, Add_Balance (Map.Element (Acc_Key), Amt_Bal));
            else
               Map.Insert (Acc_Key, Amt_Bal);
            end if;
         end;
      end loop;
   end Add_Transaction_Postings;

   procedure Collect_All_Account_Balances
     (L   : Ledger.Ledger;
      Map : out Account_Balance_Maps.Map)
   is
   begin
      for Tx of L.Transactions loop
         Add_Transaction_Postings (Tx, Map);
      end loop;
   end Collect_All_Account_Balances;

   procedure Collect_Account_Balances_Through
     (L          : Ledger.Ledger;
      Through    : ALedger.Dates.Date;
      Map        : out Account_Balance_Maps.Map)
   is
   begin
      for Tx of L.Transactions loop
         if Tx.Date <= Through then
            Add_Transaction_Postings (Tx, Map);
         end if;
      end loop;
   end Collect_Account_Balances_Through;

   procedure Collect_Account_Balances_In
     (L      : Ledger.Ledger;
      Period : ALedger.Dates.Closed_Period;
      Map    : out Account_Balance_Maps.Map)
   is
   begin
      for Tx of L.Transactions loop
         if ALedger.Dates.Contains (Period, Tx.Date) then
            Add_Transaction_Postings (Tx, Map);
         end if;
      end loop;
   end Collect_Account_Balances_In;

   function Trial_Balance_From_Map
     (Map : Account_Balance_Maps.Map) return Trial_Balance
   is
      TB     : Trial_Balance;
      Cursor : Account_Balance_Maps.Cursor := Map.First;
      Tot    : Balance := Empty_Balance;
   begin
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
   end Trial_Balance_From_Map;

   function Generate_Trial_Balance_As_Of
     (L          : Ledger.Ledger;
      As_Of_Date : ALedger.Dates.Date) return Trial_Balance
   is
      Map : Account_Balance_Maps.Map;
   begin
      Collect_Account_Balances_Through (L, As_Of_Date, Map);
      return Trial_Balance_From_Map (Map);
   end Generate_Trial_Balance_As_Of;

   function Generate_Trial_Balance (L : Ledger.Ledger) return Trial_Balance is
      Map : Account_Balance_Maps.Map;
   begin
      Collect_All_Account_Balances (L, Map);
      return Trial_Balance_From_Map (Map);
   end Generate_Trial_Balance;

   function Profit_And_Loss_From_Map
     (L   : Ledger.Ledger;
      Map : Account_Balance_Maps.Map) return Profit_And_Loss
   is
      PL      : Profit_And_Loss;
      Cursor  : Account_Balance_Maps.Cursor := Map.First;
      Tot_Inc : Balance := Empty_Balance;
      Tot_Exp : Balance := Empty_Balance;
   begin
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
                     PL.Income_Lines.Append
                       (Account_Line'(Acc => Acc, Bal => Norm_Bal));
                     Tot_Inc := Add_Balance (Tot_Inc, Norm_Bal);
                  end;
               elsif Cat = Expense then
                  PL.Expense_Lines.Append
                    (Account_Line'(Acc => Acc, Bal => Bal));
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
   end Profit_And_Loss_From_Map;

   function Generate_Profit_And_Loss_Period
     (L      : Ledger.Ledger;
      Period : ALedger.Dates.Closed_Period) return Profit_And_Loss
   is
      Map : Account_Balance_Maps.Map;
   begin
      Collect_Account_Balances_In (L, Period, Map);
      return Profit_And_Loss_From_Map (L, Map);
   end Generate_Profit_And_Loss_Period;

   function Generate_Profit_And_Loss (L : Ledger.Ledger) return Profit_And_Loss is
      Map : Account_Balance_Maps.Map;
   begin
      Collect_All_Account_Balances (L, Map);
      return Profit_And_Loss_From_Map (L, Map);
   end Generate_Profit_And_Loss;

   function Balance_Sheet_From_Map
     (L       : Ledger.Ledger;
      Map     : Account_Balance_Maps.Map;
      Earnings : Balance) return Balance_Sheet
   is
      BS      : Balance_Sheet;
      Cursor  : Account_Balance_Maps.Cursor := Map.First;
      Tot_Ast : Balance := Empty_Balance;
      Tot_Lia : Balance := Empty_Balance;
      Tot_Eq  : Balance := Empty_Balance;
   begin
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
                     BS.Liability_Lines.Append
                       (Account_Line'(Acc => Acc, Bal => Norm_Bal));
                     Tot_Lia := Add_Balance (Tot_Lia, Norm_Bal);
                  end;
               elsif Cat = Equity then
                  declare
                     Norm_Bal : constant Balance := Negate_Balance (Bal);
                  begin
                     BS.Equity_Lines.Append
                       (Account_Line'(Acc => Acc, Bal => Norm_Bal));
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
      BS.Current_Earnings  := Earnings;
      BS.Total_Equity      := Add_Balance (Tot_Eq, Earnings);
      BS.Accounting_Equation_Delta :=
        Subtract_Balance
          (Subtract_Balance (Tot_Ast, Tot_Lia), BS.Total_Equity);
      return BS;
   end Balance_Sheet_From_Map;

   function Generate_Balance_Sheet_As_Of
     (L          : Ledger.Ledger;
      As_Of_Date : ALedger.Dates.Date) return Balance_Sheet
   is
      Map        : Account_Balance_Maps.Map;
      Income_Map : Account_Balance_Maps.Map;
      PL         : Profit_And_Loss;
   begin
      Collect_Account_Balances_Through (L, As_Of_Date, Map);
      Collect_Account_Balances_Through (L, As_Of_Date, Income_Map);
      PL := Profit_And_Loss_From_Map (L, Income_Map);
      return Balance_Sheet_From_Map (L, Map, PL.Net_Income);
   end Generate_Balance_Sheet_As_Of;

   function Generate_Balance_Sheet (L : Ledger.Ledger) return Balance_Sheet is
      Map : Account_Balance_Maps.Map;
      PL  : constant Profit_And_Loss := Generate_Profit_And_Loss (L);
   begin
      Collect_All_Account_Balances (L, Map);
      return Balance_Sheet_From_Map (L, Map, PL.Net_Income);
   end Generate_Balance_Sheet;

end ALedger.Report;
