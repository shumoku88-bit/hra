with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with ALedger.Money;
with ALedger.Account;
with ALedger.Envelope;
with ALedger.Envelope_Routing;
with ALedger.Fulfillment_Routing;
with ALedger.Plan;

package body ALedger.Envelope_Commitment is

   use type ALedger.Account.Account_Type;
   use type ALedger.Money.Quantity;

   function Empty_Observation return Commitment_Observation is
   begin
      return
        (Observed_Through    => Null_Unbounded_String,
         Cycle_End_Exclusive => Null_Unbounded_String,
         Managed             => Envelope_Balance_Maps.Empty_Map,
         Unmanaged           => Account_Balance_Maps.Empty_Map,
         Unrouted            => Account_Balance_Maps.Empty_Map);
   end Empty_Observation;

   procedure Add_Envelope
     (Map : in out Envelope_Balance_Maps.Map;
      Key : String;
      Amt : ALedger.Money.Amount)
   is
      Next : ALedger.Money.Balance := ALedger.Money.Singleton_Balance (Amt);
   begin
      if Map.Contains (Key) then
         Next := ALedger.Money.Add_Balance (Map.Element (Key), Next);
         Map.Replace (Key, Next);
      else
         Map.Insert (Key, Next);
      end if;
   end Add_Envelope;

   procedure Add_Account
     (Map : in out Account_Balance_Maps.Map;
      Key : String;
      Amt : ALedger.Money.Amount)
   is
      Next : ALedger.Money.Balance := ALedger.Money.Singleton_Balance (Amt);
   begin
      if Map.Contains (Key) then
         Next := ALedger.Money.Add_Balance (Map.Element (Key), Next);
         Map.Replace (Key, Next);
      else
         Map.Insert (Key, Next);
      end if;
   end Add_Account;

   function Observe
     (Open_Plans       : ALedger.Plan_Observation.Open_Plan_Vectors.Vector;
      Registry         : ALedger.Account.Account_Registry;
      Routing          : ALedger.Envelope_Routing.Routing_History;
      Window           : ALedger.Cycle_Observation.Cycle_Window;
      Observed_Through : String;
      Result           : out Commitment_Observation;
      Diag             : out Observe_Diagnostic) return Boolean
   is
   begin
      return Observe
        (Open_Plans,
         Registry,
         Routing,
         ALedger.Fulfillment_Routing.Empty_History,
         Window,
         Observed_Through,
         Result,
         Diag);
   end Observe;

   function Observe
     (Open_Plans       : ALedger.Plan_Observation.Open_Plan_Vectors.Vector;
      Registry         : ALedger.Account.Account_Registry;
      Routing          : ALedger.Envelope_Routing.Routing_History;
      Fulfillment      : ALedger.Fulfillment_Routing.Fulfillment_Routing_History;
      Window           : ALedger.Cycle_Observation.Cycle_Window;
      Observed_Through : String;
      Result           : out Commitment_Observation;
      Diag             : out Observe_Diagnostic) return Boolean
   is
      Output : Commitment_Observation := Empty_Observation;

      procedure Fail
        (Status  : Observe_Status;
         Plan_ID : String;
         Message : String)
      is
      begin
         Diag :=
           (Status  => Status,
            Plan_Id => To_Unbounded_String (Plan_ID),
            Message => To_Unbounded_String (Message));
      end Fail;

   begin
      Result := Output;
      Diag :=
        (Status  => Success,
         Plan_Id => Null_Unbounded_String,
         Message => Null_Unbounded_String);

      if not ALedger.Cycle_Observation.Contains (Window, Observed_Through) then
         Fail
           (Observation_Outside_Cycle,
            "",
            "observation day is outside the resolved current cycle");
         return False;
      end if;

      Output.Observed_Through := To_Unbounded_String (Observed_Through);
      Output.Cycle_End_Exclusive := Window.End_Exclusive;

      for P of Open_Plans loop
         if To_String (P.Tx.Date_Text) < To_String (Window.End_Exclusive) then
            declare
               Has_Positive_Expense : Boolean := False;
               Has_Negative_Asset   : Boolean := False;
            begin
               for Posting of P.Tx.Postings loop
                  declare
                     Category : ALedger.Account.Account_Type;
                     Known    : constant Boolean :=
                       ALedger.Account.Account_Type_For
                         (Registry, Posting.Acc, Category);
                  begin
                     if not Known then
                        Fail
                          (Undeclared_Plan_Account,
                           ALedger.Plan.Text (P.ID),
                           "Plan Posting references an undeclared Account: " &
                             ALedger.Account.Name (Posting.Acc));
                        return False;
                     elsif Category = ALedger.Account.Expense
                       and then Posting.Amt.Val > 0.0
                     then
                        Has_Positive_Expense := True;
                     elsif Category = ALedger.Account.Asset
                       and then Posting.Amt.Val < 0.0
                     then
                        Has_Negative_Asset := True;
                     end if;
                  end;
               end loop;

               if Has_Positive_Expense and then not Has_Negative_Asset then
                  Fail
                    (Unsupported_Expense_Plan_Flow,
                     ALedger.Plan.Text (P.ID),
                     "positive Expense Plan commitment requires a negative Asset funding source");
                  return False;
               end if;

               for Posting of P.Tx.Postings loop
                  if Posting.Amt.Val > 0.0 then
                     declare
                        Category : ALedger.Account.Account_Type;
                        Known    : constant Boolean :=
                          ALedger.Account.Account_Type_For
                            (Registry, Posting.Acc, Category);
                     begin
                        if not Known then
                           Fail
                             (Undeclared_Plan_Account,
                              ALedger.Plan.Text (P.ID),
                              "Plan Posting references an undeclared Account");
                           return False;
                        elsif Category = ALedger.Account.Expense then
                           declare
                              Account_Name : constant String :=
                                ALedger.Account.Name (Posting.Acc);
                           begin
                              if not ALedger.Envelope_Routing.Has_Routing_At
                                (Routing, Posting.Acc, Observed_Through)
                              then
                                 Add_Account
                                   (Output.Unrouted,
                                    Account_Name,
                                    Posting.Amt);
                              else
                                 declare
                                    Route : constant ALedger.Envelope_Routing.Expense_Route :=
                                      ALedger.Envelope_Routing.Resolve
                                        (Routing,
                                         Posting.Acc,
                                         Observed_Through);
                                 begin
                                    case Route.Kind is
                                       when ALedger.Envelope_Routing.Managed_By_Envelope =>
                                          Add_Envelope
                                            (Output.Managed,
                                             ALedger.Envelope.Image (Route.Target),
                                             Posting.Amt);
                                       when ALedger.Envelope_Routing.Not_Envelope_Managed =>
                                          Add_Account
                                            (Output.Unmanaged,
                                             Account_Name,
                                             Posting.Amt);
                                    end case;
                                 end;
                              end if;
                           end;
                        else
                           --  Positive non-Expense postings never inherit
                           --  Envelope meaning from their Account. The stable
                           --  PlanId is the sole fulfillment coordinate.
                           if ALedger.Fulfillment_Routing.Has_Routing_At
                             (Fulfillment, P.ID, Observed_Through)
                           then
                              declare
                                 Route : constant ALedger.Fulfillment_Routing.Fulfillment_Route :=
                                   ALedger.Fulfillment_Routing.Resolve
                                     (Fulfillment, P.ID, Observed_Through);
                              begin
                                 case Route.Kind is
                                    when ALedger.Fulfillment_Routing.Fulfills_Envelope =>
                                       Add_Envelope
                                         (Output.Managed,
                                          ALedger.Envelope.Image (Route.Target),
                                          Posting.Amt);
                                    when ALedger.Fulfillment_Routing.Not_Fulfillment_Target =>
                                       null;
                                 end case;
                              end;
                           end if;
                        end if;
                     end;
                  end if;
               end loop;
            end;
         end if;
      end loop;

      Result := Output;
      return True;
   end Observe;

   function Commitment_For
     (Obs : Commitment_Observation;
      Env : ALedger.Envelope.Envelope_Id) return ALedger.Money.Balance
   is
      Key : constant String := ALedger.Envelope.Image (Env);
   begin
      if Obs.Managed.Contains (Key) then
         return Obs.Managed.Element (Key);
      else
         return ALedger.Money.Empty_Balance;
      end if;
   end Commitment_For;

end ALedger.Envelope_Commitment;
