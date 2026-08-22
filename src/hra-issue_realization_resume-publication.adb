with HRA.Issue_Relation.Sidecar;

package body HRA.Issue_Realization_Resume.Publication is

   use type HRA.Issue_Relation.Sidecar.Presence;

   function Relation_Expected
     (Candidate : HRA.Issue_Relation_Candidate.Candidate_Source)
      return HRA.Writer.Expected_Source is
     (if HRA.Issue_Relation_Candidate.Observed_State_Of (Candidate) =
          HRA.Issue_Relation.Sidecar.Absent
      then HRA.Writer.Make_Absent_Expected_Source
      else HRA.Writer.Make_Expected_Source
        (HRA.Issue_Relation_Candidate.Observed_Text (Candidate)));

   function Relation_Published_Premise
     (Candidate : HRA.Issue_Relation_Candidate.Candidate_Source)
      return HRA.Writer.Source_Premise is
     (HRA.Writer.Make_Source_Premise
        (HRA.Issue_Relation_Candidate.Path_Of (Candidate),
         HRA.Writer.Make_Expected_Source
           (HRA.Issue_Relation_Candidate.Text (Candidate))));

   function Build_Actual_Premises
     (Sources       : HRA.Journal_Loader.Source_Observation_Vectors.Vector;
      Account_Guard : HRA.Writer.Source_Premise)
      return HRA.Writer.Source_Premise_Array
   is
      Count  : constant Natural := Natural (Sources.Length);
      Result : HRA.Writer.Source_Premise_Array (1 .. Count + 1);
   begin
      for I in 1 .. Count loop
         declare
            Item : constant HRA.Journal_Loader.Source_Observation :=
              Sources.Element (I);
         begin
            Result (I) := HRA.Writer.Make_Source_Premise
              (To_String (Item.Path),
               HRA.Writer.Make_Expected_Source (To_String (Item.Text)));
         end;
      end loop;
      Result (Result'Last) := Account_Guard;
      return Result;
   end Build_Actual_Premises;

   function Publish
     (Prepared : Prepared_Resume;
      Result   : out Publication_Result) return Boolean
   is
      Writer_Status : HRA.Writer.Writer_Status := HRA.Writer.Success;
      Writer_Error  : Unbounded_String;

      procedure Fail
        (World   : Confirmed_World;
         Step    : Publication_Step;
         Kind    : Failure_Kind;
         Status  : HRA.Writer.Writer_Status;
         Message : String) is
      begin
         Result :=
           (Kind           => HRA.Issue_Realization_Preparation.Publication.Failed,
            Last_Confirmed => World,
            Writer_Status  => Status,
            Message        => To_Unbounded_String (Message),
            Failed_Step    => Step,
            Failure        => Kind);
      end Fail;

   begin
      case Prepared.World is
         when HRA.Issue_Realization_Reconciliation.W0 =>
            return HRA.Issue_Realization_Preparation.Publication.Publish
              (Prepared.W0_Prepared, Result);

         when HRA.Issue_Realization_Reconciliation.W1 =>
            --  Step 1: Publish Relation sidecar
            declare
               Actual_Premises : constant HRA.Writer.Source_Premise_Array :=
                 Build_Actual_Premises
                   (Prepared.Actual_Sources, Prepared.Account_Guard);
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
                    (Prepared.W1_Relation_Source),
                  Expected    => Relation_Expected
                    (Prepared.W1_Relation_Source),
                  Candidate   => HRA.Writer.Make_Candidate_Source
                    (HRA.Issue_Relation_Candidate.Text
                       (Prepared.W1_Relation_Source)),
                  Guards      => Guards,
                  Status      => Writer_Status,
                  Error_Msg   => Writer_Error)
               then
                  Fail
                    (HRA.Issue_Realization_Preparation.Publication.W1,
                     HRA.Issue_Realization_Preparation.Publication.Publishing_Relation,
                     HRA.Issue_Realization_Preparation.Publication.Writer_Failure,
                     Writer_Status,
                     To_String (Writer_Error));
                  return False;
               end if;
            end;

            --  Step 2: Publish Issue closure
            declare
               Actual_Premises : constant HRA.Writer.Source_Premise_Array :=
                 Build_Actual_Premises
                   (Prepared.Actual_Sources, Prepared.Account_Guard);
               Guards : HRA.Writer.Source_Premise_Array
                 (1 .. Actual_Premises'Length + 1);
               Next : Natural := 0;
            begin
               for I in Actual_Premises'Range loop
                  Next := Next + 1;
                  Guards (Next) := Actual_Premises (I);
               end loop;
               Guards (Guards'Last) :=
                 Relation_Published_Premise (Prepared.W1_Relation_Source);

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
                    (HRA.Issue_Realization_Preparation.Publication.W2,
                     HRA.Issue_Realization_Preparation.Publication.Publishing_Issue,
                     HRA.Issue_Realization_Preparation.Publication.Writer_Failure,
                     Writer_Status,
                     To_String (Writer_Error));
                  return False;
               end if;
            end;

            Result :=
              (Kind           => HRA.Issue_Realization_Preparation.Publication.Completed,
               Last_Confirmed => HRA.Issue_Realization_Preparation.Publication.W3,
               Writer_Status  => HRA.Writer.Success,
               Message        => Null_Unbounded_String);
            return True;

         when HRA.Issue_Realization_Reconciliation.W2 =>
            --  Step: Publish Issue closure only
            declare
               Actual_Premises : constant HRA.Writer.Source_Premise_Array :=
                 Build_Actual_Premises
                   (Prepared.Actual_Sources, Prepared.Account_Guard);
               Guards : HRA.Writer.Source_Premise_Array
                 (1 .. Actual_Premises'Length + 1);
               Next : Natural := 0;
            begin
               for I in Actual_Premises'Range loop
                  Next := Next + 1;
                  Guards (Next) := Actual_Premises (I);
               end loop;
               Guards (Guards'Last) := Prepared.W2_Relation_Guard;

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
                    (HRA.Issue_Realization_Preparation.Publication.W2,
                     HRA.Issue_Realization_Preparation.Publication.Publishing_Issue,
                     HRA.Issue_Realization_Preparation.Publication.Writer_Failure,
                     Writer_Status,
                     To_String (Writer_Error));
                  return False;
               end if;
            end;

            Result :=
              (Kind           => HRA.Issue_Realization_Preparation.Publication.Completed,
               Last_Confirmed => HRA.Issue_Realization_Preparation.Publication.W3,
               Writer_Status  => HRA.Writer.Success,
               Message        => Null_Unbounded_String);
            return True;

         when HRA.Issue_Realization_Reconciliation.W3 =>
            --  Already complete: no-op
            Result :=
              (Kind           => HRA.Issue_Realization_Preparation.Publication.Completed,
               Last_Confirmed => HRA.Issue_Realization_Preparation.Publication.W3,
               Writer_Status  => HRA.Writer.Success,
               Message        => Null_Unbounded_String);
            return True;
      end case;
   end Publish;

end HRA.Issue_Realization_Resume.Publication;
