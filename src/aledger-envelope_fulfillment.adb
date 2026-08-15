with Ada.Containers.Indefinite_Ordered_Maps;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with ALedger.Account;
with ALedger.Envelope;
with ALedger.Fulfillment_Routing;
with ALedger.Money;
with ALedger.Plan;

package body ALedger.Envelope_Fulfillment is

   use type ALedger.Account.Account;
   use type ALedger.Account.Account_Type;
   use type ALedger.Fulfillment_Routing.Fulfillment_Route_Kind;
   use type ALedger.Money.Commodity;
   use type ALedger.Money.Quantity;

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

   function Empty_Fulfillment return Envelope_Fulfillment is
   begin
      return
        (Observed_Through => Null_Unbounded_String,
         Managed          => Envelope_Amounts_Maps.Empty_Map,
         Evidence         => Evidence_Vectors.Empty_Vector);
   end Empty_Fulfillment;

   procedure Add_Managed
     (Obs     : in out Envelope_Fulfillment;
      Env     : ALedger.Envelope.Envelope_Id;
      Amounts : Fulfillment_Amounts)
   is
      Key : constant String := ALedger.Envelope.Image (Env);
   begin
      if Obs.Managed.Contains (Key) then
         Obs.Managed.Replace
           (Key, Add_Amounts (Obs.Managed.Element (Key), Amounts));
      else
         Obs.Managed.Insert (Key, Amounts);
      end if;
   end Add_Managed;

   function Observe
     (Completed        : ALedger.Plan_Observation.Completed_Plan_Vectors.Vector;
      Actual_Ledger    : ALedger.Ledger.Ledger;
      Registry         : ALedger.Account.Account_Registry;
      Routing          : ALedger.Fulfillment_Routing.Fulfillment_Routing_History;
      Observed_Through : String;
      Result           : out Envelope_Fulfillment;
      Diag             : out Observe_Diagnostic) return Boolean
   is
      Output           : Envelope_Fulfillment := Empty_Fulfillment;
      Event_Index      : String_Natural_Maps.Map;
      Reversal_Targets : String_Maps.Map;

      procedure Fail
        (Status  : Observe_Status;
         Plan_ID : ALedger.Plan.Plan_Id;
         Message : String)
      is
      begin
         Diag :=
           (Status  => Status,
            Plan_Id => To_Unbounded_String
              ((if ALedger.Plan.Is_Null (Plan_ID)
                then "" else ALedger.Plan.Text (Plan_ID))),
            Message => To_Unbounded_String (Message));
      end Fail;

      function Direction (Q : ALedger.Money.Quantity) return Integer is
      begin
         if Q > ALedger.Money.Zero_Quantity then
            return 1;
         elsif Q < ALedger.Money.Zero_Quantity then
            return -1;
         else
            return 0;
         end if;
      end Direction;

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

         --  A reversal cycle cannot be evidence for a stable root completion.
         return Null_Unbounded_String;
      end Root_Event_Id;

      function Reversal_Shape_Matches
        (Candidate, Root : ALedger.Ledger.Transaction) return Boolean
      is
      begin
         if Natural (Candidate.Postings.Length) /= Natural (Root.Postings.Length) then
            return False;
         end if;

         for I in 1 .. Natural (Root.Postings.Length) loop
            declare
               C : constant ALedger.Ledger.Posting := Candidate.Postings.Element (I);
               R : constant ALedger.Ledger.Posting := Root.Postings.Element (I);
            begin
               if C.Acc /= R.Acc or else C.Amt.Comm /= R.Amt.Comm then
                  return False;
               end if;
            end;
         end loop;
         return True;
      end Reversal_Shape_Matches;

   begin
      Output.Observed_Through := To_Unbounded_String (Observed_Through);
      Result := Output;
      Diag :=
        (Status  => Success,
         Plan_Id => Null_Unbounded_String,
         Message => Null_Unbounded_String);

      --  Stable Actual identity and reversal relation are already carried by the
      --  admitted Ledger. Build only an observation index; do not infer links.
      for I in 1 .. Natural (Actual_Ledger.Transactions.Length) loop
         declare
            Tx     : constant ALedger.Ledger.Transaction :=
              Actual_Ledger.Transactions.Element (I);
            Ev_Id  : constant String := To_String (Tx.Event_ID);
            Rev_Id : constant String := To_String (Tx.Reverses_ID);
         begin
            if Ev_Id'Length > 0 then
               if Event_Index.Contains (Ev_Id) then
                  Fail
                    (Duplicate_Actual_Event_Id,
                     ALedger.Plan.Null_Plan_Id,
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
            Completion_Date : constant String := To_String (Pair.Actual_Tx.Date_Text);
            Decision        : ALedger.Fulfillment_Routing.Fulfillment_Routing_Decision;
         begin
            if Completion_Date <= Observed_Through
              and then ALedger.Fulfillment_Routing.Resolve_Decision
                (Routing, Pair.ID, Completion_Date, Decision)
              and then Decision.Route.Kind =
                ALedger.Fulfillment_Routing.Fulfills_Envelope
            then
               declare
                  Plan_Count   : constant Natural := Natural (Pair.Plan_Tx.Postings.Length);
                  Actual_Count : constant Natural := Natural (Pair.Actual_Tx.Postings.Length);
                  Root_Id      : constant String := To_String (Pair.Actual_Tx.Event_ID);
                  Reverses_Id  : constant String := To_String (Pair.Actual_Tx.Reverses_ID);
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

                  --  Validate the whole root Plan/Actual shape before selecting
                  --  non-Expense target positions.
                  for I in 1 .. Plan_Count loop
                     declare
                        Plan_Post   : constant ALedger.Ledger.Posting :=
                          Pair.Plan_Tx.Postings.Element (I);
                        Actual_Post : constant ALedger.Ledger.Posting :=
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
                        Plan_Post : constant ALedger.Ledger.Posting :=
                          Pair.Plan_Tx.Postings.Element (I);
                        Category  : ALedger.Account.Account_Type;
                        Known     : constant Boolean :=
                          ALedger.Account.Account_Type_For
                            (Registry, Plan_Post.Acc, Category);
                     begin
                        if not Known then
                           Fail
                             (Undeclared_Plan_Account,
                              Pair.ID,
                              "completed Plan references undeclared Account: " &
                                ALedger.Account.Name (Plan_Post.Acc));
                           return False;
                        end if;

                        if Plan_Post.Amt.Val > ALedger.Money.Zero_Quantity
                          and then Category /= ALedger.Account.Expense
                        then
                           declare
                              Amounts : Fulfillment_Amounts := Empty_Amounts;
                           begin
                              for Tx of Actual_Ledger.Transactions loop
                                 declare
                                    Tx_Date : constant String := To_String (Tx.Date_Text);
                                    Ev_Id   : constant String := To_String (Tx.Event_ID);
                                 begin
                                    if Tx_Date <= Observed_Through
                                      and then Ev_Id'Length > 0
                                      and then To_String (Root_Event_Id (Ev_Id)) = Root_Id
                                    then
                                       if not Reversal_Shape_Matches
                                         (Tx, Pair.Actual_Tx)
                                       then
                                          Fail
                                            (Reversal_Shape_Mismatch,
                                             Pair.ID,
                                             "Fulfillment reversal chain must preserve root Account/Commodity shape");
                                          return False;
                                       end if;

                                       declare
                                          Amount : constant ALedger.Money.Amount :=
                                            Tx.Postings.Element (I).Amt;
                                       begin
                                          if Amount.Val > ALedger.Money.Zero_Quantity then
                                             Amounts.Applied := Add_Balance
                                               (Amounts.Applied,
                                                Singleton_Balance (Amount));
                                          elsif Amount.Val < ALedger.Money.Zero_Quantity then
                                             Amounts.Reversed := Add_Balance
                                               (Amounts.Reversed,
                                                Singleton_Balance
                                                  (ALedger.Money.Negate_Amount (Amount)));
                                          end if;
                                       end;
                                    end if;
                                 end;
                              end loop;

                              Add_Managed (Output, Decision.Route.Target, Amounts);
                              Output.Evidence.Append
                                (Fulfillment_Evidence'
                                   (Plan_ID              => Pair.ID,
                                    Envelope_ID          => Decision.Route.Target,
                                    Completion_Date      => Pair.Actual_Tx.Date_Text,
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
   end Observe;

   function Fulfillment_For
     (Obs : Envelope_Fulfillment;
      Env : ALedger.Envelope.Envelope_Id) return Fulfillment_Amounts
   is
      Key : constant String := ALedger.Envelope.Image (Env);
   begin
      if Obs.Managed.Contains (Key) then
         return Obs.Managed.Element (Key);
      else
         return Empty_Amounts;
      end if;
   end Fulfillment_For;

   function Net_For
     (Obs : Envelope_Fulfillment;
      Env : ALedger.Envelope.Envelope_Id) return Balance
   is
   begin
      return Net_Fulfillment (Fulfillment_For (Obs, Env));
   end Net_For;

end ALedger.Envelope_Fulfillment;
