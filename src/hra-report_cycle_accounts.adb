package body HRA.Report_Cycle_Accounts is

   use type HRA.Account.Account;
   use type HRA.Dates.Date;
   use type HRA.Money.Quantity;

   type Balance_Lane is (Opening_Lane, Debit_Lane, Credit_Lane);

   function Movement (Row : Current_Account_Row) return Balance is
     (Add_Balance (Row.Debit, Row.Credit));

   function Closing (Row : Current_Account_Row) return Balance is
     (Add_Balance (Row.Opening, Movement (Row)));

   function Opening_Total
     (Observation : Current_Cycle_Accounts_Observation) return Balance
   is
      Total : Balance := Empty_Balance;
   begin
      for Row of Observation.Rows loop
         Total := Add_Balance (Total, Row.Opening);
      end loop;
      return Total;
   end Opening_Total;

   function Debit_Total
     (Observation : Current_Cycle_Accounts_Observation) return Balance
   is
      Total : Balance := Empty_Balance;
   begin
      for Row of Observation.Rows loop
         Total := Add_Balance (Total, Row.Debit);
      end loop;
      return Total;
   end Debit_Total;

   function Credit_Total
     (Observation : Current_Cycle_Accounts_Observation) return Balance
   is
      Total : Balance := Empty_Balance;
   begin
      for Row of Observation.Rows loop
         Total := Add_Balance (Total, Row.Credit);
      end loop;
      return Total;
   end Credit_Total;

   function Movement_Total
     (Observation : Current_Cycle_Accounts_Observation) return Balance
   is
      Total : Balance := Empty_Balance;
   begin
      for Row of Observation.Rows loop
         Total := Add_Balance (Total, Movement (Row));
      end loop;
      return Total;
   end Movement_Total;

   function Closing_Total
     (Observation : Current_Cycle_Accounts_Observation) return Balance
   is
      Total : Balance := Empty_Balance;
   begin
      for Row of Observation.Rows loop
         Total := Add_Balance (Total, Closing (Row));
      end loop;
      return Total;
   end Closing_Total;

   function Is_Balanced
     (Observation : Current_Cycle_Accounts_Observation) return Boolean is
     (Is_Zero_Balance (Opening_Total (Observation))
      and then Is_Zero_Balance (Movement_Total (Observation))
      and then Is_Zero_Balance (Closing_Total (Observation)));

   function Add_To_Row
     (Rows  : in out Current_Account_Row_Vectors.Vector;
      Acc   : HRA.Account.Account;
      Value : Balance;
      Lane  : Balance_Lane) return Boolean
   is
   begin
      for I in 1 .. Natural (Rows.Length) loop
         if Rows.Element (I).Acc = Acc then
            declare
               Row : Current_Account_Row := Rows.Element (I);
            begin
               case Lane is
                  when Opening_Lane =>
                     Row.Opening := Add_Balance (Row.Opening, Value);
                  when Debit_Lane =>
                     Row.Debit := Add_Balance (Row.Debit, Value);
                  when Credit_Lane =>
                     Row.Credit := Add_Balance (Row.Credit, Value);
               end case;
               Rows.Replace_Element (I, Row);
               return True;
            end;
         end if;
      end loop;
      return False;
   end Add_To_Row;

   function Observe_Current
     (L                : HRA.Ledger.Ledger;
      Window           : HRA.Cycle_Observation.Cycle_Window;
      Observed_Through : HRA.Dates.Date;
      Result           : out Current_Cycle_Accounts_Observation;
      Diag             : out Current_Observe_Diagnostic) return Boolean
   is
      Cycle_Start : constant HRA.Dates.Date :=
        HRA.Cycle_Observation.Start_Date (Window);
   begin
      Result :=
        (Window           => Window,
         Observed_Through => Observed_Through,
         Rows             => Current_Account_Row_Vectors.Empty_Vector);
      Diag :=
        (Status       => Success,
         Account_Name => Null_Unbounded_String,
         Message      => Null_Unbounded_String);

      if not HRA.Cycle_Observation.Contains (Window, Observed_Through) then
         Diag :=
           (Status       => Observation_Outside_Cycle,
            Account_Name => Null_Unbounded_String,
            Message      => To_Unbounded_String
              ("Cycle Accounts observation is outside the supplied cycle"));
         return False;
      end if;

      for Decl of HRA.Account.Declarations (L.Registry) loop
         Result.Rows.Append
           (Current_Account_Row'
              (Acc     => Decl.Acc,
               Opening => Empty_Balance,
               Debit   => Empty_Balance,
               Credit  => Empty_Balance));
      end loop;

      for Tx of L.Transactions loop
         if Tx.Date < Cycle_Start or else Tx.Date <= Observed_Through then
            for P of Tx.Postings loop
               declare
                  Raw         : constant Balance := Singleton_Balance (P.Amt);
                  Lane        : Balance_Lane;
                  Use_Posting : Boolean := True;
               begin
                  if Tx.Date < Cycle_Start then
                     Lane := Opening_Lane;
                  elsif P.Amt.Val > Zero_Quantity then
                     Lane := Debit_Lane;
                  elsif P.Amt.Val < Zero_Quantity then
                     Lane := Credit_Lane;
                  else
                     Lane := Debit_Lane;
                     Use_Posting := False;
                  end if;

                  if Use_Posting
                    and then not Add_To_Row (Result.Rows, P.Acc, Raw, Lane)
                  then
                     Diag :=
                       (Status       => Undeclared_Account,
                        Account_Name => To_Unbounded_String
                          (HRA.Account.Name (P.Acc)),
                        Message      => To_Unbounded_String
                          ("Cycle Accounts encountered an undeclared Account"));
                     return False;
                  end if;
               end;
            end loop;
         end if;
      end loop;

      return True;
   end Observe_Current;

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
      Current         : Current_Cycle_Accounts_Observation;
      Result          : out Cycle_Comparison_Observation;
      Diag            : out Comparison_Diagnostic) return Boolean
   is
      Baseline_Through : HRA.Dates.Date;
      Baseline         : Current_Cycle_Accounts_Observation;
      Current_Diag     : Current_Observe_Diagnostic;
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

      if not Observe_Current
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
            Current_Row  : constant Current_Account_Row :=
              Current.Rows.Element (I);
            Baseline_Row : constant Current_Account_Row :=
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
                  Current_Movement  => Movement (Current_Row),
                  Baseline_Movement => Movement (Baseline_Row)));
         end;
      end loop;

      return True;
   end Observe_Aligned;

end HRA.Report_Cycle_Accounts;