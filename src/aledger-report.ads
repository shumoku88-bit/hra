with Ada.Containers.Indefinite_Vectors;
with ALedger.Money;   use ALedger.Money;
with ALedger.Account; use ALedger.Account;
with ALedger.Ledger;  use ALedger.Ledger;

package ALedger.Report is

   --  ========================================================================
   --  Account Line & Classification Facts
   --  ========================================================================

   type Account_Line is record
      Acc : Account.Account;
      Bal : Balance;
   end record;

   package Line_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Account_Line);

   --  ========================================================================
   --  Trial Balance (試算表)
   --  ========================================================================

   type Trial_Balance is record
      Lines : Line_Vectors.Vector;
      Total : Balance;
   end record;

   function Generate_Trial_Balance (L : Ledger.Ledger) return Trial_Balance;

   --  ========================================================================
   --  Profit and Loss / Income Statement (損益計算書)
   --  ========================================================================

   type Profit_And_Loss is record
      Income_Lines   : Line_Vectors.Vector;
      Expense_Lines  : Line_Vectors.Vector;
      Total_Income   : Balance;
      Total_Expenses : Balance;
      Net_Income     : Balance;
   end record;

   function Generate_Profit_And_Loss (L : Ledger.Ledger) return Profit_And_Loss;

   --  ========================================================================
   --  Balance Sheet (貸借対照表)
   --  ========================================================================

   type Balance_Sheet is record
      Asset_Lines               : Line_Vectors.Vector;
      Liability_Lines           : Line_Vectors.Vector;
      Equity_Lines              : Line_Vectors.Vector;
      Total_Assets              : Balance;
      Total_Liabilities         : Balance;
      Posted_Equity             : Balance;
      Current_Earnings          : Balance;
      Total_Equity              : Balance;
      Accounting_Equation_Delta : Balance;  --  Must be Zero! (Assets - Liabilities - Equity = 0)
   end record;

   function Generate_Balance_Sheet (L : Ledger.Ledger) return Balance_Sheet;

end ALedger.Report;
