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

   function Same_Identity
     (Left  : HRA.Actual_Admission.Actual_Id_Option;
      Right : HRA.Actual_Admission.Actual_Id_Option) return Boolean
   is
   begin
      if Left.Present /= Right.Present then
         return False;
      elsif not Left.Present then
         return True;
      else
         return Left.Value = Right.Value;
      end if;
   end Same_Identity;

   function Same_Source
     (Left  : HRA.Journal_Evidence.Transaction_Source;
      Right : HRA.Journal_Evidence.Transaction_Source) return Boolean
   is
      Left_Metadata_Count  : constant Natural := Natural (Left.Metadata.Length);
      Right_Metadata_Count : constant Natural := Natural (Right.Metadata.Length);
   begin
      if To_String (Left.Source_Path) /= To_String (Right.Source_Path)
        or else Left.Header_Line /= Right.Header_Line
        or else To_String (Left.Date_Text) /= To_String (Right.Date_Text)
        or else To_String (Left.Description) /= To_String (Right.Description)
        or else Left_Metadata_Count /= Right_Metadata_Count
      then
         return False;
      end if;

      for I in 1 .. Left_Metadata_Count loop
         declare
            Left_Entry  : constant HRA.Journal_Evidence.Metadata_Entry :=
              Left.Metadata.Element (I);
            Right_Entry : constant HRA.Journal_Evidence.Metadata_Entry :=
              Right.Metadata.Element (I);
         begin
            if To_String (Left_Entry.Key) /= To_String (Right_Entry.Key)
              or else To_String (Left_Entry.Value) /= To_String (Right_Entry.Value)
              or else Left_Entry.Line_Number /= Right_Entry.Line_Number
            then
               return False;
            end if;
         end;
      end loop;

      return True;
   end Same_Source;

   function Same_Entry
     (Left  : HRA.Actual_Admission.Actual_Transaction_Entry;
      Right : HRA.Actual_Admission.Actual_Transaction_Entry) return Boolean is
     (Left.Tx = Right.Tx
      and then Same_Identity (Left.Identity, Right.Identity)
      and then Same_Identity
        (Left.Source_Durable_Identity, Right.Source_Durable_Identity)
      and then Same_Source (Left.Source, Right.Source));

   function Same_Reversal
     (Left  : HRA.Actual_Admission.Reversal_Relation;
      Right : HRA.Actual_Admission.Reversal_Relation) return Boolean is
     (Left.Reversal_ID = Right.Reversal_ID
      and then Left.Target_ID = Right.Target_ID);

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
            if not Same_Entry
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
            if not Same_Reversal
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
