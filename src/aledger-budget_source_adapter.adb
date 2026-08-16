with ALedger.Account;
with ALedger.Dates;
with ALedger.Money; use ALedger.Money;

package body ALedger.Budget_Source_Adapter is

   use type ALedger.Dates.Date;

   type Source_Endpoint_Kind is
     (Endpoint_Envelope,
      Endpoint_Unallocated,
      Endpoint_Opening,
      Endpoint_Unknown);

   type Source_Endpoint (Kind : Source_Endpoint_Kind := Endpoint_Unknown) is record
      case Kind is
         when Endpoint_Envelope =>
            Target_Envelope : Envelope.Envelope_Id;
         when Endpoint_Unallocated | Endpoint_Opening | Endpoint_Unknown =>
            null;
      end case;
   end record;

   function Classify_Endpoint
     (Acc_Name : String;
      Config   : Household_Config.Household_Configuration;
      Registry : Envelope.Envelope_Registry) return Source_Endpoint
   is
   begin
      for Env_Coord of Config.Envelopes loop
         if To_String (Env_Coord.Allocation_Account) = Acc_Name then
            declare
               Env_Id : Envelope.Envelope_Id;
               Found  : constant Boolean :=
                 Envelope.Lookup (Registry, To_String (Env_Coord.ID), Env_Id);
            begin
               if Found then
                  return
                    (Kind            => Endpoint_Envelope,
                     Target_Envelope => Env_Id);
               else
                  return (Kind => Endpoint_Unknown);
               end if;
            end;
         end if;
      end loop;

      for Opening_Acc of Config.Opening_Accounts loop
         if Opening_Acc = Acc_Name then
            return (Kind => Endpoint_Opening);
         end if;
      end loop;

      for Unassigned_Acc of Config.Unassigned_Accounts loop
         if Unassigned_Acc = Acc_Name then
            return (Kind => Endpoint_Unallocated);
         end if;
      end loop;

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
      Diag :=
        (Status            => Success,
         Transaction_Index => 0,
         Message           => Null_Unbounded_String);

      for Tx of Transactions loop
         Idx := Idx + 1;

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

            declare
               From_Acc_Name : Unbounded_String;
               To_Acc_Name   : Unbounded_String;
               Amt           : Amount;
            begin
               if P2.Amt.Val >= Zero_Quantity then
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
                    Classify_Endpoint
                      (To_String (From_Acc_Name), Config, Registry);
                  To_Ep   : constant Source_Endpoint :=
                    Classify_Endpoint
                      (To_String (To_Acc_Name), Config, Registry);
               begin
                  if From_Ep.Kind = Endpoint_Unknown then
                     Diag :=
                       (Status            => Unrecognized_Budget_Account,
                        Transaction_Index => Idx,
                        Message           => To_Unbounded_String
                          ("unrecognized from budget account: " &
                           To_String (From_Acc_Name)));
                     return False;
                  elsif To_Ep.Kind = Endpoint_Unknown then
                     Diag :=
                       (Status            => Unrecognized_Budget_Account,
                        Transaction_Index => Idx,
                        Message           => To_Unbounded_String
                          ("unrecognized to budget account: " &
                           To_String (To_Acc_Name)));
                     return False;
                  end if;

                  --  A zero movement establishes the source epoch but carries
                  --  no Entitlement transfer.
                  if not Is_Zero (Amt.Val) then
                     if From_Ep.Kind = Endpoint_Envelope
                       and then To_Ep.Kind = Endpoint_Envelope
                     then
                        Result.Append
                          (Envelope_Entitlement.Entitlement_Movement'
                             (Kind          =>
                                Envelope_Entitlement.Transfer_Between_Envelopes,
                              Tx_Date       => Tx.Date,
                              Amt           => Amt,
                              From_Envelope => From_Ep.Target_Envelope,
                              To_Envelope   => To_Ep.Target_Envelope));
                     elsif From_Ep.Kind = Endpoint_Envelope then
                        Result.Append
                          (Envelope_Entitlement.Entitlement_Movement'
                             (Kind    =>
                                Envelope_Entitlement.Return_To_Unallocated,
                              Tx_Date => Tx.Date,
                              Amt     => Amt,
                              Source  => From_Ep.Target_Envelope));
                     elsif To_Ep.Kind = Endpoint_Envelope then
                        Result.Append
                          (Envelope_Entitlement.Entitlement_Movement'
                             (Kind    =>
                                Envelope_Entitlement.Grant_From_Unallocated,
                              Tx_Date => Tx.Date,
                              Amt     => Amt,
                              Target  => To_Ep.Target_Envelope));
                     end if;
                  end if;
               end;
            end;
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
      if not Adapt_Budget_Journal
        (Transactions, Config, Registry, Movements, Diag)
      then
         return False;
      end if;

      --  The complete source has already passed endpoint admission. Its earliest
      --  transaction day per Commodity is the source-owned opening boundary,
      --  even when that movement carries zero quantity.
      for Tx of Transactions loop
         Obs := Envelope_Entitlement.Record_Origin
           (Obs,
            Tx.Postings.Element (1).Amt.Comm,
            Tx.Date);
      end loop;

      for M of Movements loop
         Obs := Envelope_Entitlement.Fold_Movement (Obs, M);
      end loop;

      Observation := Obs;
      return True;
   end Observe_Entitlements;

   function Observe_Entitlements
     (Transactions : Ledger.Transaction_Vectors.Vector;
      Config       : Household_Config.Household_Configuration;
      Registry     : Envelope.Envelope_Registry;
      Through_Date : ALedger.Dates.Date;
      Observation  : out Envelope_Entitlement.Entitlement_Observation;
      Diag         : out Adapter_Diagnostic) return Boolean
   is
      Movements : Movement_Vectors.Vector;
      Obs       : Envelope_Entitlement.Entitlement_Observation :=
        Envelope_Entitlement.Empty_Observation;
   begin
      --  Validate the complete admitted Budget source, not only the historical
      --  prefix. A future malformed coordinate must not become a hidden fallback
      --  merely because the requested observation is earlier.
      if not Adapt_Budget_Journal
        (Transactions, Config, Registry, Movements, Diag)
      then
         return False;
      end if;

      for Tx of Transactions loop
         if Tx.Date <= Through_Date then
            Obs := Envelope_Entitlement.Record_Origin
              (Obs,
               Tx.Postings.Element (1).Amt.Comm,
               Tx.Date);
         end if;
      end loop;

      for M of Movements loop
         if M.Tx_Date <= Through_Date then
            Obs := Envelope_Entitlement.Fold_Movement (Obs, M);
         end if;
      end loop;

      Observation := Obs;
      return True;
   end Observe_Entitlements;

end ALedger.Budget_Source_Adapter;
