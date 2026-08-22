with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA.Issue_Relation;
with HRA.Issue_Relation.Sidecar;
with HRA.Issue_Relation.TSV;

--  Pure source-local preparation of one explicit Issue relation candidate against
--  an observed issue-relations.tsv sidecar.
--
--  This package changes no files and does not perform cross-source endpoint
--  reference validation. It preserves the observed sidecar premise exactly,
--  renders the new relation into canonical TSV syntax, and re-admits the complete
--  candidate text through HRA.Issue_Relation.TSV before exposing it.
package HRA.Issue_Relation_Candidate is

   type Candidate_Source is private;

   function Path_Of (Candidate : Candidate_Source) return String;

   function Observed_State_Of
     (Candidate : Candidate_Source) return HRA.Issue_Relation.Sidecar.Presence;

   function Observed_Text (Candidate : Candidate_Source) return String;

   function Text (Candidate : Candidate_Source) return String;

   function History_Of
     (Candidate : Candidate_Source) return HRA.Issue_Relation.TSV.Relation_History;

   type Candidate_Status is
     (Success,
      Existing_Sidecar_Admission_Failed,
      Candidate_Admission_Failed,
      Semantic_Roundtrip_Failed);

   type Candidate_Diagnostic is record
      Status  : Candidate_Status := Success;
      TSV     : HRA.Issue_Relation.TSV.Admission_Diagnostic;
      Message : Unbounded_String;
   end record;

   --  Prepare one publication-ready relation candidate source by appending Event
   --  to the observed sidecar.
   --
   --  If Observed is Absent or Present with empty / comment-only content lacking
   --  a header, the canonical header is placed before the row.
   --  Existing bytes are preserved byte-for-byte at the head of the candidate.
   --  The candidate is re-admitted via HRA.Issue_Relation.TSV, ensuring relation
   --  event ID uniqueness and full syntax compliance.
   function Prepare
     (Observed  : HRA.Issue_Relation.Sidecar.Observation;
      Event     : HRA.Issue_Relation.Relation_Event;
      Candidate : out Candidate_Source;
      Diag      : out Candidate_Diagnostic) return Boolean;

private

   type Candidate_Source is record
      Path           : Unbounded_String;
      Observed_State : HRA.Issue_Relation.Sidecar.Presence :=
        HRA.Issue_Relation.Sidecar.Absent;
      Observed_Text  : Unbounded_String;
      Candidate_Text : Unbounded_String;
      History        : HRA.Issue_Relation.TSV.Relation_History;
   end record;

end HRA.Issue_Relation_Candidate;
