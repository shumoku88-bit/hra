with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA.Actual_Graph_Admission;
with HRA.Actual_Root_Candidate;
with HRA.Journal_Loader;

package body HRA.Household_Actual_Preparation.Publication is

   function Publish_With_Guards
     (Prepared          : Prepared_Actual;
      Additional_Guards : HRA.Writer.Source_Premise_Array;
      Diag              : out HRA.Actual_Publication.Publication_Diagnostic)
      return Boolean
   is
      Guards : HRA.Writer.Source_Premise_Array
        (1 .. 1 + Additional_Guards'Length);
      Next : Natural := 1;
   begin
      Guards (1) := Prepared.Account_Guard;
      for I in Additional_Guards'Range loop
         Next := Next + 1;
         Guards (Next) := Additional_Guards (I);
      end loop;

      return HRA.Actual_Publication.Publish_With_Guards
        (Prepared.Qualified, Guards, Diag);
   end Publish_With_Guards;

   function Publish
     (Prepared : Prepared_Actual;
      Diag     : out HRA.Actual_Publication.Publication_Diagnostic)
      return Boolean
   is
      No_Additional_Guards : HRA.Writer.Source_Premise_Array (1 .. 0);
   begin
      return Publish_With_Guards
        (Prepared, No_Additional_Guards, Diag);
   end Publish;

   function Published_Source_Premises
     (Prepared : Prepared_Actual) return HRA.Writer.Source_Premise_Array
   is
      Graph : constant HRA.Actual_Graph_Admission.Candidate_Graph :=
        HRA.Actual_Account_Admission.Graph_Of (Prepared.Qualified);
      Root : constant HRA.Actual_Root_Candidate.Candidate_Root :=
        HRA.Actual_Graph_Admission.Root_Of (Graph);
      Source_Count : constant Natural :=
        HRA.Actual_Graph_Admission.Source_Count (Graph);
      Result : HRA.Writer.Source_Premise_Array (1 .. Source_Count + 1);
   begin
      Result (1) := HRA.Writer.Make_Source_Premise
        (HRA.Actual_Root_Candidate.Root_Path_Of (Root),
         HRA.Writer.Make_Expected_Source
           (HRA.Actual_Root_Candidate.Text (Root)));

      for I in 2 .. Source_Count loop
         declare
            Source : constant HRA.Journal_Loader.Source_Observation :=
              HRA.Actual_Graph_Admission.Source_At (Graph, I);
         begin
            Result (I) := HRA.Writer.Make_Source_Premise
              (To_String (Source.Path),
               HRA.Writer.Make_Expected_Source (To_String (Source.Text)));
         end;
      end loop;

      Result (Result'Last) := Prepared.Account_Guard;
      return Result;
   end Published_Source_Premises;

end HRA.Household_Actual_Preparation.Publication;
