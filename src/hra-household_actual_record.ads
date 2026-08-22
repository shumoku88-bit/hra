with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA.Actual_Admission;
with HRA.Actual_Publication;
with HRA.Household;
with HRA.Household_Actual_Preparation;
with HRA.Ledger;

--  UI-neutral application boundary for preparing and then publishing one
--  Actual from an already-admitted Household.
--
--  Candidate construction and semantic admission belong entirely to
--  Household_Actual_Preparation. This package only preserves the existing
--  record operations by delegating preparation and explicit publication.
package HRA.Household_Actual_Record is

   type Record_Status is
     (Success,
      Candidate_Rejected,
      Root_Candidate_Rejected,
      Graph_Admission_Rejected,
      Account_Admission_Rejected,
      Publication_Rejected);

   type Record_Diagnostic is record
      Status      : Record_Status := Success;
      Preparation : HRA.Household_Actual_Preparation.Preparation_Diagnostic;
      Publication : HRA.Actual_Publication.Publication_Diagnostic;
      Message     : Unbounded_String;
   end record;

   --  Prepare one identity-free Actual and explicitly publish it. State remains
   --  the pre-publication observation and must be re-admitted after mutation.
   function Record_Ordinary
     (State : HRA.Household.Household_State;
      Tx    : HRA.Ledger.Transaction;
      Diag  : out Record_Diagnostic) return Boolean;

   --  Prepare one explicitly source-durable Actual and publish it.
   function Record_Identified
     (State     : HRA.Household.Household_State;
      Tx        : HRA.Ledger.Transaction;
      Actual_ID : HRA.Actual_Admission.Actual_Id;
      Diag      : out Record_Diagnostic) return Boolean;

end HRA.Household_Actual_Record;
