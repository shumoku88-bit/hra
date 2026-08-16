with ALedger.Money;

package body ALedger.Cycle_Observation is

   use type ALedger.Account.Account;
   use type ALedger.Account.Account_Type;
   use type ALedger.Dates.Date;
   use type ALedger.Money.Quantity;

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
     (Observed_Through : ALedger.Dates.Date;
      Actual_Ledger    : ALedger.Ledger.Ledger;
      Open_Plans       : ALedger.Plan_Observation.Open_Plan_Vectors.Vector;
      Registry         : ALedger.Account.Account_Registry;
      Income_Account   : ALedger.Account.Account;
      Window           : out Cycle_Window;
      Status           : out Resolve_Status) return Boolean
   is
      Latest_Actual       : ALedger.Dates.Date;
      Previous_Actual     : ALedger.Dates.Date;
      Future_Anchor       : ALedger.Dates.Date;
      Has_Latest_Actual   : Boolean := False;
      Has_Previous_Actual : Boolean := False;
      Has_Future_Anchor   : Boolean := False;
      Income_Kind         : ALedger.Account.Account_Type;
   begin
      if not ALedger.Account.Account_Type_For
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
            Date      : constant ALedger.Dates.Date := Tx.Date;
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
               if not Has_Latest_Actual or else Date > Latest_Actual then
                  if Has_Latest_Actual and then Date /= Latest_Actual then
                     Previous_Actual := Latest_Actual;
                     Has_Previous_Actual := True;
                  end if;
                  Latest_Actual := Date;
                  Has_Latest_Actual := True;
               elsif Date < Latest_Actual
                 and then
                   (not Has_Previous_Actual or else Date > Previous_Actual)
               then
                  Previous_Actual := Date;
                  Has_Previous_Actual := True;
               end if;
            end if;
         end;
      end loop;

      if not Has_Latest_Actual or else not Has_Previous_Actual then
         Status := Insufficient_Actual_Anchors;
         return False;
      end if;

      for P of Open_Plans loop
         declare
            Date : constant ALedger.Dates.Date := P.Tx.Date;
         begin
            if Date > Observed_Through
              and then Is_Incoming_Anchor (P, Registry, Income_Account)
              and then (not Has_Future_Anchor or else Date < Future_Anchor)
            then
               Future_Anchor := Date;
               Has_Future_Anchor := True;
            end if;
         end;
      end loop;

      if not Has_Future_Anchor then
         Status := Missing_Future_Plan_Anchor;
         return False;
      elsif Latest_Actual >= Future_Anchor then
         Status := Invalid_Cycle_Window;
         return False;
      end if;

      if not ALedger.Dates.Make_Half_Open_Period
        (Latest_Actual, Future_Anchor, Window)
      then
         Status := Invalid_Cycle_Window;
         return False;
      end if;

      Status := Success;
      return True;
   end Resolve_Current;

   function Start_Date (Window : Cycle_Window) return ALedger.Dates.Date is
     (ALedger.Dates.First (Window));

   function End_Exclusive (Window : Cycle_Window) return ALedger.Dates.Date is
     (ALedger.Dates.Limit (Window));

   function Contains
     (Window : Cycle_Window;
      Date   : ALedger.Dates.Date) return Boolean
   is
   begin
      return ALedger.Dates.Contains (Window, Date);
   end Contains;

end ALedger.Cycle_Observation;
