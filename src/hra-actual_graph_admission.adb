with Ada.Directories; use Ada.Directories;
with HRA.Journal_Evidence;
with HRA.Ledger;

package body HRA.Actual_Graph_Admission is

   use type HRA.Actual_Admission.Actual_Id;
   use type HRA.Journal_Loader.Source_Kind;
   use type HRA.Ledger.Transaction;

   function Observation_Of
     (Candidate : Candidate_Graph)
      return HRA.Actual_Admission.Actual_Observation is
     (Candidate.Actual);

   function Root_Of
     (Candidate : Candidate_Graph)
      return HRA.Actual_Root_Candidate.Candidate_Root is
     (Candidate.Root);

   function Source_Count (Candidate : Candidate_Graph) return Natural is
     (Natural (Candidate.Sources.Length));

   function Source_At
     (Candidate : Candidate_Graph;
      Index     : Positive) return HRA.Journal_Loader.Source_Observation is
     (Candidate.Sources.Element (Index));

   function Empty_Actual_Diagnostic
      return HRA.Actual_Admission.Admission_Diagnostic is
     ((Status      => HRA.Actual_Admission.Success,
       Line_Number => 0,
       Actual_Id   => Null_Unbounded_String,
       Message     => Null_Unbounded_String));

   function Admit_Candidate_Root
     (Existing       : HRA.Actual_Admission.Actual_Observation;
      Candidate_Root : HRA.Actual_Root_Candidate.Candidate_Root;
      Candidate      : out Candidate_Graph;
      Diag           : out Admission_Diagnostic) return Boolean
   is
      Root_Path        : constant String :=
        HRA.Actual_Root_Candidate.Root_Path_Of (Candidate_Root);
      Candidate_Text   : constant String :=
        HRA.Actual_Root_Candidate.Text (Candidate_Root);
      Graph            : HRA.Journal_Loader.Journal_Observation;
      Graph_Error      : Unbounded_String;
      Candidate_Actual : HRA.Actual_Admission.Actual_Observation;
      Actual_Diag      : HRA.Actual_Admission.Admission_Diagnostic :=
        Empty_Actual_Diagnostic;
      Existing_Count   : constant Natural :=
        HRA.Actual_Admission.Transaction_Count (Existing);
      Existing_Reversal_Count : constant Natural :=
        HRA.Actual_Admission.Reversal_Count (Existing);
   begin
      Diag :=
        (Status  => Success,
         Actual  => Empty_Actual_Diagnostic,
         Message => Null_Unbounded_String);

      if Root_Path'Length = 0 then
         Diag.Status := Candidate_Source_Witness_Mismatch;
         Diag.Message := To_Unbounded_String
           ("candidate Actual root lost its physical source coordinate");
         return False;
      end if;

      if not HRA.Journal_Loader.Load_From_Root_Source
        (Root_Path   => Root_Path,
         Root_Text   => Candidate_Text,
         Observation => Graph,
         Error_Msg   => Graph_Error)
      then
         Diag.Status := Candidate_Graph_Load_Failed;
         Diag.Message := To_Unbounded_String
           ("candidate Actual include graph failed Journal admission: " &
            To_String (Graph_Error));
         return False;
      end if;

      declare
         Source_Count : constant Natural := Natural (Graph.Sources.Length);
      begin
         if Source_Count = 0 then
            Diag.Status := Candidate_Source_Witness_Mismatch;
            Diag.Message := To_Unbounded_String
              ("candidate Actual graph did not retain its supplied root source");
            return False;
         end if;

         declare
            Root_Source : constant HRA.Journal_Loader.Source_Observation :=
              Graph.Sources.Element (1);
         begin
            if Root_Source.Kind /= HRA.Journal_Loader.Supplied_Root
              or else To_String (Root_Source.Path) /= Full_Name (Root_Path)
              or else To_String (Root_Source.Text) /= Candidate_Text
            then
               Diag.Status := Candidate_Source_Witness_Mismatch;
               Diag.Message := To_Unbounded_String
                 ("candidate Actual graph root witness does not match Candidate_Root");
               return False;
            end if;
         end;

         for I in 2 .. Source_Count loop
            if Graph.Sources.Element (I).Kind /= HRA.Journal_Loader.Included_File then
               Diag.Status := Candidate_Source_Witness_Mismatch;
               Diag.Message := To_Unbounded_String
                 ("candidate Actual graph retained more than one supplied root source");
               return False;
            end if;
         end loop;
      end;

      if not HRA.Actual_Admission.Admit
        (Graph.Value,
         Graph.Evidence,
         Candidate_Actual,
         Actual_Diag)
      then
         Diag.Status := Candidate_Actual_Admission_Failed;
         Diag.Actual := Actual_Diag;
         Diag.Message := To_Unbounded_String
           ("candidate Actual include graph failed durable Actual admission");
         return False;
      end if;

      declare
         Candidate_Count : constant Natural :=
           HRA.Actual_Admission.Transaction_Count (Candidate_Actual);
      begin
         if Candidate_Count /= Existing_Count + 1 then
            Diag.Status := Candidate_History_Count_Mismatch;
            Diag.Message := To_Unbounded_String
              ("candidate Actual graph must add exactly one transaction to the admitted authority");
            return False;
         end if;

         for I in 1 .. Existing_Count loop
            if not HRA.Actual_Admission.Same_Entry
              (HRA.Actual_Admission.Transaction_At (Existing, I),
               HRA.Actual_Admission.Transaction_At (Candidate_Actual, I))
            then
               Diag.Status := Existing_History_Changed;
               Diag.Message := To_Unbounded_String
                 ("candidate Actual graph changed existing transaction meaning or provenance");
               return False;
            end if;
         end loop;

         if HRA.Actual_Admission.Reversal_Count (Candidate_Actual) /=
           Existing_Reversal_Count
         then
            Diag.Status := Existing_Reversal_History_Changed;
            Diag.Message := To_Unbounded_String
              ("candidate Actual graph changed existing reversal history");
            return False;
         end if;

         for I in 1 .. Existing_Reversal_Count loop
            if not HRA.Actual_Admission.Same_Reversal
              (HRA.Actual_Admission.Reversal_At (Existing, I),
               HRA.Actual_Admission.Reversal_At (Candidate_Actual, I))
            then
               Diag.Status := Existing_Reversal_History_Changed;
               Diag.Message := To_Unbounded_String
                 ("candidate Actual graph changed existing reversal relations");
               return False;
            end if;
         end loop;

         declare
            Appended : constant HRA.Actual_Admission.Actual_Transaction_Entry :=
              HRA.Actual_Admission.Transaction_At
                (Candidate_Actual, Candidate_Count);
         begin
            if Appended.Identity.Present /=
              Appended.Source_Durable_Identity.Present
              or else (Appended.Identity.Present
                       and then Appended.Identity.Value /=
                         Appended.Source_Durable_Identity.Value)
            then
               Diag.Status := Appended_Actual_Not_Source_Durable;
               Diag.Message := To_Unbounded_String
                 ("appended Actual identity must match explicit source-durable identity");
               return False;
            end if;

            if To_String (Appended.Source.Source_Path) /= Full_Name (Root_Path) then
               Diag.Status := Appended_Actual_Not_Root_Owned;
               Diag.Message := To_Unbounded_String
                 ("appended Actual must be owned by the Candidate_Root source");
               return False;
            end if;
         end;
      end;

      Candidate :=
        (Root    => Candidate_Root,
         Sources => Graph.Sources,
         Actual  => Candidate_Actual);
      return True;
   end Admit_Candidate_Root;

end HRA.Actual_Graph_Admission;
