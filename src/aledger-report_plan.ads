with ALedger.Dates;
with ALedger.Ledger;         use ALedger.Ledger;
with ALedger.Report_Config;

package ALedger.Report_Plan is

   type Resolved_Report_Plan is record
      Trial_Balance_As_Of         : ALedger.Dates.Date;
      Balance_Sheet_As_Of         : ALedger.Dates.Date;
      Profit_And_Loss             : ALedger.Dates.Closed_Period;
      Daily_Flow                  : ALedger.Dates.Closed_Period;
      Monthly_Accounts            : ALedger.Dates.Closed_Period;
      Recent_Transactions_Through : ALedger.Dates.Date;
      Recent_Transactions_Count   : Positive := 5;
   end record;

   type Resolve_Status is
     (Success,
      Invalid_Latest_Date,
      Invalid_Trial_Balance_Boundary,
      Invalid_Balance_Sheet_Boundary,
      Current_Cycle_Context_Required,
      Current_Cycle_Observation_Outside_Period,
      Invalid_Profit_And_Loss_Range,
      Invalid_Daily_Flow_Range,
      Invalid_Monthly_Accounts_Range,
      Invalid_Recent_Transactions_Boundary);

   function Needs_Current_Cycle
     (Plan : ALedger.Report_Config.Report_Plan) return Boolean;

   function Resolve
     (Latest_Date : ALedger.Dates.Date;
      L           : Ledger.Ledger;
      Plan        : ALedger.Report_Config.Report_Plan;
      Result      : out Resolved_Report_Plan;
      Status      : out Resolve_Status) return Boolean;

   function Resolve_With_Current_Cycle
     (Latest_Date   : ALedger.Dates.Date;
      L             : Ledger.Ledger;
      Current_Cycle : ALedger.Dates.Half_Open_Period;
      Plan          : ALedger.Report_Config.Report_Plan;
      Result        : out Resolved_Report_Plan;
      Status        : out Resolve_Status) return Boolean;

end ALedger.Report_Plan;
