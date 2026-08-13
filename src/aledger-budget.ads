with Ada.Containers.Indefinite_Vectors;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with ALedger.Money;         use ALedger.Money;
with ALedger.Account;       use ALedger.Account;
with ALedger.Ledger;        use ALedger.Ledger;

package ALedger.Budget is

   --  ========================================================================
   --  Canonical Cycle-Bounded Envelope & Backing Engine (h-kernel Spec)
   --  ========================================================================

   type Budget_Envelope is record
      Acc          : Account.Account;
      Entitlement  : Balance;  --  Allocated inside current cycle
      Consumption  : Balance;  --  Actual expenses inside current cycle
      Refunds      : Balance;  --  Refunds/reimbursements inside current cycle
      Plan_Reserve : Balance;  --  Unexecuted plan reservations inside current cycle
   end record;

   function Remaining (Env : Budget_Envelope) return Balance;
   function Headroom (Env : Budget_Envelope) return Balance;

   package Envelope_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Budget_Envelope);

   type Unenveloped_Expense_Line is record
      Acc      : Account.Account;
      Movement : Balance;
   end record;

   package Unenveloped_Expense_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Unenveloped_Expense_Line);

   type Budget_Status_Report is record
      Cycle_Start_Date   : Unbounded_String;
      Cycle_End_Date     : Unbounded_String;
      Observation_Date   : Unbounded_String;
      Envelopes          : Envelope_Vectors.Vector;
      Unenveloped_Expenses : Unenveloped_Expense_Vectors.Vector;
      Total_Entitlement  : Balance;
      Total_Consumption  : Balance;
      Total_Refunds      : Balance;
      Total_Remaining    : Balance;
      Total_Plan_Reserve : Balance;
      Total_Headroom     : Balance;
      Funding_Balance    : Balance;
      Backing_Required   : Balance;
      Backing_Surplus    : Balance;
      Reconciliation_Delta : Balance;
      Is_Under_Backed    : Boolean;
   end record;

   function Generate_Budget_Status (L : Ledger.Ledger) return Budget_Status_Report;

   function Generate_Cycle_Budget_Status
     (L                : Ledger.Ledger;
      Cycle_Start_Date : String;
      Cycle_End_Date   : String;
      Observation_Date : String) return Budget_Status_Report;

end ALedger.Budget;
