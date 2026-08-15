with ALedger.Account;
with ALedger.Money; use ALedger.Money;

package body ALedger.Budget_Source_Adapter is

   type Source_Endpoint_Kind is
     (Endpoint_Envelope,
      Endpoint_Unallocated,
      Endpoint_Opening,
      Endpoint_Execution,
      Endpoint_Unknown);

   type Source_Endpoint (Kind : Source_Endpoint_Kind := Endpoint_Unknown) is record
      case Kind is
         when Endpoint_Envelope =>
            Target_Envelope : Envelope.Envelope_Id;
         when Endpoint_Unallocated | Endpoint_Opening | Endpoint_Execution | Endpoint_Unknown =>
            null;
      end case;
   end record;

   function Classify_Endpoint
     (Acc_Name : String;
      Config   : Household_Config.Household_Configuration;
      Registry : Envelope.Envelope_Registry) return Source_Endpoint
   is
   begin
      --  1. Check Config.Envelopes for matching Allocation_Account
      for Env_Coord of Config.Envelopes loop
         if To_String (Env_Coord.Allocation_Account) = Acc_Name then
            declare
               Env_Id : Envelope.Envelope_Id;
               Found  : constant Boolean :=
                 Envelope.Lookup (Registry, To_String (Env_Coord.ID), Env_Id);
            begin
               if Found then
                  return (Kind => Endpoint_Envelope, Target_Envelope => Env_Id);
               else
                  return (Kind => Endpoint_Unknown);
               end if;
            end;
         end if;
      end loop;

      --  2. Check Unassigned Accounts
      for Unassigned_Acc of Config.Unassigned_Accounts loop
         if Unassigned_Acc = Acc_Name then
            return (Kind => Endpoint_Unallocated);
         end if;
      end loop;
      if Config.Has_Account_Policy then
         for Unassigned_Acc of Config.Accounts.Unassigned_Budget loop
            if Unassigned_Acc = Acc_Name then
               return (Kind => Endpoint_Unallocated);
            end if;
         end loop;
      end if;
      if Acc_Name = "budget:unassigned" then
         return (Kind => Endpoint_Unallocated);
      end if;

      --  3. Check Opening Accounts
      if Config.Has_Account_Policy then
         for Opening_Acc of Config.Accounts.Opening_Budget loop
            if Opening_Acc = Acc_Name then
               return (Kind => Endpoint_Opening);
            end if;
         end loop;
      end if;
      if Acc_Name = "budget:opening" then
         return (Kind => Endpoint_Opening);
      end if;

      --  4. Check Spent / Execution Accounts
      if Config.Has_Account_Policy then
         for Spent_Acc of Config.Accounts.Spent_Budget loop
            if Spent_Acc = Acc_Name then
               return (Kind => Endpoint_Execution);
            end if;
         end loop;
      end if;
      if Acc_Name = "budget:spent" then
         return (Kind => Endpoint_Execution);
      end if;

      return (Kind => Endpoint_Unknown);
   end Classify_Endpoint;

   function Adapt_Budget_Journal
     (Transactions : Ledger.Transaction_Vectors.Vector;
      Config       : Household_Config.Household_Configuration;
      Registry     : Envelope.Envelope_Registry;
      Movements    : out Movement_Vectors.Vector;
      Diag         : out Adapter_Diagnostic) return Boolean
   is
      Result : Movement_Vectors.Vector;
      Idx    : Natural := 0;
   begin
      Diag := (Status => Success, Transaction_Index => 0, Message => Null_Unbounded_String);

      for Tx of Transactions loop
         Idx := Idx + 1;

         --  Must have exactly 2 postings
         if Natural (Tx.Postings.Length) /= 2 then
            Diag :=
              (Status            => Transaction_Not_Binary,
               Transaction_Index => Idx,
               Message           => To_Unbounded_String
                 ("budget.journal transaction requires exactly 2 postings"));
            return False;
         end if;

         declare
            P1 : constant Ledger.Posting := Tx.Postings.Element (1);
            P2 : constant Ledger.Posting := Tx.Postings.Element (2);
         begin
            --  Postings must be exact opposites
            if P1.Amt.Val /= -P2.Amt.Val
              or else not (P1.Amt.Comm = P2.Amt.Comm)
            then
               Diag :=
                 (Status            => Postings_Not_Opposites,
                  Transaction_Index => Idx,
                  Message           => To_Unbounded_String
                    ("budget.journal postings are not exact opposites"));
               return False;
            end if;

            --  Skip zero amounts
            if not Is_Zero (P2.Amt.Val) then
               declare
                  From_Acc_Name : Unbounded_String;
                  To_Acc_Name   : Unbounded_String;
                  Amt           : Amount;
               begin
                  if P2.Amt.Val > 0.0 then
                     From_Acc_Name := Account.To_Unbounded (P1.Acc);
                     To_Acc_Name   := Account.To_Unbounded (P2.Acc);
                     Amt           := P2.Amt;
                  else
                     From_Acc_Name := Account.To_Unbounded (P2.Acc);
                     To_Acc_Name   := Account.To_Unbounded (P1.Acc);
                     Amt           := Negate_Amount (P2.Amt);
                  end if;

                  declare
                     From_Ep : constant Source_Endpoint :=
                       Classify_Endpoint (To_String (From_Acc_Name), Config, Registry);
                     To_Ep   : constant Source_Endpoint :=
                       Classify_Endpoint (To_String (To_Acc_Name), Config, Registry);
                  begin
                     if From_Ep.Kind = Endpoint_Unknown then
                        Diag :=
                          (Status            => Unrecognized_Budget_Account,
                           Transaction_Index => Idx,
                           Message           => To_Unbounded_String
                             ("unrecognized from budget account: " & To_String (From_Acc_Name)));
                        return False;
                     end if;

                     if To_Ep.Kind = Endpoint_Unknown then
                        Diag :=
                          (Status            => Unrecognized_Budget_Account,
                           Transaction_Index => Idx,
                           Message           => To_Unbounded_String
                             ("unrecognized to budget account: " & To_String (To_Acc_Name)));
                        return False;
                     end if;

                     --  Project endpoints to Entitlement_Movement
                     if From_Ep.Kind = Endpoint_Envelope
                       and then To_Ep.Kind = Endpoint_Execution
                     then
                        null; -- Spent execution movement does not affect entitlement
                     elsif From_Ep.Kind = Endpoint_Execution
                       and then To_Ep.Kind = Endpoint_Envelope
                     then
                        null; -- Reverse execution movement does not affect entitlement
                     elsif From_Ep.Kind = Endpoint_Envelope
                       and then To_Ep.Kind = Endpoint_Envelope
                     then
                        Result.Append
                          (Envelope_Entitlement.Entitlement_Movement'
                             (Kind          => Envelope_Entitlement.Transfer_Between_Envelopes,
                              Tx_Date       => Tx.Date_Text,
                              Amt           => Amt,
                              From_Envelope => From_Ep.Target_Envelope,
                              To_Envelope   => To_Ep.Target_Envelope));
                     elsif From_Ep.Kind = Endpoint_Envelope then
                        Result.Append
                          (Envelope_Entitlement.Entitlement_Movement'
                             (Kind    => Envelope_Entitlement.Return_To_Unallocated,
                              Tx_Date => Tx.Date_Text,
                              Amt     => Amt,
                              Source  => From_Ep.Target_Envelope));
                     elsif To_Ep.Kind = Endpoint_Envelope then
                        Result.Append
                          (Envelope_Entitlement.Entitlement_Movement'
                             (Kind    => Envelope_Entitlement.Grant_From_Unallocated,
                              Tx_Date => Tx.Date_Text,
                              Amt     => Amt,
                              Target  => To_Ep.Target_Envelope));
                     else
                        null; -- Non-envelope movement (e.g. Opening -> Unallocated)
                     end if;
                  end;
               end;
            end if;
         end;
      end loop;

      Movements := Result;
      return True;
   end Adapt_Budget_Journal;

   function Observe_Entitlements
     (Transactions : Ledger.Transaction_Vectors.Vector;
      Config       : Household_Config.Household_Configuration;
      Registry     : Envelope.Envelope_Registry;
      Observation  : out Envelope_Entitlement.Entitlement_Observation;
      Diag         : out Adapter_Diagnostic) return Boolean
   is
      Movements : Movement_Vectors.Vector;
      Obs       : Envelope_Entitlement.Entitlement_Observation :=
        Envelope_Entitlement.Empty_Observation;
   begin
      if not Adapt_Budget_Journal (Transactions, Config, Registry, Movements, Diag) then
         return False;
      end if;

      for M of Movements loop
         Obs := Envelope_Entitlement.Fold_Movement (Obs, M);
      end loop;

      Observation := Obs;
      return True;
   end Observe_Entitlements;

end ALedger.Budget_Source_Adapter;
