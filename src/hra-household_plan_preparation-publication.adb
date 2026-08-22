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
   use type HRA.Writer.Writer_Status;

   function Sources_To_Premises
     (Sources : HRA.Journal_Loader.Source_Observation_Vectors.Vector)
      return HRA.Writer.Source_Premise_Array
   is
      Count  : constant Natural := Natural (Sources.Length);
      Result : HRA.Writer.Source_Premise_Array (1 .. Count);
   begin
      for I in 1 .. Count loop
         declare
            Obs : constant HRA.Journal_Loader.Source_Observation :=
              Sources.Element (Positive (I));
         begin
            Result (I) :=
              HRA.Writer.Make_Source_Premise
                (Path     => To_String (Obs.Path),
                 Expected => HRA.Writer.Make_Expected_Source
                   (To_String (Obs.Text)));
         end;
      end loop;
      return Result;
   end Sources_To_Premises;

   function Publish_With_Guards
     (Prepared          : Prepared_Plan;
      Additional_Guards : HRA.Writer.Source_Premise_Array;
      Result            : out Publication_Result) return Boolean
   is
      Pub_Diag : HRA.Plan_Publication.Publication_Diagnostic;
   begin
      --  Exact retry / already present: verify all current filesystem premises
      --  (retained Plan graph, retained Accounts graph, and caller Additional_Guards)
      --  without performing filesystem mutation (verified no-op publication).
      if Is_Already_Present (Prepared) then
         declare
            Plan_Guards : constant HRA.Writer.Source_Premise_Array :=
              Sources_To_Premises (Prepared.Plan_Sources);
            Acc_Guards  : constant HRA.Writer.Source_Premise_Array :=
              Sources_To_Premises (Prepared.Account_Sources);
            Total_Count : constant Natural :=
              Plan_Guards'Length + Acc_Guards'Length + Additional_Guards'Length;
            All_Guards  : HRA.Writer.Source_Premise_Array (1 .. Total_Count);
            Next        : Natural := 0;
            Status      : HRA.Writer.Writer_Status;
            Error_Msg   : Unbounded_String;
         begin
            for I in Plan_Guards'Range loop
               Next := Next + 1;
               All_Guards (Next) := Plan_Guards (I);
            end loop;

            for I in Acc_Guards'Range loop
               Next := Next + 1;
               All_Guards (Next) := Acc_Guards (I);
            end loop;

            for I in Additional_Guards'Range loop
               Next := Next + 1;
               All_Guards (Next) := Additional_Guards (I);
            end loop;

            if not HRA.Writer.Verify_Source_Premises
              (Premises  => All_Guards,
               Status    => Status,
               Error_Msg => Error_Msg)
            then
               Result :=
                 (Kind          => Failed,
                  Completion    => Already_Present,
                  Failure       => Writer_Failure,
                  Writer_Status => Status,
                  Message       => Error_Msg);
               return False;
            end if;

            Result :=
              (Kind          => Completed,
               Completion    => Already_Present,
               Failure       => None,
               Writer_Status => HRA.Writer.Success,
               Message       => To_Unbounded_String
                 ("Plan already present with requested coordinates; publication verified as exact no-op"));
            return True;
         end;
      end if;

      --  Fresh publication: pass complete retained Accounts graph premises
      --  plus caller Additional_Guards to Plan_Publication
      declare
         Acc_Guards  : constant HRA.Writer.Source_Premise_Array :=
           Sources_To_Premises (Prepared.Account_Sources);
         Total_Count : constant Natural :=
           Acc_Guards'Length + Additional_Guards'Length;
         Guards      : HRA.Writer.Source_Premise_Array (1 .. Total_Count);
         Next        : Natural := 0;
      begin
         for I in Acc_Guards'Range loop
            Next := Next + 1;
            Guards (Next) := Acc_Guards (I);
         end loop;

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

         if not Found
           or else Target_Entry.Retirement.Kind /= HRA.Plan_Admission.No_Retirement
           or else Target_Entry.Tx /= Transaction_Of (Prepared)
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
            Plan_Guards : constant HRA.Writer.Source_Premise_Array :=
              Sources_To_Premises (Prepared.Plan_Sources);
            Acc_Guards  : constant HRA.Writer.Source_Premise_Array :=
              Sources_To_Premises (Prepared.Account_Sources);
            Result      : HRA.Writer.Source_Premise_Array
              (1 .. Plan_Guards'Length + Acc_Guards'Length);
            Next        : Natural := 0;
         begin
            for I in Plan_Guards'Range loop
               Next := Next + 1;
               Result (Next) := Plan_Guards (I);
            end loop;
            for I in Acc_Guards'Range loop
               Next := Next + 1;
               Result (Next) := Acc_Guards (I);
            end loop;
            return Result;
         end;
      else
         declare
            Plan_Premises : constant HRA.Writer.Source_Premise_Array :=
              HRA.Plan_Publication.Published_Source_Premises (Prepared.Qualified);
            Acc_Guards    : constant HRA.Writer.Source_Premise_Array :=
              Sources_To_Premises (Prepared.Account_Sources);
            Result        : HRA.Writer.Source_Premise_Array
              (1 .. Plan_Premises'Length + Acc_Guards'Length);
            Next          : Natural := 0;
         begin
            for I in Plan_Premises'Range loop
               Next := Next + 1;
               Result (Next) := Plan_Premises (I);
            end loop;
            for I in Acc_Guards'Range loop
               Next := Next + 1;
               Result (Next) := Acc_Guards (I);
            end loop;
            return Result;
         end;
      end if;
   end Published_Source_Premises;

end HRA.Household_Plan_Preparation.Publication;
