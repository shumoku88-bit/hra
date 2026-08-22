with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA.Actual_Admission;
with HRA.Dates;
with HRA.Household;
with HRA.Household_Actual_Preparation;
with HRA.Issue_Close;
with HRA.Issue_Realization_Preparation;
with HRA.Issue_Realization_Reconciliation;
with HRA.Issue_Relation;
with HRA.Issue_Relation.Admission;
with HRA.Issue_Relation.Sidecar;
with HRA.Issue_Relation_Candidate;
with HRA.Issues;
with HRA.Journal_Loader;
with HRA.Ledger;
with HRA.Writer;

--  Publication-free preparation of an opaque resume witness for an in-flight
--  Issue realization whose earlier preparation witness was lost.
--
--  This boundary combines exact semantic reconciliation (W0/W1/W2/W3) with
--  freshly captured exact filesystem premises for the remaining publication
--  steps. It grants no publication authority by itself and performs no
--  filesystem mutation.
package HRA.Issue_Realization_Resume is

   subtype Recognized_World is
     HRA.Issue_Realization_Reconciliation.Recognized_World;

   type Prepared_Resume is private;

   function World_Of (Prepared : Prepared_Resume) return Recognized_World;

   type Resume_Status is
     (Success,
      Reconciliation_Failed,
      W0_Preparation_Failed,
      Actual_Graph_Load_Failed,
      Relation_Candidate_Failed,
      Relation_Admission_Failed,
      Issue_Close_Failed,
      Cross_Admission_Failed);

   type Resume_Diagnostic is record
      Status             : Resume_Status := Success;
      Reconciliation     : HRA.Issue_Realization_Reconciliation.Reconciliation_Diagnostic;
      Preparation        : HRA.Issue_Realization_Preparation.Preparation_Diagnostic;
      Relation_Candidate : HRA.Issue_Relation_Candidate.Candidate_Diagnostic;
      Relation_Admission : HRA.Issue_Relation.Admission.Admission_Diagnostic;
      Issue_Close        : HRA.Issue_Close.Close_Diagnostic;
      Message            : Unbounded_String;
   end record;

   --  Prepare an opaque resume witness from the admitted Household state,
   --  the caller's complete realization request, and the current sidecar
   --  observation.
   --
   --  If current state matches W0, W1, W2, or W3, and all missing candidate
   --  sources admit cleanly against their exact premises, Prepared is returned
   --  with the recognized World.
   function Prepare_Resume
     (State                : HRA.Household.Household_State;
      Tx                   : HRA.Ledger.Transaction;
      Issue_ID             : HRA.Issues.Issue_Id;
      Actual_ID            : HRA.Actual_Admission.Actual_Id;
      Relation_Event_ID    : HRA.Issue_Relation.Relation_Event_Id;
      Relation_Recorded_On : HRA.Dates.Date;
      Closed_On            : HRA.Dates.Date;
      Relation_Details     : String;
      Relation_Observation : HRA.Issue_Relation.Sidecar.Observation;
      Prepared             : out Prepared_Resume;
      Diag                 : out Resume_Diagnostic) return Boolean
     with Post =>
       (if Prepare_Resume'Result
        then Diag.Status = Success
        else Diag.Status /= Success);

private

   type Prepared_Resume is record
      World : Recognized_World := HRA.Issue_Realization_Reconciliation.W0;

      --  W0: delegate to full realization preparation
      W0_Prepared : HRA.Issue_Realization_Preparation.Prepared_Realization;

      --  W1 & W2: retained Actual graph sources and Account guard
      Actual_Sources : HRA.Journal_Loader.Source_Observation_Vectors.Vector;
      Account_Guard  : HRA.Writer.Source_Premise;

      --  W1: candidate relation
      W1_Relation_Source  : HRA.Issue_Relation_Candidate.Candidate_Source;
      W1_Relation_History : HRA.Issue_Relation.Admission.Admitted_History;

      --  W2: published relation premise and admitted history
      W2_Relation_Guard   : HRA.Writer.Source_Premise;
      W2_Relation_History : HRA.Issue_Relation.Admission.Admitted_History;

      --  W1 & W2: candidate issue close and open issues guard
      Issues_Source        : HRA.Issue_Close.Candidate_Source;
      Issues_Path          : Unbounded_String;
      Issues_Observed_Text : Unbounded_String;
      Issues_Guard         : HRA.Writer.Source_Premise;
   end record;

end HRA.Issue_Realization_Resume;
