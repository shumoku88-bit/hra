package body HRA.Issue_Relation.Admission is

   function Count (History : Admitted_History) return Natural is
     (HRA.Issue_Relation.TSV.Count (History.Source_History));

   function Element
     (History : Admitted_History;
      Index   : Positive) return HRA.Issue_Relation.Relation_Event is
     (HRA.Issue_Relation.TSV.Element (History.Source_History, Index));

   function Admit
     (TSV_Text : String;
      Issues   : HRA.Issues.Issues_Inventory;
      Actuals  : HRA.Actual_Admission.Actual_Observation;
      History  : out Admitted_History;
      Diag     : out Admission_Diagnostic) return Boolean
   is
      Empty       : Admitted_History;
      Source      : HRA.Issue_Relation.TSV.Relation_History;
      Source_Diag : HRA.Issue_Relation.TSV.Admission_Diagnostic;
      Candidate   : Admitted_History;
   begin
      History := Empty;
      Diag := (Status => Success);

      if not HRA.Issue_Relation.TSV.Admit
        (TSV_Text, Source, Source_Diag)
      then
         Diag :=
           (Status => Source_Error,
            Source => Source_Diag);
         return False;
      end if;

      Candidate.Source_History := Source;

      for I in 1 .. HRA.Issue_Relation.TSV.Count (Source) loop
         declare
            Event : constant HRA.Issue_Relation.Relation_Event :=
              HRA.Issue_Relation.TSV.Element (Source, I);
            Reference_Diag : HRA.Issue_Relation.Reference_Diagnostic;
         begin
            if not HRA.Issue_Relation.Admit_References
              (Event, Issues, Actuals, Reference_Diag)
            then
               Diag :=
                 (Status            => Reference_Error,
                  Relation_Index    => I,
                  Relation_Event_Id => To_Unbounded_String
                    (HRA.Issue_Relation.Text
                       (HRA.Issue_Relation.Event_Id (Event))),
                  Reference         => Reference_Diag);
               return False;
            end if;
         end;
      end loop;

      History := Candidate;
      return True;
   end Admit;

end HRA.Issue_Relation.Admission;
