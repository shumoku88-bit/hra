with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA.Actual_Admission;
with HRA.Actual_Candidate;
with HRA.Dates;
with HRA.Household;
with HRA.Issue_Relation;
with HRA.Issue_Relation.Admission;
with HRA.Issue_Relation.Sidecar;
with HRA.Issues;
with HRA.Ledger;

--  Domain-specific recognition of an already published Issue realization
--  prefix after the original opaque preparation witness has been lost.
--
--  The caller must re-present the complete realization request together with
--  one currently admitted Household and the current Issue relation sidecar
--  observation. Existing identities are never treated as idempotent success by
--  themselves. An existing Actual must carry the requested source-durable
--  identity and exactly the requested typed Transaction meaning; an existing
--  relation event must exactly match every requested relation field; and the
--  Issue lifecycle must be compatible with the recognized prefix.
--
--  This package only recognizes W0/W1/W2/W3. It grants no publication authority,
--  retains no filesystem recovery marker, and performs no automatic recovery.
package HRA.Issue_Realization_Reconciliation is

   type Recognized_World is (W0, W1, W2, W3);

   type Reconciliation_Status is
     (Success,
      Actual_Request_Rejected,
      Relation_Request_Rejected,
      Relation_Observation_Root_Mismatch,
      Issue_Not_Found,
      Relation_Source_Admission_Rejected,
      Actual_Identity_Collision,
      Actual_Meaning_Mismatch,
      Relation_Meaning_Mismatch,
      Issue_Lifecycle_Mismatch);

   type Reconciliation_Diagnostic is record
      Status             : Reconciliation_Status := Success;
      Actual             : HRA.Actual_Candidate.Candidate_Diagnostic;
      Relation_Creation  : HRA.Issue_Relation.Create_Status :=
        HRA.Issue_Relation.Create_Success;
      Relation_Admission : HRA.Issue_Relation.Admission.Admission_Diagnostic;
      Message            : Unbounded_String;
   end record;

   function Reconcile
     (State                : HRA.Household.Household_State;
      Tx                   : HRA.Ledger.Transaction;
      Issue_ID             : HRA.Issues.Issue_Id;
      Actual_ID            : HRA.Actual_Admission.Actual_Id;
      Relation_Event_ID    : HRA.Issue_Relation.Relation_Event_Id;
      Relation_Recorded_On : HRA.Dates.Date;
      Closed_On            : HRA.Dates.Date;
      Relation_Details     : String;
      Relation_Observation : HRA.Issue_Relation.Sidecar.Observation;
      World                : out Recognized_World;
      Diag                 : out Reconciliation_Diagnostic) return Boolean
     with Post =>
       (if Reconcile'Result
        then Diag.Status = Success
        else Diag.Status /= Success);

end HRA.Issue_Realization_Reconciliation;
