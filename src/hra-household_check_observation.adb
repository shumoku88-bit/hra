with HRA.Account;
with HRA.Issues;
with HRA.Entitlement_Journal;

package body HRA.Household_Check_Observation is

   function Observe
     (State : HRA.Household.Household_State)
      return Observation
   is
   begin
      return Observation'
        (Actual_Transactions   =>
           Natural (State.Actual_Ledger.Transactions.Length),
         Plan_Transactions     =>
           Natural (State.Plan_Ledger.Transactions.Length),
         Entitlement_Movements =>
           HRA.Entitlement_Journal.Movement_Count (State.Entitlement_History),
         Registered_Accounts   =>
           HRA.Account.Declarations (State.Registry)'Length,
         Open_Issues           =>
           HRA.Issues.Count (HRA.Issues.Open_Issues (State.Issues)));
   end Observe;

end HRA.Household_Check_Observation;
