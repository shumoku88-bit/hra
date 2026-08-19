with HRA.Account;
with HRA.Dates;
with HRA.Ledger;
with HRA.Money;

--  Read-only comparison between one externally observed Account balance and the
--  canonical Actual Ledger at the same day.
--
--  External observations are evidence for reconciliation only. They are not
--  Journal facts, do not mutate canonical Actual, and carry no writer authority.
package HRA.Account_Reconciliation is

   type External_Balance_Observation is private;

   function Observe_External_Balance
     (Acc         : HRA.Account.Account;
      Observed_On : HRA.Dates.Date;
      Value       : HRA.Money.Balance) return External_Balance_Observation;

   function Account_Of
     (Observation : External_Balance_Observation) return HRA.Account.Account;

   function Observed_On
     (Observation : External_Balance_Observation) return HRA.Dates.Date;

   function Value_Of
     (Observation : External_Balance_Observation) return HRA.Money.Balance;

   type Reconciliation is private;

   --  Compare the external observation with the canonical ledger balance as of
   --  the same inclusive day. Difference is deliberately external - ledger.
   --  Positive coordinates mean the external source contains more than the
   --  canonical ledger for that Commodity; negative coordinates mean less.
   function Reconcile
     (Actual_Ledger : HRA.Ledger.Ledger;
      External      : External_Balance_Observation) return Reconciliation;

   function External_Observation
     (Result : Reconciliation) return External_Balance_Observation;

   function Ledger_Balance
     (Result : Reconciliation) return HRA.Money.Balance;

   function Difference
     (Result : Reconciliation) return HRA.Money.Balance;

   function Matches (Result : Reconciliation) return Boolean;

private

   type External_Balance_Observation is record
      Acc         : HRA.Account.Account;
      Observed_On : HRA.Dates.Date;
      Value       : HRA.Money.Balance;
   end record;

   type Reconciliation is record
      External : External_Balance_Observation;
      Ledger   : HRA.Money.Balance;
      Delta    : HRA.Money.Balance;
   end record;

end HRA.Account_Reconciliation;
