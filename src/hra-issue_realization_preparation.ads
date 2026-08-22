with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA.Actual_Admission;
with HRA.Dates;
with HRA.Household;
with HRA.Household_Actual_Preparation;
with HRA.Issue_Close;
with HRA.Issue_Relation;
with HRA.Issue_Relation.Admission;
with HRA.Issue_Relation.Sidecar;
with HRA.Issue_Relation_Candidate;
with HRA.Issues;
with HRA.Ledger;
with HRA.Writer;

--  Publication-free composition of one Issue realization candidate world.
--
--  The opaque result binds an identified Actual candidate, a Realized_As
--  relation candidate admitted against that candidate Actual universe, and a
--  resolved Issue candidate to their exact observed source premises. It grants
--  no publication authority and exposes no independently recombinable source
--  candidate or publication coordinate.
package HRA.Issue_Realization_Preparation is

   type Prepared_Realization is private;

   --  The one currently needed pure semantic projection. In particular, this
   --  exposes the candidate Actual identity universe without exposing any of
   --  the three retained source candidates or premises.
   function Actual_Observation_Of
     (Prepared : Prepared_Realization)
      return HRA.Actual_Admission.Actual_Observation;

   type Preparation_Status is
     (Success,
      Actual_Preparation_Rejected,
      Relation_Observation_Root_Mismatch,
      Relation_Creation_Rejected,
      Relation_Candidate_Rejected,
      Relation_Reference_Admission_Rejected,
      Issue_Close_Rejected);

   type Preparation_Diagnostic is record
      Status             : Preparation_Status := Success;
      Actual             : HRA.Household_Actual_Preparation.Preparation_Diagnostic;
      Relation_Creation  : HRA.Issue_Relation.Create_Status :=
        HRA.Issue_Relation.Create_Success;
      Relation_Candidate : HRA.Issue_Relation_Candidate.Candidate_Diagnostic;
      Relation_Admission : HRA.Issue_Relation.Admission.Admission_Diagnostic;
      Issue_Close        : HRA.Issue_Close.Close_Diagnostic;
      Message            : Unbounded_String;
   end record;

   --  Prepare the fixed realization composition:
   --    Open Issue -> identified Actual -> Realized_As -> Resolve_Issue.
   --
   --  All three temporal coordinates are caller-owned and independent. Tx.Date,
   --  Relation_Recorded_On, and Closed_On are neither inferred nor compared by
   --  this composition boundary beyond Issue_Close's own lifecycle law.
   function Prepare
     (State                : HRA.Household.Household_State;
      Tx                   : HRA.Ledger.Transaction;
      Issue_ID             : HRA.Issues.Issue_Id;
      Actual_ID            : HRA.Actual_Admission.Actual_Id;
      Relation_Event_ID    : HRA.Issue_Relation.Relation_Event_Id;
      Relation_Recorded_On : HRA.Dates.Date;
      Closed_On            : HRA.Dates.Date;
      Relation_Details     : String;
      Relation_Observation : HRA.Issue_Relation.Sidecar.Observation;
      Prepared             : out Prepared_Realization;
      Diag                 : out Preparation_Diagnostic) return Boolean;

private

   type Prepared_Realization is record
      Actual           : HRA.Household_Actual_Preparation.Prepared_Actual;
      Relation_Source  : HRA.Issue_Relation_Candidate.Candidate_Source;
      Relation_History : HRA.Issue_Relation.Admission.Admitted_History;
      Issues_Source    : HRA.Issue_Close.Candidate_Source;
      Issues_Guard     : HRA.Writer.Source_Premise;
   end record;

end HRA.Issue_Realization_Preparation;
