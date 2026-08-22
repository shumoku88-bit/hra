with HRA.Actual_Publication;
with HRA.Household_Actual_Preparation.Publication;
with HRA.Issue_Relation.Sidecar;

package body HRA.Issue_Realization_Preparation.Publication is

   use type HRA.Actual_Publication.Publication_Status;
   use type HRA.Issue_Relation.Sidecar.Presence;

   function Relation_Expected
     (Candidate : HRA.Issue_Relation_Candidate.Candidate_Source)
      return HRA.Writer.Expected_Source is
     (if HRA.Issue_Relation_Candidate.Observed_State_Of (Candidate) =
          HRA.Issue_Relation.Sidecar.Absent
      then HRA.Writer.Make_Absent_Expected_Source
      else HRA.Writer.Make_Expected_Source
        (HRA.Issue_Relation_Candidate.Observed_Text (Candidate)));

   function Relation_Observed_Premise
     (Candidate : HRA.Issue_Relation_Candidate.Candidate_Source)
      return HRA.Writer.Source_Premise is
     (HRA.Writer.Make_Source_Premise
        (HRA.Issue_Relation_Candidate.Path_Of (Candidate),
         Relation_Expected (Candidate)));

   function Relation_Published_Premise
     (Candidate : HRA.Issue_Relation_Candidate.Candidate_Source)
      return HRA.Writer.Source_Premise is
     (HRA.Writer.Make_Source_Premise
        (HRA.Issue_Relation_Candidate.Path_Of (Candidate),
         HRA.Writer.Make_Expected_Source
           (HRA.Issue_Relation_Candidate.Text (Candidate))));

   function Publish
     (Prepared : Prepared_Realization;
      Result   : out Publication_Result) return Boolean
   is
      Actual_Diag : HRA.Actual_Publication.Publication_Diagnostic;
      Writer_Status : HRA.Writer.Writer_Status := HRA.Writer.Success;
      Writer_Error  : Unbounded_String;
      Open_Issues   : HRA.Issues.Issues_Inventory;
      Resolved_Issues : HRA.Issues.Issues_Inventory;
      Issues_Diag   : HRA.Issues.Admission_Diagnostic;
      Admitted_Relations : HRA.Issue_Relation.Admission.Admitted_History;
      Relation_Diag : HRA.Issue_Relation.Admission.Admission_Diagnostic;

      procedure Fail
        (World   : Confirmed_World;
         Step    : Publication_Step;
         Kind    : Failure_Kind;
         Status  : HRA.Writer.Writer_Status;
         Message : String) is
      begin
         Result :=
           (Kind           => Failed,
            Last_Confirmed => World,
            Writer_Status  => Status,
            Message        => To_Unbounded_String (Message),
            Failed_Step    => Step,
            Failure        => Kind);
      end Fail;

      function Admit_Relations
        (Issues : HRA.Issues.Issues_Inventory) return Boolean is
      begin
         return HRA.Issue_Relation.Admission.Admit
           (HRA.Issue_Relation_Candidate.Text (Prepared.Relation_Source),
            Issues,
            HRA.Household_Actual_Preparation.Observation_Of (Prepared.Actual),
            Admitted_Relations,
            Relation_Diag);
      end Admit_Relations;
   begin
      Result :=
        (Kind           => Completed,
         Last_Confirmed => W0,
         Writer_Status  => HRA.Writer.Success,
         Message        => Null_Unbounded_String);

      --  The first target is still one Actual root. Issues and the relation
      --  observation join its existing Account/include guards only to bind the
      --  whole composition to the preparation premises.
      declare
         Composition_Guards : constant HRA.Writer.Source_Premise_Array (1 .. 2) :=
           [Prepared.Issues_Guard,
            Relation_Observed_Premise (Prepared.Relation_Source)];
      begin
         if not HRA.Household_Actual_Preparation.Publication.Publish_With_Guards
           (Prepared.Actual, Composition_Guards, Actual_Diag)
         then
            Fail
              (W0,
               Publishing_Actual,
               (if Actual_Diag.Status = HRA.Actual_Publication.Writer_Rejected
                then Writer_Failure
                else Invalid_Prepared_Witness),
               Actual_Diag.Writer_Status,
               To_String (Actual_Diag.Message));
            return False;
         end if;
      end;

      if not HRA.Issues.Admit_Issues_TSV
        (To_String (Prepared.Issues_Observed_Text), Open_Issues, Issues_Diag)
        or else not Admit_Relations (Open_Issues)
      then
         Fail
           (W1, Publishing_Relation, Domain_Admission_Failure,
            HRA.Writer.Success,
            "prepared relation no longer admits against the W1 candidate world");
         return False;
      end if;

      --  Relation publication is fenced by the exact W1 Actual graph and the
      --  exact Open Issues premise.
      declare
         Actual_Premises : constant HRA.Writer.Source_Premise_Array :=
           HRA.Household_Actual_Preparation.Publication.Published_Source_Premises
             (Prepared.Actual);
         Guards : HRA.Writer.Source_Premise_Array
           (1 .. Actual_Premises'Length + 1);
         Next : Natural := 0;
      begin
         for I in Actual_Premises'Range loop
            Next := Next + 1;
            Guards (Next) := Actual_Premises (I);
         end loop;
         Guards (Guards'Last) := Prepared.Issues_Guard;

         if not HRA.Writer.Atomic_Replace_Exact_Guarded
           (Target_Path => HRA.Issue_Relation_Candidate.Path_Of
              (Prepared.Relation_Source),
            Expected    => Relation_Expected (Prepared.Relation_Source),
            Candidate   => HRA.Writer.Make_Candidate_Source
              (HRA.Issue_Relation_Candidate.Text (Prepared.Relation_Source)),
            Guards      => Guards,
            Status      => Writer_Status,
            Error_Msg   => Writer_Error)
         then
            Fail
              (W1, Publishing_Relation, Writer_Failure,
               Writer_Status, To_String (Writer_Error));
            return False;
         end if;
      end;

      if not HRA.Issues.Admit_Issues_TSV
        (HRA.Issue_Close.Text (Prepared.Issues_Source),
         Resolved_Issues,
         Issues_Diag)
        or else not Admit_Relations (Resolved_Issues)
      then
         Fail
           (W2, Publishing_Issue, Domain_Admission_Failure,
            HRA.Writer.Success,
            "resolved Issues candidate does not cross-admit with relation history");
         return False;
      end if;

      --  Issue publication is fenced by the exact W2 relation and W1 Actual
      --  graph. The target itself remains the exact Open issues.tsv premise.
      declare
         Actual_Premises : constant HRA.Writer.Source_Premise_Array :=
           HRA.Household_Actual_Preparation.Publication.Published_Source_Premises
             (Prepared.Actual);
         Guards : HRA.Writer.Source_Premise_Array
           (1 .. Actual_Premises'Length + 1);
         Next : Natural := 0;
      begin
         for I in Actual_Premises'Range loop
            Next := Next + 1;
            Guards (Next) := Actual_Premises (I);
         end loop;
         Guards (Guards'Last) :=
           Relation_Published_Premise (Prepared.Relation_Source);

         if not HRA.Writer.Atomic_Replace_Exact_Guarded
           (Target_Path => To_String (Prepared.Issues_Path),
            Expected    => HRA.Writer.Make_Expected_Source
              (Prepared.Issues_Observed_Text),
            Candidate   => HRA.Writer.Make_Candidate_Source
              (HRA.Issue_Close.Text (Prepared.Issues_Source)),
            Guards      => Guards,
            Status      => Writer_Status,
            Error_Msg   => Writer_Error)
         then
            Fail
              (W2, Publishing_Issue, Writer_Failure,
               Writer_Status, To_String (Writer_Error));
            return False;
         end if;
      end;

      --  Repeat the cross-admission at the publication boundary after the
      --  single Issues target succeeds. This confirms W3 meaning without
      --  assigning domain semantics to Writer.
      if not Admit_Relations (Resolved_Issues) then
         Fail
           (W3, Publishing_Issue, Domain_Admission_Failure,
            HRA.Writer.Success,
            "published W3 candidate failed relation cross-admission confirmation");
         return False;
      end if;

      Result :=
        (Kind           => Completed,
         Last_Confirmed => W3,
         Writer_Status  => HRA.Writer.Success,
         Message        => Null_Unbounded_String);
      return True;
   end Publish;

end HRA.Issue_Realization_Preparation.Publication;
