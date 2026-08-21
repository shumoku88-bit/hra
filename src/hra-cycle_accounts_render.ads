with HRA.Report_Cycle_Accounts;

--  Pure text publication for one already typed Cycle Accounts report.
--  No Ledger, Household_State, cycle resolution, or source bytes cross here.
package HRA.Cycle_Accounts_Render is

   function Render
     (Value : HRA.Report_Cycle_Accounts.Report_Observation) return String;

end HRA.Cycle_Accounts_Render;
