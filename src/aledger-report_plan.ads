with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with ALedger.Ledger;         use ALedger.Ledger;
with ALedger.Report_Config;

package ALedger.Report_Plan is

   type Resolved_Range is record
      From_Date    : Unbounded_String;
      Through_Date : Unbounded_String;
   end record;

   type Resolved_Report_Plan is record
      Trial_Balance_As_Of        : Unbounded_String;
      Balance_Sheet_As_Of        : Unbounded_String;
      Profit_And_Loss            : Resolved_Range;
      Daily_Flow                 : Resolved_Range;
      Monthly_Accounts           : Resolved_Range;
      Recent_Transactions_Through : Unbounded_String;
      Recent_Transactions_Count   : Positive := 5;
   end record;

   type Resolve_Status is
     (Success,
      Invalid_Trial_Balance_Boundary,
      Invalid_Balance_Sheet_Boundary,
      Invalid_Profit_And_Loss_Range,
      Invalid_Daily_Flow_Range,
      Invalid_Monthly_Accounts_Range,
      Invalid_Recent_Transactions_Boundary);

   function Resolve
     (Latest_Date : String;
      L           : Ledger.Ledger;
      Plan        : ALedger.Report_Config.Report_Plan;
      Result      : out Resolved_Report_Plan;
      Status      : out Resolve_Status) return Boolean;

end ALedger.Report_Plan;
