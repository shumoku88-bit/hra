with Ada.Containers.Vectors;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA.Account;
with HRA.Cycle_Accounts_Observation;
with HRA.Cycle_Observation;
with HRA.Ledger;
with HRA.Money; use HRA.Money;

--  Report-specific comparison over neutral current Cycle Account observations.
--
--  Exact current Account state is owned by HRA.Cycle_Accounts_Observation.
--  This package owns only the aligned comparison with the immediately previous
--  cycle and the section-level availability of that narrower projection.
package HRA.Report_Cycle_Accounts is

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
      Current  : HRA.Cycle_Accounts_Observation.Observation;
      Baseline : HRA.Cycle_Accounts_Observation.Observation;
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
      Current         : HRA.Cycle_Accounts_Observation.Observation;
      Result          : out Cycle_Comparison_Observation;
      Diag            : out Comparison_Diagnostic) return Boolean;

   --  Current-cycle Account state is structurally required by the report book.
   --  The aligned historical comparison is narrower: a short previous cycle may
   --  make only this projection unavailable without erasing the current state.
   type Comparison_Availability is
     (Comparison_Available, Comparison_Unavailable);

   type Comparison_View
     (Status : Comparison_Availability := Comparison_Unavailable) is record
      case Status is
         when Comparison_Available =>
            Value : Cycle_Comparison_Observation;
         when Comparison_Unavailable =>
            Diagnostic : Comparison_Diagnostic;
      end case;
   end record;

   type Report_Observation is record
      Current    : HRA.Cycle_Accounts_Observation.Observation;
      Comparison : Comparison_View;
   end record;

end HRA.Report_Cycle_Accounts;
