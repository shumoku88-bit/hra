with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with ALedger.Account;
with ALedger.Money;

package body ALedger.Cycle_Observation is

   use type ALedger.Account.Account;
   use type ALedger.Account.Account_Type;
   use type ALedger.Money.Quantity;

   function Valid_Date (Text : String) return Boolean is
      Year, Month, Day, Max_Day : Natural;
      function Is_Leap (Y : Positive) return Boolean is
        (Y mod 400 = 0 or else (Y mod 4 = 0 and then Y mod 100 /= 0));
   begin
      if Text'Length /= 10
        or else Text (Text'First + 4) /= '-'
        or else Text (Text'First + 7) /= '-'
      then
         return False;
      end if;
      for Offset in 0 .. 9 loop
         if Offset /= 4 and then Offset /= 7
           and then Text (Text'First + Offset) not in '0' .. '9'
         then
            return False;
         end if;
      end loop;
      Year  := Natural'Value (Text (Text'First .. Text'First + 3));
      Month := Natural'Value (Text (Text'First + 5 .. Text'First + 6));
      Day   := Natural'Value (Text (Text'First + 8 .. Text'First + 9));
      if Year = 0 or else Month not in 1 .. 12 then
         return False;
      end if;
      Max_Day :=
        (case Month is
            when 2 => (if Is_Leap (Year) then 29 else 28),
            when 4 | 6 | 9 | 11 => 30,
            when others => 31);
      return Day in 1 .. Max_Day;
   exception
      when Constraint_Error => return False;
   end Valid_Date;

   function Is_Incoming_Anchor
     (P              : ALedger.Plan_Observation.Open_Plan;
      Registry       : ALedger.Account.Account_Registry;
      Income_Account : ALedger.Account.Account) return Boolean
   is
      Has_Income : Boolean := False;
      Has_Asset  : Boolean := False;
   begin
      for Posting of P.Tx.Postings loop
         declare
            Category : ALedger.Account.Account_Type;
            Known    : constant Boolean :=
              ALedger.Account.Account_Type_For
                (Registry, Posting.Acc, Category);
         begin
            if not Known then
               return False;
            elsif Category = ALedger.Account.Income
              and then Posting.Acc = Income_Account
              and then Posting.Amt.Val < 0.0
            then
               Has_Income := True;
            elsif Category = ALedger.Account.Asset
              and then Posting.Amt.Val > 0.0
            then
               Has_Asset := True;
            else
               return False;
            end if;
         end;
      end loop;
      return Has_Income and Has_Asset;
   end Is_Incoming_Anchor;

   function Resolve_Current
     (Observed_Through : String;
      Actual_Ledger    : ALedger.Ledger.Ledger;
      Open_Plans       : ALedger.Plan_Observation.Open_Plan_Vectors.Vector;
      Registry         : ALedger.Account.Account_Registry;
      Income_Account   : ALedger.Account.Account;
      Window           : out Cycle_Window;
      Status           : out Resolve_Status) return Boolean
   is
      Latest_Actual   : Unbounded_String;
      Previous_Actual : Unbounded_String;
      Future_Anchor   : Unbounded_String;
      Income_Kind     : ALedger.Account.Account_Type;
   begin
      Window :=
        (Start_Date    => Null_Unbounded_String,
         End_Exclusive => Null_Unbounded_String);

      if not Valid_Date (Observed_Through) then
         Status := Invalid_Observation_Date;
         return False;
      elsif not ALedger.Account.Account_Type_For
        (Registry, Income_Account, Income_Kind)
      then
         Status := Income_Account_Not_Declared;
         return False;
      elsif Income_Kind /= ALedger.Account.Income then
         Status := Income_Account_Has_Wrong_Type;
         return False;
      end if;

      for Tx of Actual_Ledger.Transactions loop
         declare
            Is_Anchor : Boolean := False;
            Date      : constant String := To_String (Tx.Date_Text);
         begin
            if Date <= Observed_Through then
               for Posting of Tx.Postings loop
                  if Posting.Acc = Income_Account
                    and then Posting.Amt.Val < 0.0
                  then
                     Is_Anchor := True;
                  end if;
               end loop;
            end if;

            if Is_Anchor then
               if Length (Latest_Actual) = 0
                 or else Date > To_String (Latest_Actual)
               then
                  if Length (Latest_Actual) > 0
                    and then Date /= To_String (Latest_Actual)
                  then
                     Previous_Actual := Latest_Actual;
                  end if;
                  Latest_Actual := To_Unbounded_String (Date);
               elsif Date < To_String (Latest_Actual)
                 and then
                   (Length (Previous_Actual) = 0
                    or else Date > To_String (Previous_Actual))
               then
                  Previous_Actual := To_Unbounded_String (Date);
               end if;
            end if;
         end;
      end loop;

      if Length (Latest_Actual) = 0 or else Length (Previous_Actual) = 0 then
         Status := Insufficient_Actual_Anchors;
         return False;
      end if;

      for P of Open_Plans loop
         declare
            Date : constant String := To_String (P.Tx.Date_Text);
         begin
            if Date > Observed_Through
              and then Is_Incoming_Anchor (P, Registry, Income_Account)
              and then
                (Length (Future_Anchor) = 0
                 or else Date < To_String (Future_Anchor))
            then
               Future_Anchor := To_Unbounded_String (Date);
            end if;
         end;
      end loop;

      if Length (Future_Anchor) = 0 then
         Status := Missing_Future_Plan_Anchor;
         return False;
      elsif To_String (Latest_Actual) >= To_String (Future_Anchor) then
         Status := Invalid_Cycle_Window;
         return False;
      end if;

      Window :=
        (Start_Date    => Latest_Actual,
         End_Exclusive => Future_Anchor);
      Status := Success;
      return True;
   end Resolve_Current;

   function Contains
     (Window : Cycle_Window;
      Date   : String) return Boolean
   is
   begin
      return Date >= To_String (Window.Start_Date)
        and then Date < To_String (Window.End_Exclusive);
   end Contains;

end ALedger.Cycle_Observation;
