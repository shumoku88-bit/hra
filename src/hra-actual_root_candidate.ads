with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA.Actual_Candidate;
with HRA.Journal;
with HRA.Journal_Evidence;

--  Pure placement of one already-admitted Actual source block into the observed
--  root Journal bytes.
--
--  Candidate_Root keeps the physical root coordinate together with both the
--  exact bytes observed before mutation and the exact candidate bytes produced
--  from them. Later graph admission therefore cannot pair the candidate text
--  with a different root path or reconstruct its publication premise.
--
--  This package does not read the filesystem or resolve include directives.
package HRA.Actual_Root_Candidate is

   type Candidate_Root is private;

   function Root_Path_Of (Candidate : Candidate_Root) return String;
   function Observed_Text (Candidate : Candidate_Root) return String;
   function Text (Candidate : Candidate_Root) return String;

   type Candidate_Status is
     (Success,
      Existing_Root_Journal_Admission_Failed,
      Existing_Root_Evidence_Admission_Failed,
      Candidate_Root_Journal_Admission_Failed,
      Candidate_Root_Evidence_Admission_Failed,
      Semantic_Roundtrip_Failed);

   type Candidate_Diagnostic is record
      Status   : Candidate_Status := Success;
      Journal  : HRA.Journal.Parse_Diagnostic;
      Evidence : HRA.Journal_Evidence.Evidence_Diagnostic;
      Message  : Unbounded_String;
   end record;

   --  Preserve Root_Text byte-for-byte as the observed premise, adding only one
   --  LF to the candidate when the non-empty root lacks a trailing LF, then
   --  append Block exactly. Root_Path is retained as provenance and is never
   --  opened here.
   function Prepare
     (Root_Path : String;
      Root_Text : String;
      Block     : HRA.Actual_Candidate.Candidate_Block;
      Candidate : out Candidate_Root;
      Diag      : out Candidate_Diagnostic) return Boolean
     with Pre => Root_Path'Length > 0;

private

   type Candidate_Root is record
      Root_Path            : Unbounded_String;
      Observed_Source_Text : Unbounded_String;
      Candidate_Source_Text : Unbounded_String;
   end record;

end HRA.Actual_Root_Candidate;
