with Ada.Directories; use Ada.Directories;
with HRA.Ledger;
with HRA.Plan;

package body HRA.Plan_Graph_Admission is

   use type HRA.Plan.Plan_Id;
   use type HRA.Plan_Admission.Retirement_Kind;
   use type HRA.Journal_Loader.Source_Kind;
   use type HRA.Ledger.Transaction;

   function Plan_Journal_Of
     (Candidate : Candidate_Graph)
      return HRA.Plan_Admission.Plan_Journal is
     (Candidate.Plan);

   function Root_Of
     (Candidate : Candidate_Graph)
      return HRA.Plan_Root_Candidate.Candidate_Root is
     (Candidate.Root);

   function Source_Count (Candidate : Candidate_Graph) return Natural is
     (Natural (Candidate.Sources.Length));

   function Source_At
     (Candidate : Candidate_Graph;
      Index     : Positive) return HRA.Journal_Loader.Source_Observation is
     (Candidate.Sources.Element (Index));

   function Empty_Plan_Diagnostic
      return HRA.Plan_Admission.Admission_Diagnostic is
     ((Status      => HRA.Plan_Admission.Success,
       Line_Number => 0,
       Plan_Id     => Null_Unbounded_String,
       Message     => Null_Unbounded_String));

   function Admit_Candidate_Root
     (Existing       : HRA.Plan_Admission.Plan_Journal;
      Candidate_Root : HRA.Plan_Root_Candidate.Candidate_Root;
      Candidate      : out Candidate_Graph;
      Diag           : out Admission_Diagnostic) return Boolean
   is
      Root_Path      : constant String :=
        HRA.Plan_Root_Candidate.Root_Path_Of (Candidate_Root);
      Candidate_Text : constant String :=
        HRA.Plan_Root_Candidate.Text (Candidate_Root);
      Graph          : HRA.Journal_Loader.Journal_Observation;
      Graph_Error    : Unbounded_String;
      Candidate_Plan : HRA.Plan_Admission.Plan_Journal;
      Plan_Diag      : HRA.Plan_Admission.Admission_Diagnostic :=
        Empty_Plan_Diagnostic;
      Existing_Count : constant Natural :=
        HRA.Plan_Admission.Transaction_Count (Existing);
   begin
      Diag :=
        (Status  => Success,
         Plan    => Empty_Plan_Diagnostic,
         Message => Null_Unbounded_String);

      if Root_Path'Length = 0 then
         Diag.Status := Candidate_Source_Witness_Mismatch;
         Diag.Message := To_Unbounded_String
           ("candidate Plan root lost its physical source coordinate");
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
           ("candidate Plan include graph failed Journal admission: " &
            To_String (Graph_Error));
         return False;
      end if;

      declare
         Source_Count : constant Natural := Natural (Graph.Sources.Length);
      begin
         if Source_Count = 0 then
            Diag.Status := Candidate_Source_Witness_Mismatch;
            Diag.Message := To_Unbounded_String
              ("candidate Plan graph did not retain its supplied root source");
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
                 ("candidate Plan graph root witness does not match Candidate_Root");
               return False;
            end if;
         end;

         for I in 2 .. Source_Count loop
            if Graph.Sources.Element (I).Kind /= HRA.Journal_Loader.Included_File then
               Diag.Status := Candidate_Source_Witness_Mismatch;
               Diag.Message := To_Unbounded_String
                 ("candidate Plan graph retained more than one supplied root source");
               return False;
            end if;
         end loop;
      end;

      if not HRA.Plan_Admission.Admit
        (Graph.Value,
         Graph.Evidence,
         Candidate_Plan,
         Plan_Diag)
      then
         Diag.Status := Candidate_Plan_Admission_Failed;
         Diag.Plan := Plan_Diag;
         Diag.Message := To_Unbounded_String
           ("candidate Plan include graph failed native Plan admission");
         return False;
      end if;

      declare
         Candidate_Count : constant Natural :=
           HRA.Plan_Admission.Transaction_Count (Candidate_Plan);
      begin
         if Candidate_Count /= Existing_Count + 1 then
            Diag.Status := Candidate_History_Count_Mismatch;
            Diag.Message := To_Unbounded_String
              ("candidate Plan graph must add exactly one transaction to the admitted authority");
            return False;
         end if;

         for I in 1 .. Existing_Count loop
            if not HRA.Plan_Admission.Same_Entry
              (HRA.Plan_Admission.Transaction_At (Existing, I),
               HRA.Plan_Admission.Transaction_At (Candidate_Plan, I))
            then
               Diag.Status := Existing_History_Changed;
               Diag.Message := To_Unbounded_String
                 ("candidate Plan graph changed existing transaction meaning, identity, or provenance");
               return False;
            end if;
         end loop;

         declare
            Appended : constant HRA.Plan_Admission.Plan_Transaction_Entry :=
              HRA.Plan_Admission.Transaction_At
                (Candidate_Plan, Candidate_Count);
         begin
            if Appended.Retirement.Kind /= HRA.Plan_Admission.No_Retirement then
               Diag.Status := Appended_Plan_Not_Pending;
               Diag.Message := To_Unbounded_String
                 ("appended Plan entry must be in pending (non-retired) state");
               return False;
            end if;

            if To_String (Appended.Source.Source_Path) /= Full_Name (Root_Path) then
               Diag.Status := Appended_Plan_Not_Root_Owned;
               Diag.Message := To_Unbounded_String
                 ("appended Plan must be owned by the Candidate_Root source");
               return False;
            end if;
         end;
      end;

      Candidate :=
        (Root    => Candidate_Root,
         Sources => Graph.Sources,
         Plan    => Candidate_Plan);
      return True;
   end Admit_Candidate_Root;

end HRA.Plan_Graph_Admission;
