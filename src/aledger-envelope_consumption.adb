with Ada.Containers.Indefinite_Ordered_Maps;
with ALedger.Account; use ALedger.Account;
with ALedger.Dates;
with ALedger.Money; use ALedger.Money;

package body ALedger.Envelope_Consumption is

   use type ALedger.Dates.Date;

   function Empty_Amounts return Consumption_Amounts is
   begin
      return (Charges => Empty_Balance, Refunds => Empty_Balance);
   end Empty_Amounts;

   function Make_Amounts (Charges, Refunds : Balance) return Consumption_Amounts is
   begin
      return (Charges => Charges, Refunds => Refunds);
   end Make_Amounts;

   function Add_Amounts (Left, Right : Consumption_Amounts) return Consumption_Amounts is
   begin
      return (Charges => Add_Balance (Left.Charges, Right.Charges),
              Refunds => Add_Balance (Left.Refunds, Right.Refunds));
   end Add_Amounts;

   function Net_Consumption (Amounts : Consumption_Amounts) return Balance is
   begin
      return Subtract_Balance (Amounts.Charges, Amounts.Refunds);
   end Net_Consumption;

   function "=" (Left, Right : Consumption_Amounts) return Boolean is
   begin
      return Is_Zero_Balance (Subtract_Balance (Left.Charges, Right.Charges))
        and then Is_Zero_Balance (Subtract_Balance (Left.Refunds, Right.Refunds));
   end "=";

   function Empty_Consumption return Envelope_Consumption is
   begin
      return (Scope     => (Kind => All_Transactions),
              Managed   => Envelope_Amounts_Maps.Empty_Map,
              Unmanaged => Account_Amounts_Maps.Empty_Map,
              Unrouted  => Account_Amounts_Maps.Empty_Map);
   end Empty_Consumption;

   function Add_To_Envelope_Map
     (Map     : Envelope_Amounts_Maps.Map;
      Key     : String;
      Amounts : Consumption_Amounts) return Envelope_Amounts_Maps.Map
   is
      Result : Envelope_Amounts_Maps.Map := Map;
   begin
      if Result.Contains (Key) then
         Result.Replace (Key, Add_Amounts (Result.Element (Key), Amounts));
      else
         Result.Insert (Key, Amounts);
      end if;
      return Result;
   end Add_To_Envelope_Map;

   function Add_To_Account_Map
     (Map     : Account_Amounts_Maps.Map;
      Key     : String;
      Amounts : Consumption_Amounts) return Account_Amounts_Maps.Map
   is
      Result : Account_Amounts_Maps.Map := Map;
   begin
      if Result.Contains (Key) then
         Result.Replace (Key, Add_Amounts (Result.Element (Key), Amounts));
      else
         Result.Insert (Key, Amounts);
      end if;
      return Result;
   end Add_To_Account_Map;

   package Date_Maps is new Ada.Containers.Indefinite_Ordered_Maps
     (Key_Type     => String,
      Element_Type => ALedger.Dates.Date);

   package String_Maps is new Ada.Containers.Indefinite_Ordered_Maps
     (Key_Type     => String,
      Element_Type => String);

   function Observe_Internal
     (L         : Ledger.Ledger;
      Routing   : Envelope_Routing.Routing_History;
      Scope     : Consumption_Scope) return Envelope_Consumption
   is
      Result           : Envelope_Consumption := Empty_Consumption;
      Dates_By_Id      : Date_Maps.Map;
      Reversal_Targets : String_Maps.Map;

      function Resolve_Root_Date
        (Event_Id : String;
         Own_Date : ALedger.Dates.Date) return ALedger.Dates.Date
      is
         Current_Id : Unbounded_String := To_Unbounded_String (Event_Id);
      begin
         if Event_Id'Length = 0 then
            return Own_Date;
         end if;

         while Reversal_Targets.Contains (To_String (Current_Id)) loop
            Current_Id := To_Unbounded_String
              (Reversal_Targets.Element (To_String (Current_Id)));
         end loop;

         if Dates_By_Id.Contains (To_String (Current_Id)) then
            return Dates_By_Id.Element (To_String (Current_Id));
         else
            return Own_Date;
         end if;
      end Resolve_Root_Date;

      function Is_Expense_Account (Acc : Account.Account) return Boolean is
         Cat : Account_Type;
      begin
         return Account_Type_For (L.Registry, Acc, Cat) and then Cat = Expense;
      end Is_Expense_Account;

      function In_Scope (Date : ALedger.Dates.Date) return Boolean is
      begin
         case Scope.Kind is
            when All_Transactions =>
               return True;
            when Through_Date =>
               return Date <= Scope.Through;
         end case;
      end In_Scope;

   begin
      Result.Scope := Scope;

      for Tx of L.Transactions loop
         declare
            Ev_Id  : constant String := To_String (Tx.Event_ID);
            Rev_Id : constant String := To_String (Tx.Reverses_ID);
         begin
            if Ev_Id'Length > 0 then
               Dates_By_Id.Include (Ev_Id, Tx.Date);
               if Rev_Id'Length > 0 then
                  Reversal_Targets.Include (Ev_Id, Rev_Id);
               end if;
            end if;
         end;
      end loop;

      for Tx of L.Transactions loop
         if In_Scope (Tx.Date) then
            declare
               Ev_Id     : constant String := To_String (Tx.Event_ID);
               Root_Date : constant ALedger.Dates.Date :=
                 Resolve_Root_Date (Ev_Id, Tx.Date);
            begin
               for P of Tx.Postings loop
                  if Is_Expense_Account (P.Acc) and then not Is_Zero (P.Amt.Val) then
                     declare
                        Amounts : Consumption_Amounts;
                        Acc_Str : constant String := Account.Name (P.Acc);
                     begin
                        if P.Amt.Val > 0.0 then
                           Amounts :=
                             (Charges => Singleton_Balance (P.Amt),
                              Refunds => Empty_Balance);
                        else
                           Amounts :=
                             (Charges => Empty_Balance,
                              Refunds => Singleton_Balance (Negate_Amount (P.Amt)));
                        end if;

                        if not Envelope_Routing.Has_Routing (Routing, P.Acc) then
                           Result.Unrouted :=
                             Add_To_Account_Map (Result.Unrouted, Acc_Str, Amounts);
                        else
                           declare
                              Route : constant Envelope_Routing.Expense_Route :=
                                Envelope_Routing.Resolve
                                  (Routing, P.Acc, Root_Date);
                           begin
                              case Route.Kind is
                                 when Envelope_Routing.Managed_By_Envelope =>
                                    Result.Managed :=
                                      Add_To_Envelope_Map
                                        (Result.Managed,
                                         Envelope.Image (Route.Target),
                                         Amounts);
                                 when Envelope_Routing.Not_Envelope_Managed =>
                                    Result.Unmanaged :=
                                      Add_To_Account_Map
                                        (Result.Unmanaged, Acc_Str, Amounts);
                              end case;
                           end;
                        end if;
                     end;
                  end if;
               end loop;
            end;
         end if;
      end loop;

      return Result;
   end Observe_Internal;

   function Observe_Consumption
     (L       : Ledger.Ledger;
      Routing : Envelope_Routing.Routing_History) return Envelope_Consumption
   is
   begin
      return Observe_Internal (L, Routing, (Kind => All_Transactions));
   end Observe_Consumption;

   function Observe_Consumption
     (L            : Ledger.Ledger;
      Routing      : Envelope_Routing.Routing_History;
      Through_Date : ALedger.Dates.Date) return Envelope_Consumption
   is
   begin
      return Observe_Internal
        (L, Routing, (Kind => Through_Date, Through => Through_Date));
   end Observe_Consumption;

   function Consumption_For
     (Obs : Envelope_Consumption;
      Env : Envelope.Envelope_Id) return Consumption_Amounts
   is
      Key : constant String := Envelope.Image (Env);
   begin
      if Obs.Managed.Contains (Key) then
         return Obs.Managed.Element (Key);
      else
         return Empty_Amounts;
      end if;
   end Consumption_For;

   function Net_For
     (Obs : Envelope_Consumption;
      Env : Envelope.Envelope_Id) return Balance
   is
   begin
      return Net_Consumption (Consumption_For (Obs, Env));
   end Net_For;

   function Has_Unrouted (Obs : Envelope_Consumption) return Boolean is
   begin
      return not Obs.Unrouted.Is_Empty;
   end Has_Unrouted;

   procedure For_Each_Managed
     (Obs     : Envelope_Consumption;
      Process : not null access procedure
        (Env_Id  : Envelope.Envelope_Id;
         Amounts : Consumption_Amounts))
   is
      Cursor : Envelope_Amounts_Maps.Cursor := Obs.Managed.First;
   begin
      while Envelope_Amounts_Maps.Has_Element (Cursor) loop
         declare
            Name   : constant String := Envelope_Amounts_Maps.Key (Cursor);
            Env_Id : constant Envelope.Envelope_Id :=
              Envelope.Make_Envelope_Id (Name);
         begin
            Process (Env_Id, Envelope_Amounts_Maps.Element (Cursor));
         end;
         Envelope_Amounts_Maps.Next (Cursor);
      end loop;
   end For_Each_Managed;

   procedure For_Each_Unrouted
     (Obs     : Envelope_Consumption;
      Process : not null access procedure
        (Acc_Name : String;
         Amounts  : Consumption_Amounts))
   is
      Cursor : Account_Amounts_Maps.Cursor := Obs.Unrouted.First;
   begin
      while Account_Amounts_Maps.Has_Element (Cursor) loop
         declare
            Acc_Name : constant String := Account_Amounts_Maps.Key (Cursor);
         begin
            Process (Acc_Name, Account_Amounts_Maps.Element (Cursor));
         end;
         Account_Amounts_Maps.Next (Cursor);
      end loop;
   end For_Each_Unrouted;

end ALedger.Envelope_Consumption;
