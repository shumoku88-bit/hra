with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

package body HRA.Household_Actual_Draft is

   use type HRA.Account.Account;

   function Blank_Posting return Posting_Draft is
     (Account_Text => Null_Unbounded_String,
      Amount_Text  => Null_Unbounded_String);

   function Start (Day : HRA.Dates.Date) return Record_Draft is
      Result : Record_Draft;
   begin
      Result.Day := Day;
      Result.Postings.Append (Blank_Posting);
      Result.Postings.Append (Blank_Posting);
      return Result;
   end Start;

   function Day_Of (Draft : Record_Draft) return HRA.Dates.Date is
     (Draft.Day);

   function Description_Text (Draft : Record_Draft) return String is
     (To_String (Draft.Description));

   function Posting_Count (Draft : Record_Draft) return Natural is
     (Natural (Draft.Postings.Length));

   function Posting_At
     (Draft : Record_Draft;
      Index : Positive) return Posting_Draft is
     (Draft.Postings.Element (Index));

   function Set_Description
     (Draft : Record_Draft;
      Text  : String) return Record_Draft
   is
      Result : Record_Draft := Draft;
   begin
      Result.Description := To_Unbounded_String (Text);
      return Result;
   end Set_Description;

   function Resize_Postings
     (Draft           : Record_Draft;
      Requested_Count : Natural) return Record_Draft
   is
      Result  : Record_Draft := Draft;
      Desired : constant Natural := Natural'Max (2, Requested_Count);
   begin
      while Natural (Result.Postings.Length) < Desired loop
         Result.Postings.Append (Blank_Posting);
      end loop;
      while Natural (Result.Postings.Length) > Desired loop
         Result.Postings.Delete_Last;
      end loop;
      return Result;
   end Resize_Postings;

   function Set_Posting
     (Draft        : Record_Draft;
      Index        : Positive;
      Account_Text : String;
      Amount_Text  : String) return Record_Draft
   is
      Result : Record_Draft := Draft;
   begin
      Result.Postings.Replace_Element
        (Index,
         (Account_Text => To_Unbounded_String (Account_Text),
          Amount_Text  => To_Unbounded_String (Amount_Text)));
      return Result;
   end Set_Posting;

   function Is_Whitespace (C : Character) return Boolean is
     (C = ' ' or else C = ASCII.HT);

   function Trim_Whitespace (Value : String) return String is
      First : Integer;
      Last  : Integer;
   begin
      if Value'Length = 0 then
         return "";
      end if;

      First := Value'First;
      Last  := Value'Last;
      while First <= Last and then Is_Whitespace (Value (First)) loop
         First := First + 1;
      end loop;
      while Last >= First and then Is_Whitespace (Value (Last)) loop
         Last := Last - 1;
      end loop;
      if First > Last then
         return "";
      end if;
      return Value (First .. Last);
   end Trim_Whitespace;

   function Contains_Whitespace (Value : String) return Boolean is
   begin
      for C of Value loop
         if Is_Whitespace (C) then
            return True;
         end if;
      end loop;
      return False;
   end Contains_Whitespace;

   function Build_Transaction
     (State : HRA.Household.Household_State;
      Draft : Record_Draft;
      Tx    : out HRA.Ledger.Transaction;
      Diag  : out Build_Diagnostic) return Boolean
   is
      Posts : HRA.Ledger.Posting_Vectors.Vector;

      procedure Reset_Diagnostic is
      begin
         Diag :=
           (Status           => Success,
            Posting_Index    => 0,
            Account_Status   => HRA.Account.Success,
            Commodity_Status => HRA.Money.Success,
            Ledger_Status    => HRA.Ledger.Success,
            Message          => Null_Unbounded_String);
      end Reset_Diagnostic;

      function Parse_Amount
        (Input         : String;
         Posting_Index : Positive;
         Result        : out HRA.Money.Amount) return Boolean
      is
         Clean            : constant String := Trim_Whitespace (Input);
         Quantity_Value   : HRA.Money.Quantity;
         Commodity_Value  : HRA.Money.Commodity;
         Commodity_Status : HRA.Money.Commodity_Status;
         Split            : Integer;
      begin
         if Clean'Length = 0 then
            Diag.Status := Invalid_Amount_Shape;
            Diag.Posting_Index := Posting_Index;
            Diag.Message := To_Unbounded_String ("posting amount is empty");
            return False;
         end if;

         Split := Clean'First;
         while Split <= Clean'Last
           and then not Is_Whitespace (Clean (Split))
         loop
            Split := Split + 1;
         end loop;

         declare
            Quantity_Text : constant String := Clean (Clean'First .. Split - 1);
         begin
            if not HRA.Money.Parse_Quantity (Quantity_Text, Quantity_Value) then
               Diag.Status := Invalid_Quantity;
               Diag.Posting_Index := Posting_Index;
               Diag.Message := To_Unbounded_String
                 ("posting quantity is not an exact decimal quantity");
               return False;
            end if;
         end;

         if HRA.Money.Is_Zero (Quantity_Value) then
            Diag.Status := Zero_Quantity;
            Diag.Posting_Index := Posting_Index;
            Diag.Message := To_Unbounded_String
              ("posting quantity must not be zero");
            return False;
         end if;

         if Split > Clean'Last then
            if not State.Household_Policy.Has_Primary_Commodity then
               Diag.Status := Missing_Primary_Commodity;
               Diag.Posting_Index := Posting_Index;
               Diag.Message := To_Unbounded_String
                 ("posting omits Commodity but Household has no primary commodity");
               return False;
            end if;
            Commodity_Value := State.Household_Policy.Primary_Commodity;
         else
            declare
               Commodity_Text : constant String :=
                 Trim_Whitespace (Clean (Split .. Clean'Last));
            begin
               if Commodity_Text'Length = 0
                 or else Contains_Whitespace (Commodity_Text)
               then
                  Diag.Status := Invalid_Amount_Shape;
                  Diag.Posting_Index := Posting_Index;
                  Diag.Message := To_Unbounded_String
                    ("posting amount must be QUANTITY or QUANTITY COMMODITY");
                  return False;
               end if;

               if not HRA.Money.Create_Commodity
                 (Commodity_Text, Commodity_Value, Commodity_Status)
               then
                  Diag.Status := Invalid_Commodity;
                  Diag.Posting_Index := Posting_Index;
                  Diag.Commodity_Status := Commodity_Status;
                  Diag.Message := To_Unbounded_String
                    ("posting Commodity is invalid");
                  return False;
               end if;
            end;
         end if;

         Result := HRA.Money.Make_Amount (Commodity_Value, Quantity_Value);
         return True;
      end Parse_Amount;
   begin
      Reset_Diagnostic;

      for Index in 1 .. Posting_Count (Draft) loop
         declare
            Raw          : constant Posting_Draft := Posting_At (Draft, Index);
            Account_Text : constant String :=
              Trim_Whitespace (To_String (Raw.Account_Text));
            Acc          : HRA.Account.Account;
            Acc_Status   : HRA.Account.Account_Status;
            Decl         : HRA.Account.Account_Declaration;
            Amount       : HRA.Money.Amount;
         begin
            if not HRA.Account.Create_Account
              (Account_Text, Acc, Acc_Status)
            then
               Diag.Status := Invalid_Account;
               Diag.Posting_Index := Index;
               Diag.Account_Status := Acc_Status;
               Diag.Message := To_Unbounded_String
                 ("posting Account is invalid");
               return False;
            end if;

            if not HRA.Account.Lookup_Declaration (State.Registry, Acc, Decl)
              or else Decl.Acc /= Acc
            then
               Diag.Status := Undeclared_Account;
               Diag.Posting_Index := Index;
               Diag.Message := To_Unbounded_String
                 ("posting Account is not declared in the admitted Household");
               return False;
            end if;

            if not Parse_Amount
              (To_String (Raw.Amount_Text), Index, Amount)
            then
               return False;
            end if;

            Posts.Append (HRA.Ledger.Make_Posting (Acc, Amount));
         end;
      end loop;

      if not HRA.Ledger.Create_Transaction
        (Draft.Day,
         To_String (Draft.Description),
         Posts,
         Tx,
         Diag.Ledger_Status)
      then
         Diag.Status := Transaction_Rejected;
         Diag.Message := To_Unbounded_String
           ("typed Record draft is not an admissible balanced transaction");
         return False;
      end if;

      return True;
   end Build_Transaction;

end HRA.Household_Actual_Draft;
