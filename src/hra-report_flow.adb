with Ada.Strings;       use Ada.Strings;
with Ada.Strings.Fixed; use Ada.Strings.Fixed;

package body HRA.Report_Flow is

   use type HRA.Account.Account;
   use type HRA.Account.Account_Type;
   use type HRA.Dates.Date;

   function Month_Of (Value : HRA.Dates.Date) return Year_Month is
     (Year  => Year_Number (HRA.Dates.Year (Value)),
      Month => Month_Number (HRA.Dates.Month (Value)));

   function Image (Value : Year_Month) return String is
      Y : constant String := Trim (Positive'Image (Value.Year), Both);
      M : constant String := Trim (Positive'Image (Value.Month), Both);
   begin
      return Y & "-" & (if Value.Month < 10 then "0" else "") & M;
   end Image;

   function Next_Month (Value : Year_Month) return Year_Month is
   begin
      if Value.Month = 12 then
         return (Year => Value.Year + 1, Month => 1);
      else
         return (Year => Value.Year, Month => Value.Month + 1);
      end if;
   end Next_Month;

   function Net (Line : Daily_Flow_Line) return Balance is
     (Subtract_Balance (Line.Income, Line.Expenses));

   function Total_Income (Observation : Daily_Flow_Observation) return Balance is
      Result : Balance := Empty_Balance;
   begin
      for Line of Observation.Lines loop
         Result := Add_Balance (Result, Line.Income);
      end loop;
      return Result;
   end Total_Income;

   function Total_Expenses (Observation : Daily_Flow_Observation) return Balance is
      Result : Balance := Empty_Balance;
   begin
      for Line of Observation.Lines loop
         Result := Add_Balance (Result, Line.Expenses);
      end loop;
      return Result;
   end Total_Expenses;

   function Total_Net (Observation : Daily_Flow_Observation) return Balance is
     (Subtract_Balance
        (Total_Income (Observation), Total_Expenses (Observation)));

   function Balance_For
     (Row   : Monthly_Account_Row;
      Month : Year_Month) return Balance
   is
   begin
      for Cell of Row.Cells loop
         if Cell.Month = Month then
            return Cell.Value;
         end if;
      end loop;
      return Empty_Balance;
   end Balance_For;

   function Row_Total (Row : Monthly_Account_Row) return Balance is
      Result : Balance := Empty_Balance;
   begin
      for Cell of Row.Cells loop
         Result := Add_Balance (Result, Cell.Value);
      end loop;
      return Result;
   end Row_Total;

   function Income_For
     (Observation : Monthly_Accounts_Observation;
      Month       : Year_Month) return Balance
   is
      Result : Balance := Empty_Balance;
   begin
      for Row of Observation.Income_Rows loop
         Result := Add_Balance (Result, Balance_For (Row, Month));
      end loop;
      return Result;
   end Income_For;

   function Expenses_For
     (Observation : Monthly_Accounts_Observation;
      Month       : Year_Month) return Balance
   is
      Result : Balance := Empty_Balance;
   begin
      for Row of Observation.Expense_Rows loop
         Result := Add_Balance (Result, Balance_For (Row, Month));
      end loop;
      return Result;
   end Expenses_For;

   function Net_For
     (Observation : Monthly_Accounts_Observation;
      Month       : Year_Month) return Balance is
     (Subtract_Balance
        (Income_For (Observation, Month), Expenses_For (Observation, Month)));

   procedure Add_Daily_Line_Amount
     (Observation : in out Daily_Flow_Observation;
      Day         : HRA.Dates.Date;
      Kind        : HRA.Account.Account_Type;
      Value       : Balance)
   is
      Index : Natural := 0;
   begin
      for I in 1 .. Natural (Observation.Lines.Length) loop
         if Observation.Lines.Element (I).Day = Day then
            Index := I;
            exit;
         end if;
      end loop;

      if Index = 0 then
         Observation.Lines.Append
           (Daily_Flow_Line'
              (Day      => Day,
               Income   => Empty_Balance,
               Expenses => Empty_Balance));
         Index := Natural (Observation.Lines.Length);
      end if;

      declare
         Line : Daily_Flow_Line := Observation.Lines.Element (Index);
      begin
         case Kind is
            when HRA.Account.Income =>
               Line.Income := Add_Balance (Line.Income, Value);
            when HRA.Account.Expense =>
               Line.Expenses := Add_Balance (Line.Expenses, Value);
            when others =>
               null;
         end case;
         Observation.Lines.Replace_Element (Index, Line);
      end;
   end Add_Daily_Line_Amount;

   procedure Add_Daily_Expense_Cell
     (Rows  : in out Daily_Expense_Row_Vectors.Vector;
      Acc   : HRA.Account.Account;
      Day   : HRA.Dates.Date;
      Value : Balance)
   is
      Row_Index  : Natural := 0;
      Cell_Index : Natural := 0;
   begin
      for I in 1 .. Natural (Rows.Length) loop
         if Rows.Element (I).Acc = Acc then
            Row_Index := I;
            exit;
         end if;
      end loop;

      if Row_Index = 0 then
         return;
      end if;

      declare
         Row : Daily_Expense_Row := Rows.Element (Row_Index);
      begin
         for I in 1 .. Natural (Row.Cells.Length) loop
            if Row.Cells.Element (I).Day = Day then
               Cell_Index := I;
               exit;
            end if;
         end loop;

         if Cell_Index = 0 then
            Row.Cells.Append
              (Daily_Expense_Cell'(Day => Day, Value => Value));
         else
            declare
               Cell : Daily_Expense_Cell := Row.Cells.Element (Cell_Index);
            begin
               Cell.Value := Add_Balance (Cell.Value, Value);
               Row.Cells.Replace_Element (Cell_Index, Cell);
            end;
         end if;
         Rows.Replace_Element (Row_Index, Row);
      end;
   end Add_Daily_Expense_Cell;

   procedure Add_Monthly_Cell
     (Rows  : in out Monthly_Account_Row_Vectors.Vector;
      Acc   : HRA.Account.Account;
      Month : Year_Month;
      Value : Balance)
   is
      Row_Index  : Natural := 0;
      Cell_Index : Natural := 0;
   begin
      for I in 1 .. Natural (Rows.Length) loop
         if Rows.Element (I).Acc = Acc then
            Row_Index := I;
            exit;
         end if;
      end loop;

      if Row_Index = 0 then
         return;
      end if;

      declare
         Row : Monthly_Account_Row := Rows.Element (Row_Index);
      begin
         for I in 1 .. Natural (Row.Cells.Length) loop
            if Row.Cells.Element (I).Month = Month then
               Cell_Index := I;
               exit;
            end if;
         end loop;

         if Cell_Index = 0 then
            Row.Cells.Append
              (Monthly_Account_Cell'(Month => Month, Value => Value));
         else
            declare
               Cell : Monthly_Account_Cell := Row.Cells.Element (Cell_Index);
            begin
               Cell.Value := Add_Balance (Cell.Value, Value);
               Row.Cells.Replace_Element (Cell_Index, Cell);
            end;
         end if;
         Rows.Replace_Element (Row_Index, Row);
      end;
   end Add_Monthly_Cell;

   function Has_Nonzero
     (Cells : Daily_Expense_Cell_Vectors.Vector) return Boolean
   is
   begin
      for Cell of Cells loop
         if not Is_Zero_Balance (Cell.Value) then
            return True;
         end if;
      end loop;
      return False;
   end Has_Nonzero;

   function Has_Nonzero
     (Cells : Monthly_Account_Cell_Vectors.Vector) return Boolean
   is
   begin
      for Cell of Cells loop
         if not Is_Zero_Balance (Cell.Value) then
            return True;
         end if;
      end loop;
      return False;
   end Has_Nonzero;

   procedure Sort_Daily_Lines (Lines : in out Daily_Flow_Line_Vectors.Vector) is
   begin
      if Natural (Lines.Length) < 2 then
         return;
      end if;

      for I in 2 .. Natural (Lines.Length) loop
         declare
            J : Natural := I;
         begin
            while J > 1
              and then Lines.Element (J).Day < Lines.Element (J - 1).Day
            loop
               declare
                  Left  : constant Daily_Flow_Line := Lines.Element (J - 1);
                  Right : constant Daily_Flow_Line := Lines.Element (J);
               begin
                  Lines.Replace_Element (J - 1, Right);
                  Lines.Replace_Element (J, Left);
               end;
               J := J - 1;
            end loop;
         end;
      end loop;
   end Sort_Daily_Lines;

   procedure Sort_Daily_Cells (Rows : in out Daily_Expense_Row_Vectors.Vector) is
   begin
      for Row_Index in 1 .. Natural (Rows.Length) loop
         declare
            Row : Daily_Expense_Row := Rows.Element (Row_Index);
         begin
            if Natural (Row.Cells.Length) > 1 then
               for I in 2 .. Natural (Row.Cells.Length) loop
                  declare
                     J : Natural := I;
                  begin
                     while J > 1
                       and then Row.Cells.Element (J).Day <
                         Row.Cells.Element (J - 1).Day
                     loop
                        declare
                           Left : constant Daily_Expense_Cell :=
                             Row.Cells.Element (J - 1);
                           Right : constant Daily_Expense_Cell :=
                             Row.Cells.Element (J);
                        begin
                           Row.Cells.Replace_Element (J - 1, Right);
                           Row.Cells.Replace_Element (J, Left);
                        end;
                        J := J - 1;
                     end loop;
                  end;
               end loop;
            end if;
            Rows.Replace_Element (Row_Index, Row);
         end;
      end loop;
   end Sort_Daily_Cells;

   function Observe
     (L              : HRA.Ledger.Ledger;
      Daily_Period   : HRA.Dates.Closed_Period;
      Monthly_Period : HRA.Dates.Closed_Period;
      Daily          : out Daily_Flow_Observation;
      Monthly        : out Monthly_Accounts_Observation;
      Diag           : out Observe_Diagnostic) return Boolean
   is
   begin
      Daily :=
        (Period       => Daily_Period,
         Lines        => Daily_Flow_Line_Vectors.Empty_Vector,
         Expense_Rows => Daily_Expense_Row_Vectors.Empty_Vector);
      Monthly :=
        (Period       => Monthly_Period,
         Months       => Year_Month_Vectors.Empty_Vector,
         Income_Rows  => Monthly_Account_Row_Vectors.Empty_Vector,
         Expense_Rows => Monthly_Account_Row_Vectors.Empty_Vector);
      Diag :=
        (Status       => Success,
         Account_Name => Null_Unbounded_String,
         Message      => Null_Unbounded_String);

      --  Account row order is admitted declaration order, never map key order
      --  and never first-activity order.
      for Decl of HRA.Account.Declarations (L.Registry) loop
         case Decl.Acc_Type is
            when HRA.Account.Income =>
               Monthly.Income_Rows.Append
                 (Monthly_Account_Row'
                    (Acc   => Decl.Acc,
                     Cells => Monthly_Account_Cell_Vectors.Empty_Vector));
            when HRA.Account.Expense =>
               Daily.Expense_Rows.Append
                 (Daily_Expense_Row'
                    (Acc   => Decl.Acc,
                     Cells => Daily_Expense_Cell_Vectors.Empty_Vector));
               Monthly.Expense_Rows.Append
                 (Monthly_Account_Row'
                    (Acc   => Decl.Acc,
                     Cells => Monthly_Account_Cell_Vectors.Empty_Vector));
            when others =>
               null;
         end case;
      end loop;

      --  A month is a time coordinate, not evidence of activity. Preserve every
      --  calendar month touched by the configured period, including zero-flow
      --  and partial boundary months.
      declare
         Cursor : Year_Month := Month_Of (HRA.Dates.First (Monthly_Period));
         Last   : constant Year_Month :=
           Month_Of (HRA.Dates.Last (Monthly_Period));
      begin
         loop
            Monthly.Months.Append (Cursor);
            exit when Cursor = Last;
            Cursor := Next_Month (Cursor);
         end loop;
      end;

      for Tx of L.Transactions loop
         declare
            In_Daily   : constant Boolean :=
              HRA.Dates.Contains (Daily_Period, Tx.Date);
            In_Monthly : constant Boolean :=
              HRA.Dates.Contains (Monthly_Period, Tx.Date);
         begin
            if In_Daily or else In_Monthly then
               for P of Tx.Postings loop
                  declare
                     Category : HRA.Account.Account_Type;
                     Raw      : constant Balance := Singleton_Balance (P.Amt);
                     Value    : Balance := Raw;
                  begin
                     if not HRA.Account.Account_Type_For
                       (L.Registry, P.Acc, Category)
                     then
                        Diag :=
                          (Status       => Undeclared_Account,
                           Account_Name => To_Unbounded_String
                             (HRA.Account.Name (P.Acc)),
                           Message      => To_Unbounded_String
                             ("flow report encountered an undeclared Account"));
                        return False;
                     end if;

                     if Category = HRA.Account.Income then
                        Value := Negate_Balance (Raw);
                     end if;

                     if Category in HRA.Account.Income | HRA.Account.Expense then
                        if In_Daily then
                           Add_Daily_Line_Amount
                             (Daily, Tx.Date, Category, Value);
                           if Category = HRA.Account.Expense then
                              Add_Daily_Expense_Cell
                                (Daily.Expense_Rows,
                                 P.Acc,
                                 Tx.Date,
                                 Value);
                           end if;
                        end if;

                        if In_Monthly then
                           if Category = HRA.Account.Income then
                              Add_Monthly_Cell
                                (Monthly.Income_Rows,
                                 P.Acc,
                                 Month_Of (Tx.Date),
                                 Value);
                           else
                              Add_Monthly_Cell
                                (Monthly.Expense_Rows,
                                 P.Acc,
                                 Month_Of (Tx.Date),
                                 Value);
                           end if;
                        end if;
                     end if;
                  end;
               end loop;
            end if;
         end;
      end loop;

      Sort_Daily_Lines (Daily.Lines);
      Sort_Daily_Cells (Daily.Expense_Rows);

      declare
         Kept_Daily   : Daily_Expense_Row_Vectors.Vector;
         Kept_Income  : Monthly_Account_Row_Vectors.Vector;
         Kept_Expense : Monthly_Account_Row_Vectors.Vector;
      begin
         for Row of Daily.Expense_Rows loop
            if Has_Nonzero (Row.Cells) then
               Kept_Daily.Append (Row);
            end if;
         end loop;
         for Row of Monthly.Income_Rows loop
            if Has_Nonzero (Row.Cells) then
               Kept_Income.Append (Row);
            end if;
         end loop;
         for Row of Monthly.Expense_Rows loop
            if Has_Nonzero (Row.Cells) then
               Kept_Expense.Append (Row);
            end if;
         end loop;

         Daily.Expense_Rows := Kept_Daily;
         Monthly.Income_Rows := Kept_Income;
         Monthly.Expense_Rows := Kept_Expense;
      end;

      return True;
   end Observe;

end HRA.Report_Flow;
