package body ALedger.Report is

   use type ALedger.Dates.Date;

   function Has_Account_Activity
     (L   : Ledger.Ledger;
      Acc : Account.Account) return Boolean
   is
   begin
      for Tx of L.Transactions loop
         for P of Tx.Postings loop
            if P.Acc = Acc then
               return True;
            end if;
         end loop;
      end loop;
      return False;
   end Has_Account_Activity;

   function Has_Account_Activity_Through
     (L       : Ledger.Ledger;
      Acc     : Account.Account;
      Through : ALedger.Dates.Date) return Boolean
   is
   begin
      for Tx of L.Transactions loop
         if Tx.Date <= Through then
            for P of Tx.Postings loop
               if P.Acc = Acc then
                  return True;
               end if;
            end loop;
         end if;
      end loop;
      return False;
   end Has_Account_Activity_Through;

   function Has_Account_Activity_In
     (L      : Ledger.Ledger;
      Acc    : Account.Account;
      Period : ALedger.Dates.Closed_Period) return Boolean
   is
   begin
      for Tx of L.Transactions loop
         if ALedger.Dates.Contains (Period, Tx.Date) then
            for P of Tx.Postings loop
               if P.Acc = Acc then
                  return True;
               end if;
            end loop;
         end if;
      end loop;
      return False;
   end Has_Account_Activity_In;

   procedure Add_Profit_And_Loss_Line
     (PL   : in out Profit_And_Loss;
      Decl : Account_Declaration;
      Bal  : Balance)
   is
   begin
      case Decl.Acc_Type is
         when Income =>
            declare
               Norm_Bal : constant Balance := Negate_Balance (Bal);
            begin
               PL.Income_Lines.Append
                 (Account_Line'(Acc => Decl.Acc, Bal => Norm_Bal));
               PL.Total_Income := Add_Balance (PL.Total_Income, Norm_Bal);
            end;
         when Expense =>
            PL.Expense_Lines.Append
              (Account_Line'(Acc => Decl.Acc, Bal => Bal));
            PL.Total_Expenses := Add_Balance (PL.Total_Expenses, Bal);
         when others =>
            null;
      end case;
   end Add_Profit_And_Loss_Line;

   function Generate_Trial_Balance_As_Of
     (L          : Ledger.Ledger;
      As_Of_Date : ALedger.Dates.Date) return Trial_Balance
   is
      TB : Trial_Balance;
   begin
      TB.Total := Empty_Balance;
      for Decl of Declarations (L.Registry) loop
         if Has_Account_Activity_Through (L, Decl.Acc, As_Of_Date) then
            declare
               Bal : constant Balance :=
                 Compute_Account_Balance_Through (L, Decl.Acc, As_Of_Date);
            begin
               TB.Lines.Append
                 (Account_Line'(Acc => Decl.Acc, Bal => Bal));
               TB.Total := Add_Balance (TB.Total, Bal);
            end;
         end if;
      end loop;
      return TB;
   end Generate_Trial_Balance_As_Of;

   function Generate_Trial_Balance (L : Ledger.Ledger) return Trial_Balance is
      TB : Trial_Balance;
   begin
      TB.Total := Empty_Balance;
      for Decl of Declarations (L.Registry) loop
         if Has_Account_Activity (L, Decl.Acc) then
            declare
               Bal : constant Balance := Compute_Account_Balance (L, Decl.Acc);
            begin
               TB.Lines.Append
                 (Account_Line'(Acc => Decl.Acc, Bal => Bal));
               TB.Total := Add_Balance (TB.Total, Bal);
            end;
         end if;
      end loop;
      return TB;
   end Generate_Trial_Balance;

   function Generate_Profit_And_Loss_Period
     (L      : Ledger.Ledger;
      Period : ALedger.Dates.Closed_Period) return Profit_And_Loss
   is
      PL : Profit_And_Loss;
   begin
      PL.Total_Income   := Empty_Balance;
      PL.Total_Expenses := Empty_Balance;

      for Decl of Declarations (L.Registry) loop
         if Decl.Acc_Type in Income | Expense
           and then Has_Account_Activity_In (L, Decl.Acc, Period)
         then
            Add_Profit_And_Loss_Line
              (PL,
               Decl,
               Compute_Account_Movement_In (L, Decl.Acc, Period));
         end if;
      end loop;

      PL.Net_Income := Subtract_Balance (PL.Total_Income, PL.Total_Expenses);
      return PL;
   end Generate_Profit_And_Loss_Period;

   function Generate_Profit_And_Loss_Through
     (L       : Ledger.Ledger;
      Through : ALedger.Dates.Date) return Profit_And_Loss
   is
      PL : Profit_And_Loss;
   begin
      PL.Total_Income   := Empty_Balance;
      PL.Total_Expenses := Empty_Balance;

      for Decl of Declarations (L.Registry) loop
         if Decl.Acc_Type in Income | Expense
           and then Has_Account_Activity_Through (L, Decl.Acc, Through)
         then
            Add_Profit_And_Loss_Line
              (PL,
               Decl,
               Compute_Account_Balance_Through (L, Decl.Acc, Through));
         end if;
      end loop;

      PL.Net_Income := Subtract_Balance (PL.Total_Income, PL.Total_Expenses);
      return PL;
   end Generate_Profit_And_Loss_Through;

   function Generate_Profit_And_Loss (L : Ledger.Ledger) return Profit_And_Loss is
      PL : Profit_And_Loss;
   begin
      PL.Total_Income   := Empty_Balance;
      PL.Total_Expenses := Empty_Balance;

      for Decl of Declarations (L.Registry) loop
         if Decl.Acc_Type in Income | Expense
           and then Has_Account_Activity (L, Decl.Acc)
         then
            Add_Profit_And_Loss_Line
              (PL, Decl, Compute_Account_Balance (L, Decl.Acc));
         end if;
      end loop;

      PL.Net_Income := Subtract_Balance (PL.Total_Income, PL.Total_Expenses);
      return PL;
   end Generate_Profit_And_Loss;

   procedure Add_Balance_Sheet_Line
     (BS   : in out Balance_Sheet;
      Decl : Account_Declaration;
      Bal  : Balance)
   is
   begin
      case Decl.Acc_Type is
         when Asset =>
            BS.Asset_Lines.Append
              (Account_Line'(Acc => Decl.Acc, Bal => Bal));
            BS.Total_Assets := Add_Balance (BS.Total_Assets, Bal);
         when Liability =>
            declare
               Norm_Bal : constant Balance := Negate_Balance (Bal);
            begin
               BS.Liability_Lines.Append
                 (Account_Line'(Acc => Decl.Acc, Bal => Norm_Bal));
               BS.Total_Liabilities :=
                 Add_Balance (BS.Total_Liabilities, Norm_Bal);
            end;
         when Equity =>
            declare
               Norm_Bal : constant Balance := Negate_Balance (Bal);
            begin
               BS.Equity_Lines.Append
                 (Account_Line'(Acc => Decl.Acc, Bal => Norm_Bal));
               BS.Posted_Equity := Add_Balance (BS.Posted_Equity, Norm_Bal);
            end;
         when others =>
            null;
      end case;
   end Add_Balance_Sheet_Line;

   function Generate_Balance_Sheet_As_Of
     (L          : Ledger.Ledger;
      As_Of_Date : ALedger.Dates.Date) return Balance_Sheet
   is
      BS : Balance_Sheet;
      PL : constant Profit_And_Loss :=
        Generate_Profit_And_Loss_Through (L, As_Of_Date);
   begin
      BS.Total_Assets      := Empty_Balance;
      BS.Total_Liabilities := Empty_Balance;
      BS.Posted_Equity     := Empty_Balance;

      for Decl of Declarations (L.Registry) loop
         if Decl.Acc_Type in Asset | Liability | Equity
           and then Has_Account_Activity_Through (L, Decl.Acc, As_Of_Date)
         then
            Add_Balance_Sheet_Line
              (BS,
               Decl,
               Compute_Account_Balance_Through (L, Decl.Acc, As_Of_Date));
         end if;
      end loop;

      BS.Current_Earnings := PL.Net_Income;
      BS.Total_Equity := Add_Balance (BS.Posted_Equity, BS.Current_Earnings);
      BS.Accounting_Equation_Delta :=
        Subtract_Balance
          (Subtract_Balance (BS.Total_Assets, BS.Total_Liabilities),
           BS.Total_Equity);
      return BS;
   end Generate_Balance_Sheet_As_Of;

   function Generate_Balance_Sheet (L : Ledger.Ledger) return Balance_Sheet is
      BS : Balance_Sheet;
      PL : constant Profit_And_Loss := Generate_Profit_And_Loss (L);
   begin
      BS.Total_Assets      := Empty_Balance;
      BS.Total_Liabilities := Empty_Balance;
      BS.Posted_Equity     := Empty_Balance;

      for Decl of Declarations (L.Registry) loop
         if Decl.Acc_Type in Asset | Liability | Equity
           and then Has_Account_Activity (L, Decl.Acc)
         then
            Add_Balance_Sheet_Line
              (BS, Decl, Compute_Account_Balance (L, Decl.Acc));
         end if;
      end loop;

      BS.Current_Earnings := PL.Net_Income;
      BS.Total_Equity := Add_Balance (BS.Posted_Equity, BS.Current_Earnings);
      BS.Accounting_Equation_Delta :=
        Subtract_Balance
          (Subtract_Balance (BS.Total_Assets, BS.Total_Liabilities),
           BS.Total_Equity);
      return BS;
   end Generate_Balance_Sheet;

end ALedger.Report;
