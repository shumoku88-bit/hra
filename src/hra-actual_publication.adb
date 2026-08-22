with HRA.Actual_Graph_Admission;
with HRA.Actual_Root_Candidate;
with HRA.Journal_Loader;

package body HRA.Actual_Publication is

   use type HRA.Journal_Loader.Source_Kind;

   function Publish_With_Guards
     (Candidate         : HRA.Actual_Account_Admission.Account_Qualified_Graph;
      Additional_Guards : HRA.Writer.Source_Premise_Array;
      Diag              : out Publication_Diagnostic) return Boolean
   is
      Graph : constant HRA.Actual_Graph_Admission.Candidate_Graph :=
        HRA.Actual_Account_Admission.Graph_Of (Candidate);
      Root : constant HRA.Actual_Root_Candidate.Candidate_Root :=
        HRA.Actual_Graph_Admission.Root_Of (Graph);
      Source_Count : constant Natural :=
        HRA.Actual_Graph_Admission.Source_Count (Graph);
      Graph_Guard_Count : constant Natural :=
        (if Source_Count = 0 then 0 else Source_Count - 1);
      Guard_Count : constant Natural :=
        Graph_Guard_Count + Additional_Guards'Length;
      Guards : HRA.Writer.Source_Premise_Array (1 .. Guard_Count);
      Writer_Status : HRA.Writer.Writer_Status := HRA.Writer.Success;
      Writer_Error  : Unbounded_String := Null_Unbounded_String;
   begin
      Diag :=
        (Status        => Success,
         Writer_Status => HRA.Writer.Success,
         Message       => Null_Unbounded_String);

      if Source_Count = 0 then
         Diag.Status := Invalid_Qualified_Source_Witness;
         Diag.Message := To_Unbounded_String
           ("Account-qualified Actual graph has no retained source witness");
         return False;
      end if;

      declare
         Root_Witness : constant HRA.Journal_Loader.Source_Observation :=
           HRA.Actual_Graph_Admission.Source_At (Graph, 1);
      begin
         if Root_Witness.Kind /= HRA.Journal_Loader.Supplied_Root
           or else To_String (Root_Witness.Text) /=
             HRA.Actual_Root_Candidate.Text (Root)
         then
            Diag.Status := Invalid_Qualified_Source_Witness;
            Diag.Message := To_Unbounded_String
              ("Account-qualified Actual graph root witness is inconsistent");
            return False;
         end if;
      end;

      for Source_Index in 2 .. Source_Count loop
         declare
            Source : constant HRA.Journal_Loader.Source_Observation :=
              HRA.Actual_Graph_Admission.Source_At (Graph, Source_Index);
         begin
            if Source.Kind /= HRA.Journal_Loader.Included_File then
               Diag.Status := Invalid_Qualified_Source_Witness;
               Diag.Message := To_Unbounded_String
                 ("Account-qualified Actual graph contains a non-include guard witness");
               return False;
            end if;

            Guards (Source_Index - 1) :=
              HRA.Writer.Make_Source_Premise
                (Path     => To_String (Source.Path),
                 Expected => HRA.Writer.Make_Expected_Source
                   (To_String (Source.Text)));
         end;
      end loop;

      declare
         Next_Guard : Natural := Graph_Guard_Count;
      begin
         for Guard_Index in Additional_Guards'Range loop
            Next_Guard := Next_Guard + 1;
            Guards (Next_Guard) := Additional_Guards (Guard_Index);
         end loop;
      end;

      if not HRA.Writer.Atomic_Publish_Journal_Guarded
        (Target_Path => HRA.Actual_Root_Candidate.Root_Path_Of (Root),
         Expected    => HRA.Writer.Make_Expected_Source
           (HRA.Actual_Root_Candidate.Observed_Text (Root)),
         Candidate   => HRA.Writer.Make_Candidate_Source
           (HRA.Actual_Root_Candidate.Text (Root)),
         Guards      => Guards,
         Status      => Writer_Status,
         Error_Msg   => Writer_Error)
      then
         Diag.Status := Writer_Rejected;
         Diag.Writer_Status := Writer_Status;
         Diag.Message := Writer_Error;
         return False;
      end if;

      Diag.Writer_Status := Writer_Status;
      return True;
   end Publish_With_Guards;

   function Publish
     (Candidate : HRA.Actual_Account_Admission.Account_Qualified_Graph;
      Diag      : out Publication_Diagnostic) return Boolean
   is
      No_Additional_Guards : HRA.Writer.Source_Premise_Array (1 .. 0);
   begin
      return Publish_With_Guards
        (Candidate,
         No_Additional_Guards,
         Diag);
   end Publish;

end HRA.Actual_Publication;
