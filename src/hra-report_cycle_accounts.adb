with HRA.Dates;

package body HRA.Report_Cycle_Accounts is

   use type HRA.Account.Account;
   use type HRA.Dates.Date;

   function Difference (Row : Comparison_Row) return Balance is
     (Subtract_Balance (Row.Current_Movement, Row.Baseline_Movement));

   function Current_Total
     (Observation : Cycle_Comparison_Observation) return Balance
   is
      Total : Balance := Empty_Balance;
   begin
      for Row of Observation.Rows loop
         Total := Add_Balance (Total, Row.Current_Movement);
      end loop;
      return Total;
   end Current_Total;

   function Baseline_Total
     (Observation : Cycle_Comparison_Observation) return Balance
   is
      Total : Balance := Empty_Balance;
   begin
      for Row of Observation.Rows loop
         Total := Add_Balance (Total, Row.Baseline_Movement);
      end loop;
      return Total;
   end Baseline_Total;

   function Difference_Total
     (Observation : Cycle_Comparison_Observation) return Balance
   is
      Total : Balance := Empty_Balance;
   begin
      for Row of Observation.Rows loop
         Total := Add_Balance (Total, Difference (Row));
      end loop;
      return Total;
   end Difference_Total;

   function Is_Balanced
     (Observation : Cycle_Comparison_Observation) return Boolean is
     (Is_Zero_Balance (Current_Total (Observation))
      and then Is_Zero_Balance (Baseline_Total (Observation))
      and then Is_Zero_Balance (Difference_Total (Observation)));

   function Observe_Aligned
     (L               : HRA.Ledger.Ledger;
      Baseline_Window : HRA.Cycle_Observation.Cycle_Window;
      Current         : HRA.Cycle_Accounts_Observation.Observation;
      Result          : out Cycle_Comparison_Observation;
      Diag            : out Comparison_Diagnostic) return Boolean
   is
      Baseline_Through : HRA.Dates.Date;
      Baseline         : HRA.Cycle_Accounts_Observation.Observation;
      Current_Diag     : HRA.Cycle_Accounts_Observation.Observe_Diagnostic;
   begin
      Diag :=
        (Status       => Comparison_Success,
         Account_Name => Null_Unbounded_String,
         Message      => Null_Unbounded_String);

      if not HRA.Cycle_Observation.Contains
        (Current.Window, Current.Observed_Through)
      then
         Diag.Status := Current_Observation_Outside_Cycle;
         Diag.Message := To_Unbounded_String
           ("current Cycle Accounts observation is outside its cycle");
         return False;
      end if;

      Baseline_Through := HRA.Cycle_Observation.Aligned_Day
        (Current.Observed_Through, Current.Window, Baseline_Window);
      if not HRA.Cycle_Observation.Contains
        (Baseline_Window, Baseline_Through)
      then
         Diag.Status := Baseline_Elapsed_Outside_Cycle;
         Diag.Message := To_Unbounded_String
           ("previous cycle does not contain the aligned elapsed day");
         return False;
      end if;

      if not HRA.Cycle_Accounts_Observation.Observe
        (L, Baseline_Window, Baseline_Through, Baseline, Current_Diag)
      then
         Diag.Status := Baseline_Observation_Unavailable;
         Diag.Account_Name := Current_Diag.Account_Name;
         Diag.Message := Current_Diag.Message;
         return False;
      end if;

      if Natural (Current.Rows.Length) /= Natural (Baseline.Rows.Length) then
         Diag.Status := Account_Axis_Mismatch;
         Diag.Message := To_Unbounded_String
           ("current and baseline Account axes have different lengths");
         return False;
      end if;

      Result :=
        (Policy   => Aligned_Elapsed,
         Current  => Current,
         Baseline => Baseline,
         Rows     => Comparison_Row_Vectors.Empty_Vector);

      for I in 1 .. Natural (Current.Rows.Length) loop
         declare
            Current_Row  : constant HRA.Cycle_Accounts_Observation.Account_Row :=
              Current.Rows.Element (I);
            Baseline_Row : constant HRA.Cycle_Accounts_Observation.Account_Row :=
              Baseline.Rows.Element (I);
         begin
            if Current_Row.Acc /= Baseline_Row.Acc then
               Diag.Status := Account_Axis_Mismatch;
               Diag.Account_Name := To_Unbounded_String
                 (HRA.Account.Name (Current_Row.Acc));
               Diag.Message := To_Unbounded_String
                 ("current and baseline Account identities are not aligned");
               return False;
            end if;

            Result.Rows.Append
              (Comparison_Row'
                 (Acc               => Current_Row.Acc,
                  Current_Movement  =>
                    HRA.Cycle_Accounts_Observation.Movement (Current_Row),
                  Baseline_Movement =>
                    HRA.Cycle_Accounts_Observation.Movement (Baseline_Row)));
         end;
      end loop;

      return True;
   end Observe_Aligned;

end HRA.Report_Cycle_Accounts;
