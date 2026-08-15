with Ada.Containers.Indefinite_Ordered_Maps;
with ALedger.Account; use ALedger.Account;

package body ALedger.Envelope_Consumption is

   --  ========================================================================
   --  Consumption Amounts
   --  ========================================================================

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

   --  ========================================================================
   --  Envelope Consumption Observation
   --  ========================================================================

   function Empty_Consumption return Envelope_Consumption is
   begin
      return (Observed_Through => Null_Unbounded_String,
              Managed          => Envelope_Amounts_Maps.Empty_Map,
              Unmanaged        => Account_Amounts_Maps.Empty_Map,
              Unrouted         => Account_Amounts_Maps.Empty_Map);
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

   package String_Maps is new Ada.Containers.Indefinite_Ordered_Maps
     (Key_Type     => String,
      Element_Type => String);

   function Observe_Consumption
     (L            : Ledger.Ledger;
      Routing      : Envelope_Routing.Routing_History;
      Through_Date : String := "") return Envelope_Consumption
   is
      Result            : Envelope_Consumption := Empty_Consumption;
      Dates_By_Id       : String_Maps.Map;
      Reversal_Targets  : String_Maps.Map;

      function Resolve_Root_Date (Event_Id, Own_Date : String) return String is
         Current_Id : String := Event_Id;
      begin
         if Current_Id'Length = 0 then
            return Own_Date;
         end if;

         --  Follow reversal chain to root
         while Reversal_Targets.Contains (Current_Id) loop
            Current_Id := Reversal_Targets.Element (Current_Id);
         end loop;

         if Dates_By_Id.Contains (Current_Id) then
            return Dates_By_Id.Element (Current_Id);
         else
            return Own_Date;
         end if;
      end Resolve_Root_Date;

      function Is_Expense_Account (Acc : Account.Account) return Boolean is
         Cat : Account_Type;
      begin
         if Account_Type_For (L.Registry, Acc, Cat) then
            return Cat = Expense;
         else
            --  Fallback check on name prefix for undeclared accounts
            declare
               Acc_Name : constant String := Account.Name (Acc);
            begin
               return Acc_Name'Length >= 9
                 and then Acc_Name (Acc_Name'First .. Acc_Name'First + 8) = "expenses:";
            end;
         end if;
      end Is_Expense_Account;

   begin
      if Through_Date'Length > 0 then
         Result.Observed_Through := To_Unbounded_String (Through_Date);
      end if;

      --  Pass 1: Build identity and reversal index
      for Tx of L.Transactions loop
         declare
            Ev_Id  : constant String := To_String (Tx.Event_ID);
            Rev_Id : constant String := To_String (Tx.Reverses_ID);
            D_Text : constant String := To_String (Tx.Date_Text);
         begin
            if Ev_Id'Length > 0 then
               Dates_By_Id.Include (Ev_Id, D_Text);
               if Rev_Id'Length > 0 then
                  Reversal_Targets.Include (Ev_Id, Rev_Id);
               end if;
            end if;
         end;
      end loop;

      --  Pass 2: Accumulate expense postings
      for Tx of L.Transactions loop
         declare
            Tx_Date : constant String := To_String (Tx.Date_Text);
         begin
            --  Date filter
            if Through_Date'Length = 0 or else Tx_Date <= Through_Date then
               declare
                  Ev_Id     : constant String := To_String (Tx.Event_ID);
                  Root_Date : constant String := Resolve_Root_Date (Ev_Id, Tx_Date);
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
                              --  Missing route is attention evidence (Unrouted)
                              Result.Unrouted :=
                                Add_To_Account_Map (Result.Unrouted, Acc_Str, Amounts);
                           else
                              declare
                                 Route : constant Envelope_Routing.Expense_Route :=
                                   Envelope_Routing.Resolve (Routing, P.Acc, Root_Date);
                              begin
                                 case Route.Kind is
                                    when Envelope_Routing.Managed_By_Envelope =>
                                       declare
                                          Env_Name : constant String :=
                                            Envelope.Image (Route.Target);
                                       begin
                                          Result.Managed :=
                                            Add_To_Envelope_Map
                                              (Result.Managed, Env_Name, Amounts);
                                       end;
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
         end;
      end loop;

      return Result;
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
