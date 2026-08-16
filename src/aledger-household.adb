with ALedger.Journal_Loader;
with ALedger.Canonical_Source; use ALedger.Canonical_Source;
with ALedger.Config_Support;
with ALedger.Budget_Source_Adapter;
with ALedger.Plan;
with ALedger.Plan_Observation;

package body ALedger.Household is

   function Empty_Household_State return Household_State is
      State : Household_State;
   begin
      State.Registry            := Empty_Registry;
      State.Actual_Ledger       := Empty_Ledger;
      State.Actual_Evidence.Transactions.Clear;
      State.Plan_Ledger         := Empty_Ledger;
      State.Plan_Evidence.Transactions.Clear;
      State.Budget_Ledger       := Empty_Ledger;
      State.Combined_Ledger     := Empty_Ledger;
      State.Envelope_Registry   := ALedger.Envelope.Empty_Registry;
      State.Routing_History     := ALedger.Envelope_Routing.Empty_History;
      State.Fulfillment_History := ALedger.Fulfillment_Routing.Empty_History;
      State.Entitlement         := ALedger.Envelope_Entitlement.Empty_Observation;
      State.Consumption         := ALedger.Envelope_Consumption.Empty_Consumption;
      return State;
   end Empty_Household_State;

   function Load_Canonical_Household
     (Root_Dir  : String;
      State     : out Household_State;
      Error_Msg : out Unbounded_String) return Boolean
   is
      Result      : Household_State := Empty_Household_State;
      Observation : Source_Observation;
      Config_Diag : ALedger.Config_Support.Config_Diagnostic;

      function Merge_Transactions (From : Ledger.Ledger) return Boolean is
      begin
         for Tx of From.Transactions loop
            declare
               Status : Transaction_Error;
            begin
               if not Add_Transaction (Result.Combined_Ledger, Tx, Status) then
                  Error_Msg := To_Unbounded_String
                    ("validated source produced an inadmissible transaction");
                  return False;
               end if;
            end;
         end loop;
         return True;
      end Merge_Transactions;

      function Load_Named_Journal
        (Source : Source_Name;
         Loaded : out ALedger.Journal_Loader.Journal_Observation)
         return Boolean
      is
      begin
         return ALedger.Journal_Loader.Load_From_Root_Source
           (Root_Path   => Path_For (Observation.Paths, Source),
            Root_Text   => Text_For (Observation, Source),
            Observation => Loaded,
            Error_Msg   => Error_Msg);
      end Load_Named_Journal;

      function Validate_Account
        (Name : String; Expected : Account_Type; Path : String) return Boolean
      is
         Acc    : Account.Account;
         Status : Account_Status;
         Decl   : Account_Declaration;
      begin
         if not Create_Account (Name, Acc, Status)
           or else not Lookup_Declaration (Result.Registry, Acc, Decl)
         then
            Error_Msg := To_Unbounded_String
              (Path & ": Account is not declared in accounts.journal: " & Name);
            return False;
         elsif Decl.Acc_Type /= Expected then
            Error_Msg := To_Unbounded_String
              (Path & ": expected " & Account_Type_Image (Expected) &
               " Account, got " & Account_Type_Image (Decl.Acc_Type) & ": " & Name);
            return False;
         end if;
         return True;
      end Validate_Account;

      function Validate_Ledger_Accounts
        (From : Ledger.Ledger; Path : String) return Boolean
      is
      begin
         for Tx of From.Transactions loop
            for Posting of Tx.Postings loop
               declare
                  Decl : Account_Declaration;
               begin
                  if not Lookup_Declaration
                    (Result.Registry, Posting.Acc, Decl)
                    or else Decl.Acc /= Posting.Acc
                  then
                     Error_Msg := To_Unbounded_String
                       (Path & ": Account is not declared in accounts.journal: " &
                        Account.Name (Posting.Acc));
                     return False;
                  end if;
               end;
            end loop;
         end loop;
         return True;
      end Validate_Ledger_Accounts;

      function Validate_Config_Accounts return Boolean is
         H : ALedger.Household_Config.Household_Configuration
           renames Result.Household_Policy;
      begin
         for Pool of Result.Budget_Policy.Backing_Pools loop
            for Name of Pool.Asset_Accounts loop
               if not Validate_Account
                 (Name, Asset, "budget.toml backing pool")
               then
                  return False;
               end if;
            end loop;
         end loop;

         if not Validate_Account
           (To_String (H.Cycle_Income_Account), Income, "household.toml cycle")
         then
            return False;
         end if;

         for Name of H.Opening_Accounts loop
            if not Validate_Account
              (Name, Budget, "household.toml opening account")
            then
               return False;
            end if;
         end loop;

         for Name of H.Unassigned_Accounts loop
            if not Validate_Account
              (Name, Budget, "household.toml unassigned account")
            then
               return False;
            end if;
         end loop;

         for Env_Coord of H.Envelopes loop
            if not Validate_Account
              (To_String (Env_Coord.Allocation_Account),
               Budget,
               "household.toml allocation account")
            then
               return False;
            end if;
         end loop;

         for Entry of H.Envelope_History.Expense_Routing loop
            if not Validate_Account
              (To_String (Entry.Expense_Account),
               Expense,
               "household.toml expense routing")
            then
               return False;
            end if;
         end loop;

         for Selection of H.Daily_Target_Assets loop
            if not Validate_Account
              (To_String (Selection.Account), Asset, "household.toml Daily Target")
            then
               return False;
            end if;
         end loop;

         return True;
      end Validate_Config_Accounts;

      function Validate_Envelope_References return Boolean is
         H : ALedger.Household_Config.Household_Configuration
           renames Result.Household_Policy;
         Env_Id : ALedger.Envelope.Envelope_Id;
      begin
         for Env_Def of Result.Budget_Policy.Envelopes loop
            if not ALedger.Envelope.Lookup
              (Result.Envelope_Registry, To_String (Env_Def.ID), Env_Id)
            then
               Error_Msg := To_Unbounded_String
                 ("budget.toml: current Envelope missing from " &
                  "envelope-history.identities: " & To_String (Env_Def.ID));
               return False;
            end if;
         end loop;

         for Env_Coord of H.Envelopes loop
            if not ALedger.Envelope.Lookup
              (Result.Envelope_Registry, To_String (Env_Coord.ID), Env_Id)
            then
               Error_Msg := To_Unbounded_String
                 ("household.toml: allocation Envelope missing from " &
                  "envelope-history.identities: " & To_String (Env_Coord.ID));
               return False;
            end if;
         end loop;
         return True;
      end Validate_Envelope_References;
   begin
      if not Observe_Canonical_Sources
        (Root_Dir, Observation, Error_Msg)
      then
         return False;
      end if;

      Result.Root_Path := Observation.Root_Path;
      Result.Paths     := Observation.Paths;
      Result.Sources   := Observation;

      declare
         Accounts : ALedger.Journal_Loader.Journal_Observation;
      begin
         if not Load_Named_Journal (Accounts_Source, Accounts) then
            return False;
         end if;
         Result.Registry := Accounts.Value.Registry;
      end;

      if not ALedger.Budget_Config.Parse_Budget_Policy
        (Text_For (Observation, Budget_Config_Source),
         Result.Budget_Policy, Config_Diag)
      then
         Error_Msg := To_Unbounded_String
           (ALedger.Config_Support.Format_Diagnostic (Config_Diag));
         return False;
      end if;

      if not ALedger.Household_Config.Parse_Household_Configuration
        (Text_For (Observation, Household_Config_Source),
         Result.Budget_Policy, Result.Household_Policy, Config_Diag)
      then
         Error_Msg := To_Unbounded_String
           (ALedger.Config_Support.Format_Diagnostic (Config_Diag));
         return False;
      end if;

      if not ALedger.Report_Config.Parse_Report_Configuration
        (Text_For (Observation, Report_Config_Source),
         Result.Report_Policy, Config_Diag)
      then
         Error_Msg := To_Unbounded_String
           (ALedger.Config_Support.Format_Diagnostic (Config_Diag));
         return False;
      end if;

      if not Validate_Config_Accounts then
         return False;
      end if;

      declare
         Actual : ALedger.Journal_Loader.Journal_Observation;
      begin
         if not Load_Named_Journal (Actual_Source, Actual) then
            return False;
         end if;
         Result.Actual_Ledger   := Actual.Value;
         Result.Actual_Evidence := Actual.Evidence;
      end;
      if not Validate_Ledger_Accounts (Result.Actual_Ledger, "actual.journal") then
         return False;
      end if;
      if not Merge_Transactions (Result.Actual_Ledger) then
         return False;
      end if;

      declare
         Plan : ALedger.Journal_Loader.Journal_Observation;
      begin
         if not Load_Named_Journal (Plan_Source, Plan) then
            return False;
         end if;
         Result.Plan_Ledger   := Plan.Value;
         Result.Plan_Evidence := Plan.Evidence;
      end;
      if not Validate_Ledger_Accounts (Result.Plan_Ledger, "plan.journal") then
         return False;
      end if;

      declare
         Budget : ALedger.Journal_Loader.Journal_Observation;
      begin
         if not Load_Named_Journal (Budget_Journal_Source, Budget) then
            return False;
         end if;
         Result.Budget_Ledger := Budget.Value;
      end;
      if not Validate_Ledger_Accounts (Result.Budget_Ledger, "budget.journal") then
         return False;
      end if;
      if not Merge_Transactions (Result.Budget_Ledger) then
         return False;
      end if;

      if not Parse_Issues_TSV
        (Text_For (Observation, Issues_Source), Result.Issues)
      then
         Error_Msg := To_Unbounded_String
           (Path_For (Observation.Paths, Issues_Source) &
            ": invalid issues.tsv");
         return False;
      end if;

      Result.Combined_Ledger.Registry := Result.Registry;
      Result.Actual_Ledger.Registry   := Result.Registry;
      Result.Plan_Ledger.Registry     := Result.Registry;
      Result.Budget_Ledger.Registry   := Result.Registry;

      --  Envelope identity is historical source data. Never infer the stable
      --  registry from current budget.toml membership.
      if not ALedger.Envelope.Admit_Registry
        (Result.Household_Policy.Envelope_History.Identities,
         Result.Envelope_Registry,
         Config_Diag)
      then
         Error_Msg := To_Unbounded_String
           (ALedger.Config_Support.Format_Diagnostic (Config_Diag));
         return False;
      end if;

      if not Validate_Envelope_References then
         return False;
      end if;

      --  Historical Expense meaning comes only from explicit routing history.
      declare
         use ALedger.Envelope_Routing;
         R_Entries : Routing_Entry_Vectors.Vector;
         H_Status  : History_Status;
      begin
         for Entry_Data of
           Result.Household_Policy.Envelope_History.Expense_Routing
         loop
            declare
               Eff   : Effective_Date;
               Route : Expense_Route;
            begin
               case Entry_Data.Effective.Kind is
                  when ALedger.Household_Config.Initial =>
                     Eff := Initial_Effective_Date;
                  when ALedger.Household_Config.From_Date =>
                     Eff := Dated_Effective (Entry_Data.Effective.Date);
               end case;

               case Entry_Data.Route.Kind is
                  when ALedger.Household_Config.Managed =>
                     declare
                        Target_Id : ALedger.Envelope.Envelope_Id;
                        Found     : constant Boolean :=
                          ALedger.Envelope.Lookup
                            (Result.Envelope_Registry,
                             To_String (Entry_Data.Route.Target),
                             Target_Id);
                     begin
                        if not Found then
                           Error_Msg := To_Unbounded_String
                             ("household.toml: routing target envelope not " &
                              "found in registry: " &
                              To_String (Entry_Data.Route.Target));
                           return False;
                        end if;
                        Route := Managed_Route (Target_Id);
                     end;
                  when ALedger.Household_Config.Not_Managed =>
                     Route := Not_Managed_Route;
               end case;

               R_Entries.Append
                 (Routing_Entry'
                    (Effective => Eff,
                     Expense   => Account.Make_Account
                       (To_String (Entry_Data.Expense_Account)),
                     Route     => Route,
                     Note      => Entry_Data.Note));
            end;
         end loop;

         if not Admit
           (R_Entries,
            Result.Envelope_Registry,
            Result.Routing_History,
            H_Status)
         then
            Error_Msg := To_Unbounded_String
              ("household.toml: failed to admit expense routing history");
            return False;
         end if;
      end;

      if not Result.Household_Policy.Envelope_History.Fulfillment_Routing.Is_Empty then
         declare
            Known_Plans : ALedger.Plan.Plan_Id_Universe;
            Plan_Diag   : ALedger.Plan_Observation.Admission_Diagnostic;
            Decisions   : ALedger.Fulfillment_Routing.Decision_Vectors.Vector;
            F_Status    : ALedger.Fulfillment_Routing.Admission_Status;
         begin
            if not ALedger.Plan_Observation.Admit_Plan_Identities
              (Result.Plan_Ledger,
               Result.Plan_Evidence,
               Known_Plans,
               Plan_Diag)
            then
               Error_Msg := To_Unbounded_String
                 ("plan.journal: failed to admit stable Plan identities: " &
                  ALedger.Plan_Observation.Admission_Status'Image
                    (Plan_Diag.Status) &
                  (if Length (Plan_Diag.Message) > 0
                   then ": " & To_String (Plan_Diag.Message)
                   else ""));
               return False;
            end if;

            for Entry_Data of
              Result.Household_Policy.Envelope_History.Fulfillment_Routing
            loop
               declare
                  PID        : ALedger.Plan.Plan_Id;
                  PID_Status : ALedger.Plan.Plan_Id_Status;
               begin
                  if not ALedger.Plan.Create_Plan_Id
                    (To_String (Entry_Data.Plan_ID), PID, PID_Status)
                  then
                     Error_Msg := To_Unbounded_String
                       ("household.toml: invalid fulfillment-routing PlanId: " &
                        To_String (Entry_Data.Plan_ID));
                     return False;
                  end if;

                  case Entry_Data.Route.Kind is
                     when ALedger.Household_Config.Fulfills =>
                        declare
                           Target_Id     : ALedger.Envelope.Envelope_Id;
                           Target_Status : ALedger.Envelope.Envelope_Id_Status;
                        begin
                           if not ALedger.Envelope.Create_Envelope_Id
                             (To_String (Entry_Data.Route.Target),
                              Target_Id,
                              Target_Status)
                           then
                              Error_Msg := To_Unbounded_String
                                ("household.toml: invalid fulfillment-routing EnvelopeId: " &
                                 To_String (Entry_Data.Route.Target));
                              return False;
                           end if;

                           Decisions.Append
                             (ALedger.Fulfillment_Routing.Fulfillment_Routing_Decision'
                                (Effective_From => Entry_Data.Effective_From,
                                 Plan_ID        => PID,
                                 Route          =>
                                   ALedger.Fulfillment_Routing.Fulfills (Target_Id),
                                 Note           => Entry_Data.Note));
                        end;

                     when ALedger.Household_Config.Not_Target =>
                        Decisions.Append
                          (ALedger.Fulfillment_Routing.Fulfillment_Routing_Decision'
                             (Effective_From => Entry_Data.Effective_From,
                              Plan_ID        => PID,
                              Route          => ALedger.Fulfillment_Routing.Not_Target,
                              Note           => Entry_Data.Note));
                  end case;
               end;
            end loop;

            if not ALedger.Fulfillment_Routing.Admit
              (Decisions,
               Known_Plans,
               Result.Envelope_Registry,
               Result.Fulfillment_History,
               F_Status)
            then
               Error_Msg := To_Unbounded_String
                 ("household.toml: failed to admit fulfillment routing history: " &
                  ALedger.Fulfillment_Routing.Admission_Status'Image (F_Status));
               return False;
            end if;
         end;
      end if;

      declare
         P_Status : ALedger.Backing_Policy.Policy_Status;
      begin
         if not ALedger.Backing_Policy.Admit_Backing_Policy
           (Result.Budget_Policy,
            Result.Envelope_Registry,
            Result.Backing_Policy_Spec,
            P_Status)
         then
            Error_Msg := To_Unbounded_String
              ("budget.toml: failed to admit backing policy");
            return False;
         end if;
      end;

      declare
         Ad_Diag : ALedger.Budget_Source_Adapter.Adapter_Diagnostic;
      begin
         if not ALedger.Budget_Source_Adapter.Observe_Entitlements
           (Result.Budget_Ledger.Transactions,
            Result.Household_Policy,
            Result.Envelope_Registry,
            Result.Entitlement,
            Ad_Diag)
         then
            Error_Msg := To_Unbounded_String
              ("budget.journal: " & To_String (Ad_Diag.Message));
            return False;
         end if;
      end;

      Result.Consumption :=
        ALedger.Envelope_Consumption.Observe_Consumption
          (Result.Actual_Ledger, Result.Routing_History);

      Result.Backing :=
        ALedger.Backing_Policy.Observe_Backing
          (Result.Backing_Policy_Spec,
           Result.Actual_Ledger,
           Result.Entitlement,
           Result.Consumption);

      State := Result;
      Error_Msg := Null_Unbounded_String;
      return True;
   end Load_Canonical_Household;

end ALedger.Household;
