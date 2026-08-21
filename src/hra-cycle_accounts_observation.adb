package body HRA.Cycle_Accounts_Observation is

   use type HRA.Account.Account;
   use type HRA.Dates.Date;
   use type HRA.Money.Quantity;

   type Balance_Lane is (Opening_Lane, Debit_Lane, Credit_Lane);

   function Movement (Row : Account_Row) return Balance is
     (Add_Balance (Row.Debit, Row.Credit));

   function Closing (Row : Account_Row) return Balance is
     (Add_Balance (Row.Opening, Movement (Row)));

   function Opening_Total (Value : Observation) return Balance
   is
      Total : Balance := Empty_Balance;
   begin
      for Row of Value.Rows loop
         Total := Add_Balance (Total, Row.Opening);
      end loop;
      return Total;
   end Opening_Total;

   function Debit_Total (Value : Observation) return Balance
   is
      Total : Balance := Empty_Balance;
   begin
      for Row of Value.Rows loop
         Total := Add_Balance (Total, Row.Debit);
      end loop;
      return Total;
   end Debit_Total;

   function Credit_Total (Value : Observation) return Balance
   is
      Total : Balance := Empty_Balance;
   begin
      for Row of Value.Rows loop
         Total := Add_Balance (Total, Row.Credit);
      end loop;
      return Total;
   end Credit_Total;

   function Movement_Total (Value : Observation) return Balance
   is
      Total : Balance := Empty_Balance;
   begin
      for Row of Value.Rows loop
         Total := Add_Balance (Total, Movement (Row));
      end loop;
      return Total;
   end Movement_Total;

   function Closing_Total (Value : Observation) return Balance
   is
      Total : Balance := Empty_Balance;
   begin
      for Row of Value.Rows loop
         Total := Add_Balance (Total, Closing (Row));
      end loop;
      return Total;
   end Closing_Total;

   function Is_Balanced (Value : Observation) return Boolean is
     (Is_Zero_Balance (Opening_Total (Value))
      and then Is_Zero_Balance (Movement_Total (Value))
      and then Is_Zero_Balance (Closing_Total (Value)));

   function Add_To_Row
     (Rows  : in out Account_Row_Vectors.Vector;
      Acc   : HRA.Account.Account;
      Value : Balance;
      Lane  : Balance_Lane) return Boolean
   is
   begin
      for I in 1 .. Natural (Rows.Length) loop
         if Rows.Element (I).Acc = Acc then
            declare
               Row : Account_Row := Rows.Element (I);
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

   function Observe
     (L                : HRA.Ledger.Ledger;
      Window           : HRA.Cycle_Observation.Cycle_Window;
      Observed_Through : HRA.Dates.Date;
      Result           : out Observation;
      Diag             : out Observe_Diagnostic) return Boolean
   is
      Cycle_Start : constant HRA.Dates.Date :=
        HRA.Cycle_Observation.Start_Date (Window);
   begin
      Result :=
        (Window           => Window,
         Observed_Through => Observed_Through,
         Rows             => Account_Row_Vectors.Empty_Vector);
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
           (Account_Row'
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
   end Observe;

end HRA.Cycle_Accounts_Observation;
