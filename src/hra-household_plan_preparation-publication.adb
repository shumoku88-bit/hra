with HRA.Journal_Loader;
with HRA.Plan_Account_Admission;
with HRA.Plan_Admission;
with HRA.Plan_Graph_Admission;
with HRA.Plan_Publication;
with HRA.Plan_Root_Candidate;

package body HRA.Household_Plan_Preparation.Publication is

   use type HRA.Plan.Plan_Id;
   use type HRA.Plan_Admission.Retirement_Kind;
   use type HRA.Ledger.Transaction;
   use type HRA.Writer.Source_Presence;
   use type HRA.Writer.Writer_Status;

   function Publish_With_Guards
     (Prepared          : Prepared_Plan;
      Additional_Guards : HRA.Writer.Source_Premise_Array;
      Result            : out Publication_Result) return Boolean
   is
      Pub_Diag : HRA.Plan_Publication.Publication_Diagnostic;
   begin
      --  Exact retry / already present: verify current filesystem premises
      --  without performing filesystem mutation (no-op publication).
      if Is_Already_Present (Prepared) then
         declare
            Observed  : HRA.Writer.Expected_Source;
            Obs_Error : Unbounded_String;
         begin
            if not HRA.Writer.Observe_Source
              (Target_Path => To_String (Prepared.Target_Path),
               Observed    => Observed,
               Error_Msg   => Obs_Error)
            then
               Result :=
                 (Kind          => Failed,
                  Completion    => Already_Present,
                  Failure       => Writer_Failure,
                  Writer_Status => HRA.Writer.Stale_Source_Rejected,
                  Message       => To_Unbounded_String
                    ("cannot observe current Plan source for retry verification: " &
                     To_String (Obs_Error)));
               return False;
            end if;

            if HRA.Writer.Presence_Of (Observed) /= HRA.Writer.Present
              or else HRA.Writer.Source_Text (Observed) /=
                To_String (Prepared.Expected_Root_Text)
            then
               Result :=
                 (Kind          => Failed,
                  Completion    => Already_Present,
                  Failure       => Writer_Failure,
                  Writer_Status => HRA.Writer.Stale_Source_Rejected,
                  Message       => To_Unbounded_String
                    ("current Plan source is stale against prepared retry premise"));
               return False;
            end if;
         end;

         if Length (Prepared.Account_Guard_Path) > 0 then
            declare
               Acc_Observed : HRA.Writer.Expected_Source;
               Acc_Error    : Unbounded_String;
            begin
               if not HRA.Writer.Observe_Source
                 (Target_Path => To_String (Prepared.Account_Guard_Path),
                  Observed    => Acc_Observed,
                  Error_Msg   => Acc_Error)
               then
                  Result :=
                    (Kind          => Failed,
                     Completion    => Already_Present,
                     Failure       => Writer_Failure,
                     Writer_Status => HRA.Writer.Stale_Source_Rejected,
                     Message       => To_Unbounded_String
                       ("cannot observe current Accounts source for retry verification: " &
                        To_String (Acc_Error)));
                  return False;
               end if;

               if HRA.Writer.Presence_Of (Acc_Observed) /= HRA.Writer.Present
                 or else HRA.Writer.Source_Text (Acc_Observed) /=
                   To_String (Prepared.Account_Guard_Text)
               then
                  Result :=
                    (Kind          => Failed,
                     Completion    => Already_Present,
                     Failure       => Writer_Failure,
                     Writer_Status => HRA.Writer.Stale_Source_Rejected,
                     Message       => To_Unbounded_String
                       ("current Accounts source is stale against prepared retry premise"));
                  return False;
               end if;
            end;
         end if;

         Result :=
           (Kind          => Completed,
            Completion    => Already_Present,
            Failure       => None,
            Writer_Status => HRA.Writer.Success,
            Message       => To_Unbounded_String
              ("Plan already present with requested coordinates; publication verified as exact no-op"));
         return True;
      end if;

      declare
         Guards : HRA.Writer.Source_Premise_Array
           (1 .. 1 + Additional_Guards'Length);
         Next   : Natural := 1;
      begin
         Guards (1) := Prepared.Account_Guard;
         for I in Additional_Guards'Range loop
            Next := Next + 1;
            Guards (Next) := Additional_Guards (I);
         end loop;

         if not HRA.Plan_Publication.Publish_With_Guards
           (Prepared.Qualified, Guards, Pub_Diag)
         then
            Result :=
              (Kind          => Failed,
               Completion    => Newly_Published,
               Failure       => Writer_Failure,
               Writer_Status => Pub_Diag.Writer_Status,
               Message       => Pub_Diag.Message);
            return False;
         end if;
      end;

      --  Post-publication domain verification
      declare
         Graph        : constant HRA.Plan_Graph_Admission.Candidate_Graph :=
           HRA.Plan_Account_Admission.Graph_Of (Prepared.Qualified);
         Root         : constant HRA.Plan_Root_Candidate.Candidate_Root :=
           HRA.Plan_Graph_Admission.Root_Of (Graph);
         Loaded       : HRA.Journal_Loader.Journal_Observation;
         Loaded_Error : Unbounded_String;
         Admitted     : HRA.Plan_Admission.Plan_Journal;
         Admit_Diag   : HRA.Plan_Admission.Admission_Diagnostic;
         Found        : Boolean := False;
         Target_Entry : HRA.Plan_Admission.Plan_Transaction_Entry;
      begin
         if not HRA.Journal_Loader.Load_From_Root_Source
           (Root_Path   => HRA.Plan_Root_Candidate.Root_Path_Of (Root),
            Root_Text   => HRA.Plan_Root_Candidate.Text (Root),
            Observation => Loaded,
            Error_Msg   => Loaded_Error)
         then
            Result :=
              (Kind          => Failed,
               Completion    => Newly_Published,
               Failure       => Post_Admission_Failure,
               Writer_Status => HRA.Writer.Success,
               Message       => To_Unbounded_String
                 ("post-publication Plan journal load failed: " &
                  To_String (Loaded_Error)));
            return False;
         end if;

         if not HRA.Plan_Admission.Admit
           (Loaded.Value, Loaded.Evidence, Admitted, Admit_Diag)
         then
            Result :=
              (Kind          => Failed,
               Completion    => Newly_Published,
               Failure       => Post_Admission_Failure,
               Writer_Status => HRA.Writer.Success,
               Message       => To_Unbounded_String
                 ("post-publication Plan admission failed"));
            return False;
         end if;

         for I in 1 .. HRA.Plan_Admission.Transaction_Count (Admitted) loop
            declare
               Item : constant HRA.Plan_Admission.Plan_Transaction_Entry :=
                 HRA.Plan_Admission.Transaction_At (Admitted, I);
            begin
               if Item.ID = Plan_Id_Of (Prepared) then
                  Target_Entry := Item;
                  Found := True;
                  exit;
               end if;
            end;
         end loop;

         declare
            Expected_Tx : HRA.Ledger.Transaction := Transaction_Of (Prepared);
         begin
            Expected_Tx.Event_ID := Null_Unbounded_String;
            Expected_Tx.Reverses_ID := Null_Unbounded_String;

            if not Found
              or else Target_Entry.Retirement.Kind /= HRA.Plan_Admission.No_Retirement
              or else Target_Entry.Tx /= Expected_Tx
            then
               Result :=
                 (Kind          => Failed,
                  Completion    => Newly_Published,
                  Failure       => Post_Admission_Failure,
                  Writer_Status => HRA.Writer.Success,
                  Message       => To_Unbounded_String
                    ("post-publication Plan verification failed"));
               return False;
            end if;
         end;
      end;

      Result :=
        (Kind          => Completed,
         Completion    => Newly_Published,
         Failure       => None,
         Writer_Status => HRA.Writer.Success,
         Message       => To_Unbounded_String
           ("Plan created and published successfully"));
      return True;
   end Publish_With_Guards;

   function Publish
     (Prepared : Prepared_Plan;
      Result   : out Publication_Result) return Boolean
   is
      No_Additional_Guards : HRA.Writer.Source_Premise_Array (1 .. 0);
   begin
      return Publish_With_Guards
        (Prepared, No_Additional_Guards, Result);
   end Publish;

   function Published_Source_Premises
     (Prepared : Prepared_Plan) return HRA.Writer.Source_Premise_Array
   is
   begin
      if Is_Already_Present (Prepared) then
         declare
            Result : HRA.Writer.Source_Premise_Array (1 .. 2);
         begin
            Result (1) :=
              HRA.Writer.Make_Source_Premise
                (To_String (Prepared.Target_Path),
                 HRA.Writer.Make_Expected_Source
                   (To_String (Prepared.Expected_Root_Text)));
            Result (2) := Prepared.Account_Guard;
            return Result;
         end;
      else
         declare
            Graph        : constant HRA.Plan_Graph_Admission.Candidate_Graph :=
              HRA.Plan_Account_Admission.Graph_Of (Prepared.Qualified);
            Root         : constant HRA.Plan_Root_Candidate.Candidate_Root :=
              HRA.Plan_Graph_Admission.Root_Of (Graph);
            Source_Count : constant Natural :=
              HRA.Plan_Graph_Admission.Source_Count (Graph);
            Result       : HRA.Writer.Source_Premise_Array (1 .. Source_Count + 1);
         begin
            Result (1) :=
              HRA.Writer.Make_Source_Premise
                (HRA.Plan_Root_Candidate.Root_Path_Of (Root),
                 HRA.Writer.Make_Expected_Source
                   (HRA.Plan_Root_Candidate.Text (Root)));

            for I in 2 .. Source_Count loop
               declare
                  Source : constant HRA.Journal_Loader.Source_Observation :=
                    HRA.Plan_Graph_Admission.Source_At (Graph, I);
               begin
                  Result (I) :=
                    HRA.Writer.Make_Source_Premise
                      (To_String (Source.Path),
                       HRA.Writer.Make_Expected_Source (To_String (Source.Text)));
               end;
            end loop;

            Result (Result'Last) := Prepared.Account_Guard;
            return Result;
         end;
      end if;
   end Published_Source_Premises;

end HRA.Household_Plan_Preparation.Publication;
