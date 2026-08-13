with Ada.Containers.Indefinite_Vectors;
with ALedger.Money;   use ALedger.Money;
with ALedger.Account; use ALedger.Account;
with ALedger.Ledger;  use ALedger.Ledger;

package ALedger.Budget is

   --  ========================================================================
   --  Budget Envelope and Consumption Status
   --  ========================================================================

   type Budget_Envelope is record
      Acc         : Account.Account;
      Entitlement : Balance;  --  Total budget allocated
      Consumption : Balance;  --  Total budget consumed/spent
   end record;

   function Remaining (Env : Budget_Envelope) return Balance;

   package Envelope_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Budget_Envelope);

   type Budget_Status_Report is record
      Envelopes         : Envelope_Vectors.Vector;
      Total_Entitlement : Balance;
      Total_Consumption : Balance;
      Total_Remaining   : Balance;
   end record;

   function Generate_Budget_Status (L : Ledger.Ledger) return Budget_Status_Report;

end ALedger.Budget;
