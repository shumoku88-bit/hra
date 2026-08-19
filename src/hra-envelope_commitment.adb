with HRA.Plan;

package body HRA.Envelope_Commitment is

   use type HRA.Account.Account_Type;
   use type HRA.Dates.Date;

   function Empty_Observation
     (Observed_Through    : HRA.Dates.Date;
      Cycle_End_Exclusive : HRA.Dates.Date) return Commitment_Observation
   is
   begin
      return
        (Observed_Through    => Observed_Through,
         Cycle_End_Exclusive => Cycle_End_Exclusive,
         Managed             => Envelope_Balance_Maps.Empty_Map,
         Unmanaged           => Account_Balance_Maps.Empty_Map,
         Unrouted            => Account_Balance_Maps.Empty_Map);
   end Empty_Observation;

   procedure Add_Envelope
     (Map : in out Envelope_Balance_Maps.Map;
      Key : String;
      Amt : HRA.Money.Amount)
   is
      Next : HRA.Money.Balance := HRA.Money.Singleton_Balance (Amt);
   begin
      if Map.Contains (Key) then
         Next := HRA.Money.Add_Balance (Map.Element (Key), Next);
         Map.Replace (Key, Next);
      else
         Map.Insert (Key, Next);
      end if;
   end Add_Envelope;

   procedure Add_Account
     (Map : in out Account_Balance_Maps.Map;
      Key : String;
      Amt : HRA.Money.Amount)
   is
      Next : HRA.Money.Balance := HRA.Money.Singleton_Balance (Amt);
   begin
      if Map.Contains (Key) then
         Next := HRA.Money.Add_Balance (Map.Element (Key), Next);
         Map.Replace (Key, Next);
      else
         Map.Insert (Key, Next);
      end if;
   end Add_Account;

   function Observe
     (Open_Plans       : HRA.Plan_Observation.Open_Plan_Vectors.Vector;
      Registry         : HRA.Account.Account_Registry;
      Routing          : HRA.Envelope_Routing.Routing_History;
      Fulfillment      : HRA.Fulfillment_Routing.Fulfillment_Routing_History;
      Window           : HRA.Cycle_Observation.Cycle_Window;
      Observed_Through : HRA.Dates.Date;
      Result           : out Commitment_Observation;
      Diag             : out Observe_Diagnostic) return Boolean
   is
      Cycle_Limit : constant HRA.Dates.Date :=
        HRA.Cycle_Observation.End_Exclusive (Window);
      Output      : Commitment_Observation :=
        Empty_Observation (Observed_Through, Cycle_Limit);

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

      if not HRA.Cycle_Observation.Contains (Window, Observed_Through) then
         Fail
           (Observation_Outside_Cycle,
            "",
            "observation day is outside the resolved current cycle");
         return False;
      end if;

      for P of Open_Plans loop
         if P.Tx.Date < HRA.Cycle_Observation.End_Exclusive (Window) then
            declare
               Has_Positive_Expense : Boolean := False;
               Has_Negative_Asset   : Boolean := False;
            begin
               for Posting of P.Tx.Postings loop
                  declare
                     Category : HRA.Account.Account_Type;
                     Known    : constant Boolean :=
                       HRA.Account.Account_Type_For
                         (Registry, Posting.Acc, Category);
                  begin
                     if not Known then
                        Fail
                          (Undeclared_Plan_Account,
                           HRA.Plan.Text (P.ID),
                           "Plan Posting references an undeclared Account: " &
                             HRA.Account.Name (Posting.Acc));
                        return False;
                     elsif Category = HRA.Account.Expense
                       and then Posting.Amt.Val > 0.0
                     then
                        Has_Positive_Expense := True;
                     elsif Category = HRA.Account.Asset
                       and then Posting.Amt.Val < 0.0
                     then
                        Has_Negative_Asset := True;
                     end if;
                  end;
               end loop;

               if Has_Positive_Expense and then not Has_Negative_Asset then
                  Fail
                    (Unsupported_Expense_Plan_Flow,
                     HRA.Plan.Text (P.ID),
                     "positive Expense Plan commitment requires a negative Asset funding source");
                  return False;
               end if;

               for Posting of P.Tx.Postings loop
                  if Posting.Amt.Val > 0.0 then
                     declare
                        Category : HRA.Account.Account_Type;
                        Known    : constant Boolean :=
                          HRA.Account.Account_Type_For
                            (Registry, Posting.Acc, Category);
                     begin
                        if not Known then
                           Fail
                             (Undeclared_Plan_Account,
                              HRA.Plan.Text (P.ID),
                              "Plan Posting references an undeclared Account");
                           return False;
                        elsif Category = HRA.Account.Expense then
                           declare
                              Account_Name : constant String :=
                                HRA.Account.Name (Posting.Acc);
                           begin
                              if not HRA.Envelope_Routing.Has_Routing_At
                                (Routing, Posting.Acc, Observed_Through)
                              then
                                 Add_Account
                                   (Output.Unrouted,
                                    Account_Name,
                                    Posting.Amt);
                              else
                                 declare
                                    Route : constant HRA.Envelope_Routing.Expense_Route :=
                                      HRA.Envelope_Routing.Resolve
                                        (Routing,
                                         Posting.Acc,
                                         Observed_Through);
                                 begin
                                    case Route.Kind is
                                       when HRA.Envelope_Routing.Managed_By_Envelope =>
                                          Add_Envelope
                                            (Output.Managed,
                                             HRA.Envelope.Image (Route.Target),
                                             Posting.Amt);
                                       when HRA.Envelope_Routing.Not_Envelope_Managed =>
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
                           if HRA.Fulfillment_Routing.Has_Routing_At
                             (Fulfillment, P.ID, Observed_Through)
                           then
                              declare
                                 Route : constant HRA.Fulfillment_Routing.Fulfillment_Route :=
                                   HRA.Fulfillment_Routing.Resolve
                                     (Fulfillment, P.ID, Observed_Through);
                              begin
                                 case Route.Kind is
                                    when HRA.Fulfillment_Routing.Fulfills_Envelope =>
                                       Add_Envelope
                                         (Output.Managed,
                                          HRA.Envelope.Image (Route.Target),
                                          Posting.Amt);
                                    when HRA.Fulfillment_Routing.Not_Fulfillment_Target =>
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
      Env : HRA.Envelope.Envelope_Id) return HRA.Money.Balance
   is
      Key : constant String := HRA.Envelope.Image (Env);
   begin
      if Obs.Managed.Contains (Key) then
         return Obs.Managed.Element (Key);
      else
         return HRA.Money.Empty_Balance;
      end if;
   end Commitment_For;

end HRA.Envelope_Commitment;
