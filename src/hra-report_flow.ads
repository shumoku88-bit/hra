with Ada.Containers.Vectors;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA.Account;
with HRA.Dates;
with HRA.Ledger;
with HRA.Money; use HRA.Money;

--  Shared typed Income/Expense flow basis for time-indexed accounting reports.
--
--  This owner performs classification, Income sign normalization, period
--  selection, and exact Account x Time aggregation once. Daily Flow and
--  Monthly Accounts are projections of the same admitted Actual Ledger facts.
--  Presentation policy, terminal layout, and source I/O are excluded here.
package HRA.Report_Flow is

   subtype Year_Number is Positive range 1 .. 9_999;
   subtype Month_Number is Positive range 1 .. 12;

   type Year_Month is record
      Year  : Year_Number;
      Month : Month_Number;
   end record;

   function Month_Of (Value : HRA.Dates.Date) return Year_Month;
   function Image (Value : Year_Month) return String;

   package Year_Month_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Year_Month);

   type Daily_Flow_Line is record
      Day      : HRA.Dates.Date;
      Income   : Balance := Empty_Balance;
      Expenses : Balance := Empty_Balance;
   end record;

   function Net (Line : Daily_Flow_Line) return Balance;

   package Daily_Flow_Line_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Daily_Flow_Line);

   type Daily_Expense_Cell is record
      Day   : HRA.Dates.Date;
      Value : Balance := Empty_Balance;
   end record;

   package Daily_Expense_Cell_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Daily_Expense_Cell);

   type Daily_Expense_Row is record
      Acc   : HRA.Account.Account;
      Cells : Daily_Expense_Cell_Vectors.Vector;
   end record;

   package Daily_Expense_Row_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Daily_Expense_Row);

   type Daily_Flow_Observation is record
      Period       : HRA.Dates.Closed_Period;
      Lines        : Daily_Flow_Line_Vectors.Vector;
      Expense_Rows : Daily_Expense_Row_Vectors.Vector;
   end record;

   function Total_Income (Observation : Daily_Flow_Observation) return Balance;
   function Total_Expenses (Observation : Daily_Flow_Observation) return Balance;
   function Total_Net (Observation : Daily_Flow_Observation) return Balance;

   type Monthly_Account_Cell is record
      Month : Year_Month;
      Value : Balance := Empty_Balance;
   end record;

   package Monthly_Account_Cell_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Monthly_Account_Cell);

   type Monthly_Account_Row is record
      Acc   : HRA.Account.Account;
      Cells : Monthly_Account_Cell_Vectors.Vector;
   end record;

   package Monthly_Account_Row_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Monthly_Account_Row);

   type Monthly_Accounts_Observation is record
      Period       : HRA.Dates.Closed_Period;
      Months       : Year_Month_Vectors.Vector;
      Income_Rows  : Monthly_Account_Row_Vectors.Vector;
      Expense_Rows : Monthly_Account_Row_Vectors.Vector;
   end record;

   function Balance_For
     (Row   : Monthly_Account_Row;
      Month : Year_Month) return Balance;

   function Row_Total (Row : Monthly_Account_Row) return Balance;

   function Income_For
     (Observation : Monthly_Accounts_Observation;
      Month       : Year_Month) return Balance;

   function Expenses_For
     (Observation : Monthly_Accounts_Observation;
      Month       : Year_Month) return Balance;

   function Net_For
     (Observation : Monthly_Accounts_Observation;
      Month       : Year_Month) return Balance;

   type Observe_Status is
     (Success,
      Undeclared_Account);

   type Observe_Diagnostic is record
      Status       : Observe_Status := Success;
      Account_Name : Unbounded_String := Null_Unbounded_String;
      Message      : Unbounded_String := Null_Unbounded_String;
   end record;

   --  Build Daily Flow and Monthly Accounts in one pass over admitted Actual.
   --  Asset/Liability/Equity postings are intentionally outside the flow basis.
   --  Income credits are sign-normalized to positive report Income while
   --  Expense postings retain Ledger sign so refunds remain negative Expense.
   function Observe
     (L              : HRA.Ledger.Ledger;
      Daily_Period   : HRA.Dates.Closed_Period;
      Monthly_Period : HRA.Dates.Closed_Period;
      Daily          : out Daily_Flow_Observation;
      Monthly        : out Monthly_Accounts_Observation;
      Diag           : out Observe_Diagnostic) return Boolean;

end HRA.Report_Flow;
