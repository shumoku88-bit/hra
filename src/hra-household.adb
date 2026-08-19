with HRA.Journal_Loader;
with HRA.Canonical_Source; use HRA.Canonical_Source;
with HRA.Config_Support;
with HRA.Budget_Source_Adapter;
with HRA.Plan_Observation;

package body HRA.Household is

   function Empty_Household_State return Household_State is
      State : Household_State;
   begin
      State.Registry            := Empty_Registry;
      State.Actual_Ledger       := Empty_Ledger;
      State.Actual_Evidence.Transactions.Clear;
      State.Actual_Identity     := HRA.Actual_Admission.Empty_Observation;
      State.Plan_Ledger         := Empty_Ledger;
      State.Plan_Evidence.Transactions.Clear;
      State.Plan_Ids            := HRA.Plan.Empty_Plan_Id_Universe;
      State.Budget_Ledger       := Empty_Ledger;
      State.Combined_Ledger     := Empty_Ledger;
      State.Envelope_Registry   := HRA.Envelope.Empty_Registry;
      State.Routing_History     := HRA.Envelope_Routing.Empty_History;
      State.Fulfillment_History := HRA.Fulfillment_Routing.Empty_History;
      return State;
   end Empty_Household_State;

   function Admit_Canonical_Household
     (Observation : HRA.Canonical_Source.Source_Observation;
      State       : out Household_State;
      Error_Msg   : out Unbounded_String) return Boolean
   is
      Result      : Household_State := Empty_Household_State;
      Config_Diag : HRA.Config_Support.Config_Diagnostic;

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
         Loaded : out HRA.Journal_Loader.Journal_Observation)
         return Boolean
      is
      begin
         return HRA.Journal_Loader.Load_From_Root_Source
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
         H : HRA.Household_Config.Household_Configuration
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

         for Routing_Entry of H.Envelope_History.Expense_Routing loop
            if not Validate_Account
              (To_String (Routing_Entry.Expense_Account),
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
         H : HRA.Household_Config.Household_Configuration
           renames Result.Household_Policy;
         Env_Id : HRA.Envelope.Envelope_Id;
      begin
         for Env_Def of Result.Budget_Policy.Envelopes loop
            if not HRA.Envelope.Lookup
              (Result.Envelope_Registry, To_String (Env_Def.ID), Env_Id)
            then
               Error_Msg := To_Unbounded_String
                 ("budget.toml: current Envelope missing from " &
                  "envelope-history.identities: " & To_String (Env_Def.ID));
               return False;
            end if;
         end loop;

         for Env_Coord of H.Envelopes loop
            if not HRA.Envelope.Lookup
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
      Result.Root_Path := Observation.Root_Path;
      Result.Paths     := Observation.Paths;
      Result.Sources   := Observation;

      declare
         Accounts : HRA.Journal_Loader.Journal_Observation;
      begin
         if not Load_Named_Journal (Accounts_Source, Accounts) then
            return False;
         end if;
         Result.Registry := Accounts.Value.Registry;
      end;

      if not HRA.Budget_Config.Parse_Budget_Policy
        (Text_For (Observation, Budget_Config_Source),
         Result.Budget_Policy, Config_Diag)
      then
         Error_Msg := To_Unbounded_String
           (HRA.Config_Support.Format_Diagnostic (Config_Diag));
         return False;
      end if;

      if not HRA.Household_Config.Parse_Household_Configuration
        (Text_For (Observation, Household_Config_Source),
         Result.Budget_Policy, Result.Household_Policy, Config_Diag)
      then
         Error_Msg := To_Unbounded_String
           (HRA.Config_Support.Format_Diagnostic (Config_Diag));
         return False;
      end if;

      if not HRA.Report_Config.Parse_Report_Configuration
        (Text_For (Observation, Report_Config_Source),
         Result.Report_Policy, Config_Diag)
      then
         Error_Msg := To_Unbounded_String
           (HRA.Config_Support.Format_Diagnostic (Config_Diag));
         return False;
      end if;

      if not Validate_Config_Accounts then
         return False;
      end if;

      declare
         Actual : HRA.Journal_Loader.Journal_Observation;
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

      --  Registry is part of the Ledger observation admitted as canonical
      --  Actual. Attach it before admission so the opaque Actual value never
      --  requires post-admission mutation.
      Result.Actual_Ledger.Registry := Result.Registry;

      declare
         Actual_Diag : HRA.Actual_Admission.Admission_Diagnostic;
      begin
         if not HRA.Actual_Admission.Admit
           (Result.Actual_Ledger,
            Result.Actual_Evidence,
            Result.Actual_Identity,
            Actual_Diag)
         then
            Error_Msg := To_Unbounded_String
              ("actual.journal: failed durable identity admission: " &
               HRA.Actual_Admission.Admission_Status'Image
                 (Actual_Diag.Status) &
               (if Length (Actual_Diag.Actual_Id) > 0
                then " [actual-id=" & To_String (Actual_Diag.Actual_Id) & "]"
                else "") &
               (if Length (Actual_Diag.Message) > 0
                then ": " & To_String (Actual_Diag.Message)
                else ""));
            return False;
         end if;
      end;

      --  From this point forward, production consumers see only identity and
      --  reversal coordinates admitted from retained Journal source evidence.
      --  The Journal parser's description-derived compatibility fields cannot
      --  become a second authority path.
      Result.Actual_Ledger :=
        HRA.Actual_Admission.Ledger_Of (Result.Actual_Identity);
      if not Merge_Transactions (Result.Actual_Ledger) then
         return False;
      end if;

      declare
         Plan : HRA.Journal_Loader.Journal_Observation;
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
         Plan_Diag : HRA.Plan_Observation.Admission_Diagnostic;
      begin
         if not HRA.Plan_Observation.Admit_Plan_Identities
           (Result.Plan_Ledger,
            Result.Plan_Evidence,
            Result.Plan_Ids,
            Plan_Diag)
         then
            Error_Msg := To_Unbounded_String
              ("plan.journal: failed stable Plan identity admission: " &
               HRA.Plan_Observation.Admission_Status'Image
                 (Plan_Diag.Status) &
               (if Length (Plan_Diag.Plan_Id) > 0
                then " [plan-id=" & To_String (Plan_Diag.Plan_Id) & "]"
                else "") &
               (if Length (Plan_Diag.Message) > 0
                then ": " & To_String (Plan_Diag.Message)
                else ""));
            return False;
         end if;
      end;

      --  Completion is a cross-source admission law, not a report-time guess.
      --  Every Actual plan-id must resolve to one admitted Plan and a Plan may
      --  be completed by at most one Actual transaction.
      declare
         Completion_Diag : HRA.Plan_Observation.Admission_Diagnostic;
      begin
         if not HRA.Plan_Observation.Admit_Plan_Completions
           (Result.Plan_Ids,
            Result.Actual_Ledger,
            Result.Actual_Evidence,
            Completion_Diag)
         then
            Error_Msg := To_Unbounded_String
              ("actual.journal: failed Plan completion admission: " &
               HRA.Plan_Observation.Admission_Status'Image
                 (Completion_Diag.Status) &
               (if Length (Completion_Diag.Plan_Id) > 0
                then " [plan-id=" & To_String (Completion_Diag.Plan_Id) & "]"
                else "") &
               (if Length (Completion_Diag.Message) > 0
                then ": " & To_String (Completion_Diag.Message)
                else ""));
            return False;
         end if;
      end;

      declare
         Budget : HRA.Journal_Loader.Journal_Observation;
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

      declare
         Issues_Diag : HRA.Issues.Admission_Diagnostic;
      begin
         if not HRA.Issues.Admit_Issues_TSV
           (Text_For (Observation, Issues_Source), Result.Issues, Issues_Diag)
         then
            Error_Msg := To_Unbounded_String
              (Path_For (Observation.Paths, Issues_Source) & ":" &
               (if Issues_Diag.Line_Number > 0
                then Natural'Image (Issues_Diag.Line_Number) & ":"
                else "") &
               " failed Issues admission: " &
               HRA.Issues.Admission_Status'Image (Issues_Diag.Status) &
               (if Length (Issues_Diag.Issue_ID) > 0
                then " [issue-id=" & To_String (Issues_Diag.Issue_ID) & "]"
                else "") &
               (if Length (Issues_Diag.Message) > 0
                then ": " & To_String (Issues_Diag.Message)
                else ""));
            return False;
         end if;
      end;

      Result.Combined_Ledger.Registry := Result.Registry;
      Result.Actual_Ledger.Registry   := Result.Registry;
      Result.Plan_Ledger.Registry     := Result.Registry;
      Result.Budget_Ledger.Registry   := Result.Registry;

      --  Envelope identity is historical source data. Never infer the stable
      --  registry from current budget.toml membership.
      if not HRA.Envelope.Admit_Registry
        (Result.Household_Policy.Envelope_History.Identities,
         Result.Envelope_Registry,
         Config_Diag)
      then
         Error_Msg := To_Unbounded_String
           (HRA.Config_Support.Format_Diagnostic (Config_Diag));
         return False;
      end if;

      if not Validate_Envelope_References then
         return False;
      end if;

      --  Historical Expense meaning comes only from explicit routing history.
      declare
         use HRA.Envelope_Routing;
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
                  when HRA.Household_Config.Initial =>
                     Eff := Initial_Effective_Date;
                  when HRA.Household_Config.From_Date =>
                     Eff := Dated_Effective (Entry_Data.Effective.Date);
               end case;

               case Entry_Data.Route.Kind is
                  when HRA.Household_Config.Managed =>
                     declare
                        Target_Id : HRA.Envelope.Envelope_Id;
                        Found     : constant Boolean :=
                          HRA.Envelope.Lookup
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
                  when HRA.Household_Config.Not_Managed =>
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
            Decisions : HRA.Fulfillment_Routing.Decision_Vectors.Vector;
            F_Status  : HRA.Fulfillment_Routing.Admission_Status;
         begin
            for Entry_Data of
              Result.Household_Policy.Envelope_History.Fulfillment_Routing
            loop
               declare
                  PID        : HRA.Plan.Plan_Id;
                  PID_Status : HRA.Plan.Plan_Id_Status;
               begin
                  if not HRA.Plan.Create_Plan_Id
                    (To_String (Entry_Data.Plan_ID), PID, PID_Status)
                  then
                     Error_Msg := To_Unbounded_String
                       ("household.toml: invalid fulfillment-routing PlanId: " &
                        To_String (Entry_Data.Plan_ID));
                     return False;
                  end if;

                  case Entry_Data.Route.Kind is
                     when HRA.Household_Config.Fulfills =>
                        declare
                           Target_Id     : HRA.Envelope.Envelope_Id;
                           Target_Status : HRA.Envelope.Envelope_Id_Status;
                        begin
                           if not HRA.Envelope.Create_Envelope_Id
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
                             (HRA.Fulfillment_Routing.Fulfillment_Routing_Decision'
                                (Effective_From => Entry_Data.Effective_From,
                                 Plan_ID        => PID,
                                 Route          =>
                                   HRA.Fulfillment_Routing.Fulfills (Target_Id),
                                 Note           => Entry_Data.Note));
                        end;

                     when HRA.Household_Config.Not_Target =>
                        Decisions.Append
                          (HRA.Fulfillment_Routing.Fulfillment_Routing_Decision'
                             (Effective_From => Entry_Data.Effective_From,
                              Plan_ID        => PID,
                              Route          => HRA.Fulfillment_Routing.Not_Target,
                              Note           => Entry_Data.Note));
                  end case;
               end;
            end loop;

            if not HRA.Fulfillment_Routing.Admit
              (Decisions,
               Result.Plan_Ids,
               Result.Envelope_Registry,
               Result.Fulfillment_History,
               F_Status)
            then
               Error_Msg := To_Unbounded_String
                 ("household.toml: failed to admit fulfillment routing history: " &
                  HRA.Fulfillment_Routing.Admission_Status'Image (F_Status));
               return False;
            end if;
         end;
      end if;

      --  Budget source shape and endpoint meaning are admission laws. Validate
      --  the complete source here, but do not retain a time-dependent
      --  Entitlement observation in Household_State.
      declare
         Movements : HRA.Budget_Source_Adapter.Movement_Vectors.Vector;
         Ad_Diag   : HRA.Budget_Source_Adapter.Adapter_Diagnostic;
      begin
         if not HRA.Budget_Source_Adapter.Adapt_Budget_Journal
           (Result.Budget_Ledger.Transactions,
            Result.Household_Policy,
            Result.Envelope_Registry,
            Movements,
            Ad_Diag)
         then
            Error_Msg := To_Unbounded_String
              ("budget.journal: " & To_String (Ad_Diag.Message));
            return False;
         end if;
      end;

      declare
         P_Status : HRA.Backing_Policy.Policy_Status;
      begin
         if not HRA.Backing_Policy.Admit_Backing_Policy
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

      State := Result;
      Error_Msg := Null_Unbounded_String;
      return True;
   end Admit_Canonical_Household;

   function Load_Canonical_Household
     (Root_Dir  : String;
      State     : out Household_State;
      Error_Msg : out Unbounded_String) return Boolean
   is
      Observation : Source_Observation;
   begin
      if not Observe_Canonical_Sources
        (Root_Dir, Observation, Error_Msg)
      then
         return False;
      end if;

      return Admit_Canonical_Household (Observation, State, Error_Msg);
   end Load_Canonical_Household;

end HRA.Household;
