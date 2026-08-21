with Ada.Containers.Vectors;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA.Account;
with HRA.Cycle_Observation;
with HRA.Dates;
with HRA.Ledger;
with HRA.Money; use HRA.Money;

--  Exact current Account state inside one already-resolved Household cycle.
--
--  This is a semantic observation owner, not a report projection. It consumes
--  one admitted Actual Ledger, one typed cycle window, and one observation day.
--  Account identity/order come from the Ledger's admitted registry; names never
--  classify facts. Report comparison and Daily Target may consume this same
--  observation without rebuilding Actual balance authority.
package HRA.Cycle_Accounts_Observation is

   type Account_Row is record
      Acc     : HRA.Account.Account;
      Opening : Balance := Empty_Balance;
      Debit   : Balance := Empty_Balance;
      Credit  : Balance := Empty_Balance;
   end record;

   function Movement (Row : Account_Row) return Balance;
   function Closing (Row : Account_Row) return Balance;

   package Account_Row_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Account_Row);

   type Observation is record
      Window           : HRA.Cycle_Observation.Cycle_Window;
      Observed_Through : HRA.Dates.Date;
      Rows             : Account_Row_Vectors.Vector;
   end record;

   function Opening_Total (Value : Observation) return Balance;
   function Debit_Total (Value : Observation) return Balance;
   function Credit_Total (Value : Observation) return Balance;
   function Movement_Total (Value : Observation) return Balance;
   function Closing_Total (Value : Observation) return Balance;
   function Is_Balanced (Value : Observation) return Boolean;

   type Observe_Status is
     (Success,
      Observation_Outside_Cycle,
      Undeclared_Account);

   type Observe_Diagnostic is record
      Status       : Observe_Status := Success;
      Account_Name : Unbounded_String := Null_Unbounded_String;
      Message      : Unbounded_String := Null_Unbounded_String;
   end record;

   --  Observe every declared Account, including zero-activity Accounts.
   --
   --  Opening contains all admitted Actual facts before cycle start. Debit and
   --  Credit contain facts from cycle start through Observed_Through inclusive;
   --  Debit retains positive Ledger sign and Credit retains negative Ledger
   --  sign. Movement and Closing are derived, never independently stored.
   function Observe
     (L                : HRA.Ledger.Ledger;
      Window           : HRA.Cycle_Observation.Cycle_Window;
      Observed_Through : HRA.Dates.Date;
      Result           : out Observation;
      Diag             : out Observe_Diagnostic) return Boolean;

end HRA.Cycle_Accounts_Observation;
