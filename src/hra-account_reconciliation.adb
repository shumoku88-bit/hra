with HRA.Ledger;

package body HRA.Account_Reconciliation is

   function Observe_External_Balance
     (Acc         : HRA.Account.Account;
      Observed_On : HRA.Dates.Date;
      Value       : HRA.Money.Balance) return External_Balance_Observation
   is
   begin
      return
        (Acc         => Acc,
         Observed_On => Observed_On,
         Value       => Value);
   end Observe_External_Balance;

   function Account_Of
     (Observation : External_Balance_Observation) return HRA.Account.Account
   is (Observation.Acc);

   function Observed_On
     (Observation : External_Balance_Observation) return HRA.Dates.Date
   is (Observation.Observed_On);

   function Value_Of
     (Observation : External_Balance_Observation) return HRA.Money.Balance
   is (Observation.Value);

   function Reconcile
     (Actual   : HRA.Actual_Admission.Actual_Observation;
      External : External_Balance_Observation) return Reconciliation
   is
      Canonical : constant HRA.Money.Balance :=
        HRA.Ledger.Compute_Account_Balance_Through
          (Actual.Value,
           External.Acc,
           External.Observed_On);
   begin
      return
        (External         => External,
         Ledger           => Canonical,
         Difference_Value => HRA.Money.Subtract_Balance
           (External.Value, Canonical));
   end Reconcile;

   function External_Observation
     (Result : Reconciliation) return External_Balance_Observation
   is (Result.External);

   function Ledger_Balance
     (Result : Reconciliation) return HRA.Money.Balance
   is (Result.Ledger);

   function Difference
     (Result : Reconciliation) return HRA.Money.Balance
   is (Result.Difference_Value);

   function Matches (Result : Reconciliation) return Boolean is
     (HRA.Money.Is_Zero_Balance (Result.Difference_Value));

end HRA.Account_Reconciliation;
