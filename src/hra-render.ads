with HRA.Household_Report_Observation;

package HRA.Render is

   function Render_Account_Balances
     (Value :
        HRA.Household_Report_Observation.Account_Balances_Report_Observation)
      return String;

   function Render_Balance_Sheet
     (Value : HRA.Household_Report_Observation.Balance_Sheet_Report_Observation)
      return String;

   function Render_Profit_And_Loss
     (Value :
        HRA.Household_Report_Observation.Profit_And_Loss_Report_Observation)
      return String;

   function Render_Household_Issues
     (Value : HRA.Household_Report_Observation.Issues_Report_Observation)
      return String;

end HRA.Render;
