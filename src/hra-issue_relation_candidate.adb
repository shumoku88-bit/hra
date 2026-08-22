with HRA.Actual_Admission;
with HRA.Dates;
with HRA.Issues;

package body HRA.Issue_Relation_Candidate is

   use type HRA.Dates.Date;
   use type HRA.Issue_Relation.Relation_Event_Id;
   use type HRA.Issue_Relation.Relation_Kind;
   use type HRA.Issue_Relation.Sidecar.Presence;

   function Path_Of (Candidate : Candidate_Source) return String is
     (To_String (Candidate.Path));

   function Observed_State_Of
     (Candidate : Candidate_Source) return HRA.Issue_Relation.Sidecar.Presence is
     (Candidate.Observed_State);

   function Observed_Text (Candidate : Candidate_Source) return String is
     (To_String (Candidate.Observed_Text));

   function Text (Candidate : Candidate_Source) return String is
     (To_String (Candidate.Candidate_Text));

   function History_Of
     (Candidate : Candidate_Source) return HRA.Issue_Relation.TSV.Relation_History is
     (Candidate.History);

   function Same_Relation_Event
     (Left  : HRA.Issue_Relation.Relation_Event;
      Right : HRA.Issue_Relation.Relation_Event) return Boolean is
     (HRA.Issue_Relation.Event_Id (Left) = HRA.Issue_Relation.Event_Id (Right)
      and then HRA.Issue_Relation.Recorded_On (Left) =
        HRA.Issue_Relation.Recorded_On (Right)
      and then HRA.Issues.Text (HRA.Issue_Relation.Issue_Id (Left)) =
        HRA.Issues.Text (HRA.Issue_Relation.Issue_Id (Right))
      and then HRA.Issue_Relation.Kind (Left) =
        HRA.Issue_Relation.Kind (Right)
      and then (case HRA.Issue_Relation.Kind (Left) is
                   when HRA.Issue_Relation.Realized_As =>
                     HRA.Actual_Admission.Text
                       (HRA.Issue_Relation.Actual_Id (Left)) =
                     HRA.Actual_Admission.Text
                       (HRA.Issue_Relation.Actual_Id (Right)))
      and then HRA.Issue_Relation.Details (Left) =
        HRA.Issue_Relation.Details (Right));

   function Prepare
     (Observed  : HRA.Issue_Relation.Sidecar.Observation;
      Event     : HRA.Issue_Relation.Relation_Event;
      Candidate : out Candidate_Source;
      Diag      : out Candidate_Diagnostic) return Boolean
   is
      Existing_History  : HRA.Issue_Relation.TSV.Relation_History;
      Existing_Diag     : HRA.Issue_Relation.TSV.Admission_Diagnostic;
      Candidate_History : HRA.Issue_Relation.TSV.Relation_History;
      Candidate_Diag    : HRA.Issue_Relation.TSV.Admission_Diagnostic;
      Observed_State    : constant HRA.Issue_Relation.Sidecar.Presence :=
        HRA.Issue_Relation.Sidecar.State_Of (Observed);
      Path              : constant String :=
        HRA.Issue_Relation.Sidecar.Path_Of (Observed);
      Observed_Source   : constant String :=
        (if Observed_State = HRA.Issue_Relation.Sidecar.Present
         then HRA.Issue_Relation.Sidecar.Text_Of (Observed)
         else "");
      Rendered          : Unbounded_String;
      Needs_Header      : Boolean := False;
   begin
      Candidate :=
        (Path           => Null_Unbounded_String,
         Observed_State => HRA.Issue_Relation.Sidecar.Absent,
         Observed_Text  => Null_Unbounded_String,
         Candidate_Text => Null_Unbounded_String,
         History        => Existing_History);
      Diag :=
        (Status  => Success,
         TSV     =>
           (Status            => HRA.Issue_Relation.TSV.Success,
            Line_Number       => 0,
            Relation_Event_Id => Null_Unbounded_String,
            Message           => Null_Unbounded_String),
         Message => Null_Unbounded_String);

      if Observed_State = HRA.Issue_Relation.Sidecar.Present then
         if not HRA.Issue_Relation.TSV.Admit
           (Observed_Source, Existing_History, Existing_Diag)
         then
            Diag.Status := Existing_Sidecar_Admission_Failed;
            Diag.TSV := Existing_Diag;
            Diag.Message := To_Unbounded_String
              ("existing Issue relation sidecar is not admitted");
            return False;
         end if;
         Needs_Header :=
           not HRA.Issue_Relation.TSV.Has_Canonical_Header (Observed_Source);
         Rendered := To_Unbounded_String (Observed_Source);
         if Length (Rendered) > 0
           and then Element (Rendered, Length (Rendered)) /= ASCII.LF
         then
            Append (Rendered, ASCII.LF);
         end if;
      else
         Needs_Header := True;
      end if;

      if Needs_Header then
         Append (Rendered, HRA.Issue_Relation.TSV.Canonical_Header_Text);
         Append (Rendered, ASCII.LF);
      end if;

      Append (Rendered, HRA.Issue_Relation.TSV.Render_Event_Row (Event));
      Append (Rendered, ASCII.LF);

      if not HRA.Issue_Relation.TSV.Admit
        (To_String (Rendered), Candidate_History, Candidate_Diag)
      then
         Diag.Status := Candidate_Admission_Failed;
         Diag.TSV := Candidate_Diag;
         Diag.Message := To_Unbounded_String
           ("candidate Issue relation source is not admitted");
         return False;
      end if;

      declare
         Existing_Count  : constant Natural :=
           HRA.Issue_Relation.TSV.Count (Existing_History);
         Candidate_Count : constant Natural :=
           HRA.Issue_Relation.TSV.Count (Candidate_History);
      begin
         if Candidate_Count /= Existing_Count + 1 then
            Diag.Status := Semantic_Roundtrip_Failed;
            Diag.Message := To_Unbounded_String
              ("candidate Issue relation source count mismatch");
            return False;
         end if;

         for I in 1 .. Existing_Count loop
            if not Same_Relation_Event
              (HRA.Issue_Relation.TSV.Element (Candidate_History, I),
               HRA.Issue_Relation.TSV.Element (Existing_History, I))
            then
               Diag.Status := Semantic_Roundtrip_Failed;
               Diag.Message := To_Unbounded_String
                 ("candidate Issue relation source modified existing relation history");
               return False;
            end if;
         end loop;

         if not Same_Relation_Event
           (HRA.Issue_Relation.TSV.Element (Candidate_History, Candidate_Count),
            Event)
         then
            Diag.Status := Semantic_Roundtrip_Failed;
            Diag.Message := To_Unbounded_String
              ("candidate Issue relation source did not preserve appended relation meaning");
            return False;
         end if;
      end;

      Candidate :=
        (Path           => To_Unbounded_String (Path),
         Observed_State => Observed_State,
         Observed_Text  => To_Unbounded_String (Observed_Source),
         Candidate_Text => Rendered,
         History        => Candidate_History);
      return True;
   end Prepare;

end HRA.Issue_Relation_Candidate;
