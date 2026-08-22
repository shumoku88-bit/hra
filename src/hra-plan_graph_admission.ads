with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA.Journal_Loader;
with HRA.Plan_Admission;
with HRA.Plan_Root_Candidate;

--  Filesystem-backed admission of one complete Plan candidate graph.
--
--  The already-admitted Existing observation is the current Plan authority.
--  Candidate_Root supplies its own root coordinate together with observed and
--  candidate bytes. Journal_Loader may read included documents once to
--  construct the candidate graph, and the exact source observations from that
--  same admission are retained inside Candidate_Graph.
--
--  The returned Candidate_Graph is intentionally not a Household-qualified
--  Plan authority. Account-registry validation and publication remain later
--  boundaries.
package HRA.Plan_Graph_Admission is

   type Candidate_Graph is private;

   function Plan_Journal_Of
     (Candidate : Candidate_Graph)
      return HRA.Plan_Admission.Plan_Journal;

   function Root_Of
     (Candidate : Candidate_Graph)
      return HRA.Plan_Root_Candidate.Candidate_Root;

   function Source_Count (Candidate : Candidate_Graph) return Natural;

   function Source_At
     (Candidate : Candidate_Graph;
      Index     : Positive) return HRA.Journal_Loader.Source_Observation
     with Pre => Index <= Source_Count (Candidate);

   type Admission_Status is
     (Success,
      Candidate_Graph_Load_Failed,
      Candidate_Source_Witness_Mismatch,
      Candidate_Plan_Admission_Failed,
      Candidate_History_Count_Mismatch,
      Existing_History_Changed,
      Appended_Plan_Not_Root_Owned,
      Appended_Plan_Not_Pending);

   type Admission_Diagnostic is record
      Status  : Admission_Status := Success;
      Plan    : HRA.Plan_Admission.Admission_Diagnostic;
      Message : Unbounded_String;
   end record;

   --  Resolve and admit Candidate_Root through the current include graph.
   --  Success requires the supplied Existing observation to remain an exact
   --  admitted prefix and exactly one new root-owned pending Plan to appear at
   --  the end. The root coordinate cannot be supplied separately from the root
   --  candidate, and no file is written here.
   function Admit_Candidate_Root
     (Existing       : HRA.Plan_Admission.Plan_Journal;
      Candidate_Root : HRA.Plan_Root_Candidate.Candidate_Root;
      Candidate      : out Candidate_Graph;
      Diag           : out Admission_Diagnostic) return Boolean;

private

   type Candidate_Graph is record
      Root    : HRA.Plan_Root_Candidate.Candidate_Root;
      Sources : HRA.Journal_Loader.Source_Observation_Vectors.Vector;
      Plan    : HRA.Plan_Admission.Plan_Journal;
   end record;

end HRA.Plan_Graph_Admission;
