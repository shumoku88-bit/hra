package body HRA.Envelope_Fulfillment is

   use type HRA.Account.Account;
   use type HRA.Account.Account_Type;
   use type HRA.Dates.Date;
   use type HRA.Fulfillment_Routing.Fulfillment_Route_Kind;

   package String_Maps is new Ada.Containers.Indefinite_Ordered_Maps
     (Key_Type     => String,
      Element_Type => String);

   package String_Natural_Maps is new Ada.Containers.Indefinite_Ordered_Maps
     (Key_Type     => String,
      Element_Type => Natural);

   function Empty_Amounts return Fulfillment_Amounts is
   begin
      return (Applied => Empty_Balance, Reversed => Empty_Balance);
   end Empty_Amounts;

   function Add_Amounts
     (Left, Right : Fulfillment_Amounts) return Fulfillment_Amounts
   is
   begin
      return
        (Applied  => Add_Balance (Left.Applied, Right.Applied),
         Reversed => Add_Balance (Left.Reversed, Right.Reversed));
   end Add_Amounts;

   function Net_Fulfillment (Amounts : Fulfillment_Amounts) return Balance is
   begin
      return Subtract_Balance (Amounts.Applied, Amounts.Reversed);
   end Net_Fulfillment;

   function Empty_Fulfillment
     (Observed_Through : HRA.Dates.Date) return Envelope_Fulfillment is
   begin
      return
        (Observed_Through => Observed_Through,
         Managed          => Envelope_Amounts_Maps.Empty_Map,
         Evidence         => Evidence_Vectors.Empty_Vector);
   end Empty_Fulfillment;

   procedure Add_Managed
     (Obs     : in out Envelope_Fulfillment;
      Env     : HRA.Envelope.Envelope_Id;
      Amounts : Fulfillment_Amounts)
   is
      Key : constant String := HRA.Envelope.Image (Env);
   begin
      if Obs.Managed.Contains (Key) then
         Obs.Managed.Replace
           (Key, Add_Amounts (Obs.Managed.Element (Key), Amounts));
      else
         Obs.Managed.Insert (Key, Amounts);
      end if;
   end Add_Managed;

   function Observe_Internal
     (Completed            : HRA.Plan_Observation.Completed_Plan_Vectors.Vector;
      Actual_Ledger        : HRA.Ledger.Ledger;
      Registry             : HRA.Account.Account_Registry;
      Routing              : HRA.Fulfillment_Routing.Fulfillment_Routing_History;
      Require_Stock_Origin : Boolean;
      Entitlement          : HRA.Envelope_Entitlement.Entitlement_Observation;
      Observed_Through     : HRA.Dates.Date;
      Result               : out Envelope_Fulfillment;
      Diag                 : out Observe_Diagnostic) return Boolean
   is
      Output           : Envelope_Fulfillment :=
        Empty_Fulfillment (Observed_Through);
      Event_Index      : String_Natural_Maps.Map;
      Reversal_Targets : String_Maps.Map;

      procedure Fail
        (Status  : Observe_Status;
         Plan_ID : HRA.Plan.Plan_Id;
         Message : String)
      is
      begin
         Diag :=
           (Status  => Status,
            Plan_Id => To_Unbounded_String
              ((if HRA.Plan.Is_Null (Plan_ID)
                then "" else HRA.Plan.Text (Plan_ID))),
            Message => To_Unbounded_String (Message));
      end Fail;

      function Direction (Q : HRA.Money.Quantity) return Integer is
      begin
         if Q > HRA.Money.Zero_Quantity then
            return 1;
         elsif Q < HRA.Money.Zero_Quantity then
            return -1;
         else
            return 0;
         end if;
      end Direction;

      function In_Stock_Horizon
        (Completion_Date : HRA.Dates.Date;
         Amt             : HRA.Money.Amount) return Boolean
      is
      begin
         if not Require_Stock_Origin then
            return True;
         elsif not HRA.Envelope_Entitlement.Has_Origin
           (Entitlement, Amt.Comm)
         then
            return False;
         else
            return Completion_Date >=
              HRA.Envelope_Entitlement.Origin_For
                (Entitlement, Amt.Comm);
         end if;
      end In_Stock_Horizon;

      function Root_Event_Id (Event_Id : String) return Unbounded_String is
         Current : Unbounded_String := To_Unbounded_String (Event_Id);
      begin
         if Event_Id'Length = 0 then
            return Null_Unbounded_String;
         end if;

         for Step in 1 .. Natural (Actual_Ledger.Transactions.Length) + 1 loop
            pragma Unreferenced (Step);
            if not Reversal_Targets.Contains (To_String (Current)) then
               return Current;
            end if;
            Current := To_Unbounded_String
              (Reversal_Targets.Element (To_String (Current)));
         end loop;

         return Null_Unbounded_String;
      end Root_Event_Id;

      function Reversal_Depth_To_Root
        (Event_Id : String;
         Root_Id  : String;
         Depth    : out Natural) return Boolean
      is
         Current : Unbounded_String := To_Unbounded_String (Event_Id);
      begin
         Depth := 0;
         if Event_Id'Length = 0 or else Root_Id'Length = 0 then
            return False;
         end if;

         for Step in 0 .. Natural (Actual_Ledger.Transactions.Length) loop
            pragma Unreferenced (Step);
            if To_String (Current) = Root_Id then
               return True;
            end if;

            if not Event_Index.Contains (To_String (Current)) then
               return False;
            end if;

            declare
               Current_Tx : constant HRA.Ledger.Transaction :=
                 Actual_Ledger.Transactions.Element
                   (Event_Index.Element (To_String (Current)));
               Target_Id : constant String := To_String (Current_Tx.Reverses_ID);
            begin
               if Target_Id'Length = 0
                 or else not Event_Index.Contains (Target_Id)
               then
                  return False;
               end if;

               declare
                  Target_Tx : constant HRA.Ledger.Transaction :=
                    Actual_Ledger.Transactions.Element
                      (Event_Index.Element (Target_Id));
               begin
                  if not HRA.Ledger.Is_Reversal_Of
                    (Current_Tx, Target_Tx)
                  then
                     return False;
                  end if;
               end;

               Depth := Depth + 1;
               Current := To_Unbounded_String (Target_Id);
            end;
         end loop;

         return False;
      end Reversal_Depth_To_Root;

   begin
      Output.Observed_Through := Observed_Through;
      Result := Output;
      Diag :=
        (Status  => Success,
         Plan_Id => Null_Unbounded_String,
         Message => Null_Unbounded_String);

      for I in 1 .. Natural (Actual_Ledger.Transactions.Length) loop
         declare
            Tx     : constant HRA.Ledger.Transaction :=
              Actual_Ledger.Transactions.Element (I);
            Ev_Id  : constant String := To_String (Tx.Event_ID);
            Rev_Id : constant String := To_String (Tx.Reverses_ID);
         begin
            if Ev_Id'Length > 0 then
               if Event_Index.Contains (Ev_Id) then
                  Fail
                    (Duplicate_Actual_Event_Id,
                     HRA.Plan.Null_Plan_Id,
                     "Actual Event_ID is not unique: " & Ev_Id);
                  return False;
               end if;
               Event_Index.Insert (Ev_Id, I);
               if Rev_Id'Length > 0 then
                  Reversal_Targets.Insert (Ev_Id, Rev_Id);
               end if;
            end if;
         end;
      end loop;

      for Pair of Completed loop
         declare
            Completion_Date : constant HRA.Dates.Date := Pair.Actual_Tx.Date;
            Decision        :
              HRA.Fulfillment_Routing.Fulfillment_Routing_Decision;
         begin
            if Completion_Date <= Observed_Through
              and then HRA.Fulfillment_Routing.Resolve_Decision
                (Routing, Pair.ID, Completion_Date, Decision)
              and then Decision.Route.Kind =
                HRA.Fulfillment_Routing.Fulfills_Envelope
            then
               declare
                  Plan_Count : constant Natural :=
                    Natural (Pair.Plan_Tx.Postings.Length);
                  Actual_Count : constant Natural :=
                    Natural (Pair.Actual_Tx.Postings.Length);
                  Root_Id : constant String :=
                    To_String (Pair.Actual_Tx.Event_ID);
                  Reverses_Id : constant String :=
                    To_String (Pair.Actual_Tx.Reverses_ID);
               begin
                  if Root_Id'Length = 0 then
                     Fail
                       (Missing_Completion_Event_Id,
                        Pair.ID,
                        "routed completion Actual requires stable Event_ID");
                     return False;
                  elsif Reverses_Id'Length > 0 then
                     Fail
                       (Completion_Actual_Is_Reversal,
                        Pair.ID,
                        "routed completion Actual must be the non-reversal root of its Fulfillment evidence");
                     return False;
                  elsif Plan_Count /= Actual_Count then
                     Fail
                       (Completion_Posting_Count_Mismatch,
                        Pair.ID,
                        "Plan and completion Actual posting counts must match");
                     return False;
                  end if;

                  for I in 1 .. Plan_Count loop
                     declare
                        Plan_Post : constant HRA.Ledger.Posting :=
                          Pair.Plan_Tx.Postings.Element (I);
                        Actual_Post : constant HRA.Ledger.Posting :=
                          Pair.Actual_Tx.Postings.Element (I);
                     begin
                        if Plan_Post.Acc /= Actual_Post.Acc then
                           Fail
                             (Completion_Account_Shape_Mismatch,
                              Pair.ID,
                              "Plan/Actual Account order must match");
                           return False;
                        elsif Direction (Plan_Post.Amt.Val) /=
                          Direction (Actual_Post.Amt.Val)
                        then
                           Fail
                             (Completion_Direction_Mismatch,
                              Pair.ID,
                              "Plan/Actual posting directions must match");
                           return False;
                        elsif Plan_Post.Amt.Comm /= Actual_Post.Amt.Comm then
                           Fail
                             (Completion_Commodity_Mismatch,
                              Pair.ID,
                              "Plan/Actual posting Commodities must match");
                           return False;
                        end if;
                     end;
                  end loop;

                  for I in 1 .. Plan_Count loop
                     declare
                        Plan_Post : constant HRA.Ledger.Posting :=
                          Pair.Plan_Tx.Postings.Element (I);
                        Actual_Post : constant HRA.Ledger.Posting :=
                          Pair.Actual_Tx.Postings.Element (I);
                        Category : HRA.Account.Account_Type;
                        Known : constant Boolean :=
                          HRA.Account.Account_Type_For
                            (Registry, Plan_Post.Acc, Category);
                     begin
                        if not Known then
                           Fail
                             (Undeclared_Plan_Account,
                              Pair.ID,
                              "completed Plan references undeclared Account: " &
                                HRA.Account.Name (Plan_Post.Acc));
                           return False;
                        end if;

                        if Plan_Post.Amt.Val > HRA.Money.Zero_Quantity
                          and then Category /= HRA.Account.Expense
                          and then In_Stock_Horizon
                            (Completion_Date, Actual_Post.Amt)
                        then
                           declare
                              Amounts : Fulfillment_Amounts := Empty_Amounts;
                              Root_Amount : constant HRA.Money.Amount :=
                                Actual_Post.Amt;
                           begin
                              for Tx of Actual_Ledger.Transactions loop
                                 declare
                                    Ev_Id : constant String :=
                                      To_String (Tx.Event_ID);
                                 begin
                                    if Tx.Date <= Observed_Through
                                      and then Ev_Id'Length > 0
                                      and then To_String
                                        (Root_Event_Id (Ev_Id)) = Root_Id
                                    then
                                       declare
                                          Depth : Natural;
                                       begin
                                          if not Reversal_Depth_To_Root
                                            (Ev_Id, Root_Id, Depth)
                                          then
                                             Fail
                                               (Reversal_Shape_Mismatch,
                                                Pair.ID,
                                                "Fulfillment reversal chain must consist of exact Ledger reversal links");
                                             return False;
                                          end if;

                                          if Depth mod 2 = 0 then
                                             Amounts.Applied :=
                                               Add_Balance
                                                 (Amounts.Applied,
                                                  Singleton_Balance
                                                    (Root_Amount));
                                          else
                                             Amounts.Reversed :=
                                               Add_Balance
                                                 (Amounts.Reversed,
                                                  Singleton_Balance
                                                    (Root_Amount));
                                          end if;
                                       end;
                                    end if;
                                 end;
                              end loop;

                              Add_Managed
                                (Output, Decision.Route.Target, Amounts);
                              Output.Evidence.Append
                                (Fulfillment_Evidence'
                                   (Plan_ID              => Pair.ID,
                                    Envelope_ID          => Decision.Route.Target,
                                    Completion_Date      => Pair.Actual_Tx.Date,
                                    Root_Actual_Event_ID => Pair.Actual_Tx.Event_ID,
                                    Plan_Header_Line     => Pair.Plan_Source.Header_Line,
                                    Actual_Header_Line   => Pair.Actual_Source.Header_Line,
                                    Target_Posting_Index => Positive (I),
                                    Route_Effective_From => Decision.Effective_From,
                                    Route_Note           => Decision.Note,
                                    Applied              => Amounts.Applied,
                                    Reversed             => Amounts.Reversed));
                           end;
                        end if;
                     end;
                  end loop;
               end;
            end if;
         end;
      end loop;

      Result := Output;
      return True;
   end Observe_Internal;

   function Observe
     (Completed        : HRA.Plan_Observation.Completed_Plan_Vectors.Vector;
      Actual_Ledger    : HRA.Ledger.Ledger;
      Registry         : HRA.Account.Account_Registry;
      Routing          : HRA.Fulfillment_Routing.Fulfillment_Routing_History;
      Observed_Through : HRA.Dates.Date;
      Result           : out Envelope_Fulfillment;
      Diag             : out Observe_Diagnostic) return Boolean
   is
   begin
      return Observe_Internal
        (Completed,
         Actual_Ledger,
         Registry,
         Routing,
         False,
         HRA.Envelope_Entitlement.Empty_Observation,
         Observed_Through,
         Result,
         Diag);
   end Observe;

   function Observe_Stock
     (Completed        : HRA.Plan_Observation.Completed_Plan_Vectors.Vector;
      Actual_Ledger    : HRA.Ledger.Ledger;
      Registry         : HRA.Account.Account_Registry;
      Routing          : HRA.Fulfillment_Routing.Fulfillment_Routing_History;
      Entitlement      : HRA.Envelope_Entitlement.Entitlement_Observation;
      Observed_Through : HRA.Dates.Date;
      Result           : out Envelope_Fulfillment;
      Diag             : out Observe_Diagnostic) return Boolean
   is
   begin
      return Observe_Internal
        (Completed,
         Actual_Ledger,
         Registry,
         Routing,
         True,
         Entitlement,
         Observed_Through,
         Result,
         Diag);
   end Observe_Stock;

   function Fulfillment_For
     (Obs : Envelope_Fulfillment;
      Env : HRA.Envelope.Envelope_Id) return Fulfillment_Amounts
   is
      Key : constant String := HRA.Envelope.Image (Env);
   begin
      if Obs.Managed.Contains (Key) then
         return Obs.Managed.Element (Key);
      else
         return Empty_Amounts;
      end if;
   end Fulfillment_For;

   function Net_For
     (Obs : Envelope_Fulfillment;
      Env : HRA.Envelope.Envelope_Id) return Balance
   is
   begin
      return Net_Fulfillment (Fulfillment_For (Obs, Env));
   end Net_For;

end HRA.Envelope_Fulfillment;
