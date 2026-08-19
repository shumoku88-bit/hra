with HRA.Money;

package body HRA.Cycle_Observation is

   use type HRA.Account.Account;
   use type HRA.Account.Account_Type;
   use type HRA.Dates.Date;
   use type HRA.Money.Quantity;

   function Is_Incoming_Anchor
     (P              : HRA.Plan_Observation.Open_Plan;
      Registry       : HRA.Account.Account_Registry;
      Income_Account : HRA.Account.Account) return Boolean
   is
      Has_Income : Boolean := False;
      Has_Asset  : Boolean := False;
   begin
      for Posting of P.Tx.Postings loop
         declare
            Category : HRA.Account.Account_Type;
            Known    : constant Boolean :=
              HRA.Account.Account_Type_For
                (Registry, Posting.Acc, Category);
         begin
            if not Known then
               return False;
            elsif Category = HRA.Account.Income
              and then Posting.Acc = Income_Account
              and then Posting.Amt.Val < 0.0
            then
               Has_Income := True;
            elsif Category = HRA.Account.Asset
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
     (Observed_Through : HRA.Dates.Date;
      Actual_Ledger    : HRA.Ledger.Ledger;
      Open_Plans       : HRA.Plan_Observation.Open_Plan_Vectors.Vector;
      Registry         : HRA.Account.Account_Registry;
      Income_Account   : HRA.Account.Account;
      Window           : out Cycle_Window;
      Status           : out Resolve_Status) return Boolean
   is
      Latest_Actual       : HRA.Dates.Date;
      Previous_Actual     : HRA.Dates.Date;
      Future_Anchor       : HRA.Dates.Date;
      Has_Latest_Actual   : Boolean := False;
      Has_Previous_Actual : Boolean := False;
      Has_Future_Anchor   : Boolean := False;
      Income_Kind         : HRA.Account.Account_Type;
   begin
      if not HRA.Account.Account_Type_For
        (Registry, Income_Account, Income_Kind)
      then
         Status := Income_Account_Not_Declared;
         return False;
      elsif Income_Kind /= HRA.Account.Income then
         Status := Income_Account_Has_Wrong_Type;
         return False;
      end if;

      for Tx of Actual_Ledger.Transactions loop
         declare
            Is_Anchor : Boolean := False;
            Date      : constant HRA.Dates.Date := Tx.Date;
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
            Date : constant HRA.Dates.Date := P.Tx.Date;
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

      if not HRA.Dates.Make_Half_Open_Period
        (Latest_Actual, Future_Anchor, Window)
      then
         Status := Invalid_Cycle_Window;
         return False;
      end if;

      Status := Success;
      return True;
   end Resolve_Current;

   function Start_Date (Window : Cycle_Window) return HRA.Dates.Date is
     (HRA.Dates.First (Window));

   function End_Exclusive (Window : Cycle_Window) return HRA.Dates.Date is
     (HRA.Dates.Limit (Window));

   function Contains
     (Window : Cycle_Window;
      Date   : HRA.Dates.Date) return Boolean
   is
   begin
      return HRA.Dates.Contains (Window, Date);
   end Contains;

end HRA.Cycle_Observation;
