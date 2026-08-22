with HRA.Canonical_Source;

package body HRA.Issue_Realization_Preparation is

   function Actual_Observation_Of
     (Prepared : Prepared_Realization)
      return HRA.Actual_Admission.Actual_Observation is
     (HRA.Household_Actual_Preparation.Observation_Of (Prepared.Actual));

   function Prepare
     (State                : HRA.Household.Household_State;
      Tx                   : HRA.Ledger.Transaction;
      Issue_ID             : HRA.Issues.Issue_Id;
      Actual_ID            : HRA.Actual_Admission.Actual_Id;
      Relation_Event_ID    : HRA.Issue_Relation.Relation_Event_Id;
      Relation_Recorded_On : HRA.Dates.Date;
      Closed_On            : HRA.Dates.Date;
      Relation_Details     : String;
      Relation_Observation : HRA.Issue_Relation.Sidecar.Observation;
      Prepared             : out Prepared_Realization;
      Diag                 : out Preparation_Diagnostic) return Boolean
   is
      Actual             : HRA.Household_Actual_Preparation.Prepared_Actual;
      Actual_Diag        : HRA.Household_Actual_Preparation.Preparation_Diagnostic;
      Event              : HRA.Issue_Relation.Relation_Event;
      Creation_Status    : HRA.Issue_Relation.Create_Status :=
        HRA.Issue_Relation.Create_Success;
      Relation_Source    : HRA.Issue_Relation_Candidate.Candidate_Source;
      Relation_Diag      : HRA.Issue_Relation_Candidate.Candidate_Diagnostic;
      Relation_History   : HRA.Issue_Relation.Admission.Admitted_History;
      Admission_Diag     : HRA.Issue_Relation.Admission.Admission_Diagnostic;
      Issues_Source      : HRA.Issue_Close.Candidate_Source;
      Close_Diag         : HRA.Issue_Close.Close_Diagnostic;
      Current_Issues     : constant String :=
        HRA.Canonical_Source.Text_For
          (State.Sources, HRA.Canonical_Source.Issues_Source);
      Issues_Guard       : constant HRA.Writer.Source_Premise :=
        HRA.Writer.Make_Source_Premise
          (Path =>
             HRA.Canonical_Source.Path_For
               (State.Sources.Paths, HRA.Canonical_Source.Issues_Source),
           Expected => HRA.Writer.Make_Expected_Source (Current_Issues));

      procedure Set_Diagnostic
        (Status  : Preparation_Status;
         Message : String) is
      begin
         Diag :=
           (Status             => Status,
            Actual             => Actual_Diag,
            Relation_Creation  => Creation_Status,
            Relation_Candidate => Relation_Diag,
            Relation_Admission => Admission_Diag,
            Issue_Close        => Close_Diag,
            Message            => To_Unbounded_String (Message));
      end Set_Diagnostic;
   begin
      if not HRA.Household_Actual_Preparation.Prepare_Identified
        (State, Tx, Actual_ID, Actual, Actual_Diag)
      then
         Set_Diagnostic
           (Actual_Preparation_Rejected,
            "identified Actual preparation rejected");
         return False;
      end if;

      if not HRA.Issue_Relation.Sidecar.Is_For_Root
        (Relation_Observation, To_String (State.Root_Path))
      then
         Set_Diagnostic
           (Relation_Observation_Root_Mismatch,
            "Issue relation observation belongs to a different Household root");
         return False;
      end if;

      if not HRA.Issue_Relation.Create_Realized_As
        (Event_ID    => Relation_Event_ID,
         Recorded_On => Relation_Recorded_On,
         Issue_ID    => Issue_ID,
         Actual_ID   => Actual_ID,
         Details     => Relation_Details,
         Event       => Event,
         Status      => Creation_Status)
      then
         Set_Diagnostic
           (Relation_Creation_Rejected,
            "Realized_As relation creation rejected");
         return False;
      end if;

      if not HRA.Issue_Relation_Candidate.Prepare
        (Relation_Observation, Event, Relation_Source, Relation_Diag)
      then
         Set_Diagnostic
           (Relation_Candidate_Rejected,
            "Issue relation source candidate rejected");
         return False;
      end if;

      --  This is the composition's central cross-source law. The candidate
      --  relation is admitted against the candidate Actual world, not the
      --  pre-publication State.Actual_Identity universe.
      if not HRA.Issue_Relation.Admission.Admit
        (HRA.Issue_Relation_Candidate.Text (Relation_Source),
         State.Issues,
         HRA.Household_Actual_Preparation.Observation_Of (Actual),
         Relation_History,
         Admission_Diag)
      then
         Set_Diagnostic
           (Relation_Reference_Admission_Rejected,
            "Issue relation candidate reference admission rejected");
         return False;
      end if;

      if not HRA.Issue_Close.Prepare_Close
        (Existing_Source => Current_Issues,
         Issue_ID        => Issue_ID,
         Disposition     => HRA.Issue_Close.Resolve_Issue,
         Closed_On       => Closed_On,
         Candidate       => Issues_Source,
         Diag            => Close_Diag)
      then
         Set_Diagnostic
           (Issue_Close_Rejected,
            "Issue resolve candidate rejected");
         return False;
      end if;

      Prepared :=
        (Actual           => Actual,
         Relation_Source  => Relation_Source,
         Relation_History => Relation_History,
         Issues_Source    => Issues_Source,
         Issues_Guard     => Issues_Guard);
      Set_Diagnostic (Success, "");
      return True;
   end Prepare;

end HRA.Issue_Realization_Preparation;
