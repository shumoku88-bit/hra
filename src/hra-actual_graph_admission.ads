with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA.Actual_Admission;
with HRA.Actual_Root_Candidate;

--  Filesystem-backed admission of one complete Actual candidate graph.
--
--  The already-admitted Existing observation is the current Actual authority.
--  Candidate_Root supplies the already-qualified root bytes. Journal_Loader may
--  read included documents once to construct the candidate graph, but this
--  package never rereads the original root or reconstructs Existing authority.
--
--  The returned Candidate_Graph is intentionally not a Household-qualified
--  Actual authority. Account-registry validation and publication remain later
--  boundaries.
package HRA.Actual_Graph_Admission is

   type Candidate_Graph is private;

   function Observation_Of
     (Candidate : Candidate_Graph)
      return HRA.Actual_Admission.Actual_Observation;

   type Admission_Status is
     (Success,
      Candidate_Graph_Load_Failed,
      Candidate_Actual_Admission_Failed,
      Candidate_History_Count_Mismatch,
      Existing_History_Changed,
      Existing_Reversal_History_Changed,
      Appended_Actual_Not_Source_Durable,
      Appended_Actual_Not_Root_Owned);

   type Admission_Diagnostic is record
      Status  : Admission_Status := Success;
      Actual  : HRA.Actual_Admission.Admission_Diagnostic;
      Message : Unbounded_String;
   end record;

   --  Resolve and admit Candidate_Root through the current include graph.
   --  Success requires the supplied Existing observation to remain an exact
   --  admitted prefix and exactly one new source-durable, root-owned Actual to
   --  appear at the end. No file is written here.
   function Admit_Candidate_Root
     (Existing       : HRA.Actual_Admission.Actual_Observation;
      Root_Path      : String;
      Candidate_Root : HRA.Actual_Root_Candidate.Candidate_Root;
      Candidate      : out Candidate_Graph;
      Diag           : out Admission_Diagnostic) return Boolean
     with Pre => Root_Path'Length > 0;

private

   type Candidate_Graph is record
      Actual : HRA.Actual_Admission.Actual_Observation;
   end record;

end HRA.Actual_Graph_Admission;
