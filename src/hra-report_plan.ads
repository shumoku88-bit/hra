with HRA.Dates;
with HRA.Ledger;         use HRA.Ledger;
with HRA.Report_Config;

package HRA.Report_Plan is

   type Resolved_Report_Plan is record
      Trial_Balance_As_Of         : HRA.Dates.Date;
      Balance_Sheet_As_Of         : HRA.Dates.Date;
      Profit_And_Loss             : HRA.Dates.Closed_Period;
      Daily_Flow                  : HRA.Dates.Closed_Period;
      Monthly_Accounts            : HRA.Dates.Closed_Period;
      Recent_Transactions_Through : HRA.Dates.Date;
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
     (Plan : HRA.Report_Config.Report_Plan) return Boolean;

   function Resolve
     (Latest_Date : HRA.Dates.Date;
      L           : Ledger.Ledger;
      Plan        : HRA.Report_Config.Report_Plan;
      Result      : out Resolved_Report_Plan;
      Status      : out Resolve_Status) return Boolean;

   function Resolve_With_Current_Cycle
     (Latest_Date   : HRA.Dates.Date;
      L             : Ledger.Ledger;
      Current_Cycle : HRA.Dates.Half_Open_Period;
      Plan          : HRA.Report_Config.Report_Plan;
      Result        : out Resolved_Report_Plan;
      Status        : out Resolve_Status) return Boolean;

end HRA.Report_Plan;
