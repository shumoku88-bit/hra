with HRA.Canonical_Source;

package body HRA.Issue_Realization_Resume is

   function World_Of (Prepared : Prepared_Resume) return Recognized_World is
     (Prepared.World);

   function Prepare_Resume
     (State                : HRA.Household.Household_State;
      Tx                   : HRA.Ledger.Transaction;
      Issue_ID             : HRA.Issues.Issue_Id;
      Actual_ID            : HRA.Actual_Admission.Actual_Id;
      Relation_Event_ID    : HRA.Issue_Relation.Relation_Event_Id;
      Relation_Recorded_On : HRA.Dates.Date;
      Closed_On            : HRA.Dates.Date;
      Relation_Details     : String;
      Relation_Observation : HRA.Issue_Relation.Sidecar.Observation;
      Prepared             : out Prepared_Resume;
      Diag                 : out Resume_Diagnostic) return Boolean
   is
      Recognized       : Recognized_World :=
        HRA.Issue_Realization_Reconciliation.W0;
      Reconcile_Diag   : HRA.Issue_Realization_Reconciliation.Reconciliation_Diagnostic;
      Prep_Diag        : HRA.Issue_Realization_Preparation.Preparation_Diagnostic;
      Rel_Cand_Diag    : HRA.Issue_Relation_Candidate.Candidate_Diagnostic;
      Admission_Diag   : HRA.Issue_Relation.Admission.Admission_Diagnostic;
      Close_Diag       : HRA.Issue_Close.Close_Diagnostic;

      procedure Set_Diagnostic
        (Status  : Resume_Status;
         Message : String) is
      begin
         Diag :=
           (Status             => Status,
            Reconciliation     => Reconcile_Diag,
            Preparation        => Prep_Diag,
            Relation_Candidate => Rel_Cand_Diag,
            Relation_Admission => Admission_Diag,
            Issue_Close        => Close_Diag,
            Message            => To_Unbounded_String (Message));
      end Set_Diagnostic;

      function Load_Actual_Graph_Premises return Boolean is
         Actual_Path : constant String :=
           HRA.Canonical_Source.Path_For
             (State.Sources.Paths, HRA.Canonical_Source.Actual_Source);
         Actual_Text : constant String :=
           HRA.Canonical_Source.Text_For
             (State.Sources, HRA.Canonical_Source.Actual_Source);
         Actual_Obs  : HRA.Journal_Loader.Journal_Observation;
         Load_Error  : Unbounded_String;
         Fresh_Actual : HRA.Actual_Admission.Actual_Observation;
         Actual_Diag  : HRA.Actual_Admission.Admission_Diagnostic;
      begin
         if not HRA.Journal_Loader.Load_From_Root_Source
           (Actual_Path, Actual_Text, Actual_Obs, Load_Error)
         then
            Set_Diagnostic
              (Actual_Graph_Load_Failed,
               "failed to load Actual journal graph premises: " &
               To_String (Load_Error));
            return False;
         end if;

         --  Admit the freshly loaded Actual graph and verify that it represents
         --  the exact same authority as the reconciled State.Actual_Identity.
         if not HRA.Actual_Admission.Admit
           (Actual_Ledger   => Actual_Obs.Value,
            Actual_Evidence => Actual_Obs.Evidence,
            Result          => Fresh_Actual,
            Diag            => Actual_Diag)
         then
            Set_Diagnostic
              (Actual_Graph_Load_Failed,
               "freshly loaded Actual graph failed durable identity admission: " &
               HRA.Actual_Admission.Admission_Status'Image (Actual_Diag.Status) &
               (if Length (Actual_Diag.Message) > 0
                then ": " & To_String (Actual_Diag.Message)
                else ""));
            return False;
         end if;

         if not HRA.Actual_Admission.Same_Observation
           (Fresh_Actual, State.Actual_Identity)
         then
            Set_Diagnostic
              (Actual_Graph_Load_Failed,
               "freshly loaded Actual graph authority does not match reconciled Household state");
            return False;
         end if;

         Prepared.Actual_Sources := Actual_Obs.Sources;
         Prepared.Account_Guard  :=
           HRA.Writer.Make_Source_Premise
             (Path     =>
                HRA.Canonical_Source.Path_For
                  (State.Sources.Paths, HRA.Canonical_Source.Accounts_Source),
              Expected =>
                HRA.Writer.Make_Expected_Source
                  (HRA.Canonical_Source.Text_For
                     (State.Sources, HRA.Canonical_Source.Accounts_Source)));
         return True;
      end Load_Actual_Graph_Premises;

      function Prepare_Issue_Close_Candidate
        (Relation_Text : String) return Boolean
      is
         Current_Issues : constant String :=
           HRA.Canonical_Source.Text_For
             (State.Sources, HRA.Canonical_Source.Issues_Source);
         Resolved_Issues : HRA.Issues.Issues_Inventory;
         Issues_Diag     : HRA.Issues.Admission_Diagnostic;
         Admitted_Rel    : HRA.Issue_Relation.Admission.Admitted_History;
         Rel_Diag        : HRA.Issue_Relation.Admission.Admission_Diagnostic;
      begin
         if not HRA.Issue_Close.Prepare_Close
           (Existing_Source => Current_Issues,
            Issue_ID        => Issue_ID,
            Disposition     => HRA.Issue_Close.Resolve_Issue,
            Closed_On       => Closed_On,
            Candidate       => Prepared.Issues_Source,
            Diag            => Close_Diag)
         then
            Set_Diagnostic
              (Issue_Close_Failed,
               "failed to prepare Issue close candidate");
            return False;
         end if;

         Prepared.Issues_Path := To_Unbounded_String
           (HRA.Canonical_Source.Path_For
              (State.Sources.Paths, HRA.Canonical_Source.Issues_Source));
         Prepared.Issues_Observed_Text := To_Unbounded_String (Current_Issues);
         Prepared.Issues_Guard := HRA.Writer.Make_Source_Premise
           (Path     => To_String (Prepared.Issues_Path),
            Expected => HRA.Writer.Make_Expected_Source (Current_Issues));

         if not HRA.Issues.Admit_Issues_TSV
           (HRA.Issue_Close.Text (Prepared.Issues_Source),
            Resolved_Issues,
            Issues_Diag)
           or else not HRA.Issue_Relation.Admission.Admit
             (Relation_Text,
              Resolved_Issues,
              State.Actual_Identity,
              Admitted_Rel,
              Rel_Diag)
         then
            Set_Diagnostic
              (Cross_Admission_Failed,
               "relation does not cross-admit with resolved issues candidate");
            return False;
         end if;

         return True;
      end Prepare_Issue_Close_Candidate;

   begin
      Prepared := (World => HRA.Issue_Realization_Reconciliation.W0,
                   others => <>);

      if not HRA.Issue_Realization_Reconciliation.Reconcile
        (State                => State,
         Tx                   => Tx,
         Issue_ID             => Issue_ID,
         Actual_ID            => Actual_ID,
         Relation_Event_ID    => Relation_Event_ID,
         Relation_Recorded_On => Relation_Recorded_On,
         Closed_On            => Closed_On,
         Relation_Details     => Relation_Details,
         Relation_Observation => Relation_Observation,
         World                => Recognized,
         Diag                 => Reconcile_Diag)
      then
         Set_Diagnostic
           (Reconciliation_Failed,
            "reconciliation failed: " & To_String (Reconcile_Diag.Message));
         return False;
      end if;

      Prepared.World := Recognized;

      case Recognized is
         when HRA.Issue_Realization_Reconciliation.W0 =>
            if not HRA.Issue_Realization_Preparation.Prepare
              (State                => State,
               Tx                   => Tx,
               Issue_ID             => Issue_ID,
               Actual_ID            => Actual_ID,
               Relation_Event_ID    => Relation_Event_ID,
               Relation_Recorded_On => Relation_Recorded_On,
               Closed_On            => Closed_On,
               Relation_Details     => Relation_Details,
               Relation_Observation => Relation_Observation,
               Prepared             => Prepared.W0_Prepared,
               Diag                 => Prep_Diag)
            then
               Set_Diagnostic
                 (W0_Preparation_Failed,
                  "W0 full realization preparation failed: " &
                  To_String (Prep_Diag.Message));
               return False;
            end if;

         when HRA.Issue_Realization_Reconciliation.W1 =>
            if not Load_Actual_Graph_Premises then
               return False;
            end if;

            declare
               Event         : HRA.Issue_Relation.Relation_Event;
               Create_Status : HRA.Issue_Relation.Create_Status :=
                 HRA.Issue_Relation.Create_Success;
            begin
               if not HRA.Issue_Relation.Create_Realized_As
                 (Event_ID    => Relation_Event_ID,
                  Recorded_On => Relation_Recorded_On,
                  Issue_ID    => Issue_ID,
                  Actual_ID   => Actual_ID,
                  Details     => Relation_Details,
                  Event       => Event,
                  Status      => Create_Status)
               then
                  Set_Diagnostic
                    (Relation_Candidate_Failed,
                     "failed to create Realized_As relation event");
                  return False;
               end if;

               if not HRA.Issue_Relation_Candidate.Prepare
                 (Observed  => Relation_Observation,
                  Event     => Event,
                  Candidate => Prepared.W1_Relation_Source,
                  Diag      => Rel_Cand_Diag)
               then
                  Set_Diagnostic
                    (Relation_Candidate_Failed,
                     "failed to prepare relation candidate source");
                  return False;
               end if;

               if not HRA.Issue_Relation.Admission.Admit
                 (HRA.Issue_Relation_Candidate.Text
                    (Prepared.W1_Relation_Source),
                  State.Issues,
                  State.Actual_Identity,
                  Prepared.W1_Relation_History,
                  Admission_Diag)
               then
                  Set_Diagnostic
                    (Relation_Admission_Failed,
                     "relation candidate does not admit against current endpoints");
                  return False;
               end if;

               if not Prepare_Issue_Close_Candidate
                 (HRA.Issue_Relation_Candidate.Text
                    (Prepared.W1_Relation_Source))
               then
                  return False;
               end if;
            end;

         when HRA.Issue_Realization_Reconciliation.W2 =>
            if not Load_Actual_Graph_Premises then
               return False;
            end if;

            Prepared.W2_Relation_Guard :=
              HRA.Writer.Make_Source_Premise
                (Path     =>
                   HRA.Issue_Relation.Sidecar.Path_Of (Relation_Observation),
                 Expected =>
                   HRA.Writer.Make_Expected_Source
                     (HRA.Issue_Relation.Sidecar.Text_Of
                        (Relation_Observation)));

            if not HRA.Issue_Relation.Admission.Admit
              (HRA.Issue_Relation.Sidecar.Text_Of (Relation_Observation),
               State.Issues,
               State.Actual_Identity,
               Prepared.W2_Relation_History,
               Admission_Diag)
            then
               Set_Diagnostic
                 (Relation_Admission_Failed,
                  "existing relation sidecar does not admit against current endpoints");
               return False;
            end if;

            if not Prepare_Issue_Close_Candidate
              (HRA.Issue_Relation.Sidecar.Text_Of (Relation_Observation))
            then
               return False;
            end if;

         when HRA.Issue_Realization_Reconciliation.W3 =>
            null;
      end case;

      Set_Diagnostic (Success, "");
      return True;
   end Prepare_Resume;

end HRA.Issue_Realization_Resume;
