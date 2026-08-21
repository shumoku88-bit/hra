with Ada.Containers.Vectors;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA.Account;
with HRA.Cycle_Observation;
with HRA.Dates;
with HRA.Ledger;
with HRA.Money; use HRA.Money;

--  Exact Account state inside one admitted Household cycle, plus an explicit
--  comparison with the immediately previous cycle at the same elapsed day.
--
--  Cycle resolution remains outside this package. This owner receives typed
--  cycle windows, one admitted Actual Ledger, and an observation day. Account
--  identity/order come from the admitted registry; names never classify facts.
package HRA.Report_Cycle_Accounts is

   type Current_Account_Row is record
      Acc     : HRA.Account.Account;
      Opening : Balance := Empty_Balance;
      Debit   : Balance := Empty_Balance;
      Credit  : Balance := Empty_Balance;
   end record;

   function Movement (Row : Current_Account_Row) return Balance;
   function Closing (Row : Current_Account_Row) return Balance;

   package Current_Account_Row_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Current_Account_Row);

   type Current_Cycle_Accounts_Observation is record
      Window           : HRA.Cycle_Observation.Cycle_Window;
      Observed_Through : HRA.Dates.Date;
      Rows             : Current_Account_Row_Vectors.Vector;
   end record;

   function Opening_Total
     (Observation : Current_Cycle_Accounts_Observation) return Balance;
   function Debit_Total
     (Observation : Current_Cycle_Accounts_Observation) return Balance;
   function Credit_Total
     (Observation : Current_Cycle_Accounts_Observation) return Balance;
   function Movement_Total
     (Observation : Current_Cycle_Accounts_Observation) return Balance;
   function Closing_Total
     (Observation : Current_Cycle_Accounts_Observation) return Balance;
   function Is_Balanced
     (Observation : Current_Cycle_Accounts_Observation) return Boolean;

   type Current_Observe_Status is
     (Success,
      Observation_Outside_Cycle,
      Undeclared_Account);

   type Current_Observe_Diagnostic is record
      Status       : Current_Observe_Status := Success;
      Account_Name : Unbounded_String := Null_Unbounded_String;
      Message      : Unbounded_String := Null_Unbounded_String;
   end record;

   --  Observe every declared Account, including zero-activity Accounts.
   --
   --  Opening contains all admitted Actual facts before cycle start. Debit and
   --  Credit contain facts from cycle start through Observed_Through inclusive;
   --  Debit retains positive Ledger sign and Credit retains negative Ledger
   --  sign. Movement and Closing are derived, never independently stored.
   function Observe_Current
     (L                : HRA.Ledger.Ledger;
      Window           : HRA.Cycle_Observation.Cycle_Window;
      Observed_Through : HRA.Dates.Date;
      Result           : out Current_Cycle_Accounts_Observation;
      Diag             : out Current_Observe_Diagnostic) return Boolean;

   type Comparison_Policy is (Aligned_Elapsed);

   type Comparison_Row is record
      Acc               : HRA.Account.Account;
      Current_Movement  : Balance := Empty_Balance;
      Baseline_Movement : Balance := Empty_Balance;
   end record;

   function Difference (Row : Comparison_Row) return Balance;

   package Comparison_Row_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Comparison_Row);

   type Cycle_Comparison_Observation is record
      Policy   : Comparison_Policy := Aligned_Elapsed;
      Current  : Current_Cycle_Accounts_Observation;
      Baseline : Current_Cycle_Accounts_Observation;
      Rows     : Comparison_Row_Vectors.Vector;
   end record;

   function Current_Total
     (Observation : Cycle_Comparison_Observation) return Balance;
   function Baseline_Total
     (Observation : Cycle_Comparison_Observation) return Balance;
   function Difference_Total
     (Observation : Cycle_Comparison_Observation) return Balance;
   function Is_Balanced
     (Observation : Cycle_Comparison_Observation) return Boolean;

   type Comparison_Status is
     (Comparison_Success,
      Current_Observation_Outside_Cycle,
      Baseline_Elapsed_Outside_Cycle,
      Baseline_Observation_Unavailable,
      Account_Axis_Mismatch);

   type Comparison_Diagnostic is record
      Status       : Comparison_Status := Comparison_Success;
      Account_Name : Unbounded_String := Null_Unbounded_String;
      Message      : Unbounded_String := Null_Unbounded_String;
   end record;

   --  Compare movement with the previous cycle at the same elapsed day count.
   --  The baseline date is derived only from the two explicit typed windows and
   --  Current.Observed_Through. It is never inferred from journal activity.
   function Observe_Aligned
     (L               : HRA.Ledger.Ledger;
      Baseline_Window : HRA.Cycle_Observation.Cycle_Window;
      Current         : Current_Cycle_Accounts_Observation;
      Result          : out Cycle_Comparison_Observation;
      Diag            : out Comparison_Diagnostic) return Boolean;

end HRA.Report_Cycle_Accounts;
