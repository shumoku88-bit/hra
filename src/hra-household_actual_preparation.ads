with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA.Actual_Admission;
with HRA.Actual_Account_Admission;
with HRA.Actual_Candidate;
with HRA.Actual_Graph_Admission;
with HRA.Actual_Root_Candidate;
with HRA.Household;
with HRA.Ledger;
with HRA.Writer;

--  Household-qualified, publication-free preparation of one Actual.
--
--  The opaque result binds the Account-qualified candidate graph to the exact
--  canonical Accounts source premise used by the already-admitted Household.
--  Preparation may read the existing Actual include graph for admission, but
--  it does not publish or otherwise mutate any filesystem source.
package HRA.Household_Actual_Preparation is

   type Prepared_Actual is private;

   function Observation_Of
     (Prepared : Prepared_Actual)
      return HRA.Actual_Admission.Actual_Observation;

   type Preparation_Status is
     (Success,
      Candidate_Rejected,
      Root_Candidate_Rejected,
      Graph_Admission_Rejected,
      Account_Admission_Rejected);

   type Preparation_Diagnostic is record
      Status    : Preparation_Status := Success;
      Candidate : HRA.Actual_Candidate.Candidate_Diagnostic;
      Root      : HRA.Actual_Root_Candidate.Candidate_Diagnostic;
      Graph     : HRA.Actual_Graph_Admission.Admission_Diagnostic;
      Account   : HRA.Actual_Account_Admission.Admission_Diagnostic;
      Message   : Unbounded_String;
   end record;

   --  Prepare one ordinary identity-free Actual through complete graph and
   --  canonical Account admission. No Actual_Id is selected or generated.
   function Prepare_Ordinary
     (State    : HRA.Household.Household_State;
      Tx       : HRA.Ledger.Transaction;
      Prepared : out Prepared_Actual;
      Diag     : out Preparation_Diagnostic) return Boolean;

   --  Prepare one Actual carrying exactly the explicitly supplied
   --  source-durable identity. Identity selection remains the caller's concern.
   function Prepare_Identified
     (State     : HRA.Household.Household_State;
      Tx        : HRA.Ledger.Transaction;
      Actual_ID : HRA.Actual_Admission.Actual_Id;
      Prepared  : out Prepared_Actual;
      Diag      : out Preparation_Diagnostic) return Boolean;

private

   type Prepared_Actual is record
      Qualified      : HRA.Actual_Account_Admission.Account_Qualified_Graph;
      Account_Guard  : HRA.Writer.Source_Premise;
   end record;

end HRA.Household_Actual_Preparation;
