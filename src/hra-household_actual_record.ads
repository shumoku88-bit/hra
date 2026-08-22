with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA.Actual_Admission;
with HRA.Actual_Account_Admission;
with HRA.Actual_Candidate;
with HRA.Actual_Graph_Admission;
with HRA.Actual_Publication;
with HRA.Actual_Root_Candidate;
with HRA.Household;
with HRA.Ledger;

--  UI-neutral application boundary for recording an Actual transaction from an
--  already-admitted Household.
--
--  The Household owns the current canonical Account universe, admitted Actual
--  authority, root coordinate, and exact root source premise. This package
--  threads those existing premises through the typed Actual preparation and
--  publication layers. It does not interpret terminal keys, collect form input,
--  infer a domain date, generate an Actual_Id, close Issues, or refresh UI state.
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
      Candidate   : HRA.Actual_Candidate.Candidate_Diagnostic;
      Root        : HRA.Actual_Root_Candidate.Candidate_Diagnostic;
      Graph       : HRA.Actual_Graph_Admission.Admission_Diagnostic;
      Account     : HRA.Actual_Account_Admission.Admission_Diagnostic;
      Publication : HRA.Actual_Publication.Publication_Diagnostic;
      Message     : Unbounded_String;
   end record;

   --  Record one explicit typed transaction through the complete ordinary
   --  identity-free Actual path:
   --
   --    source-local candidate -> root candidate -> complete graph admission
   --    -> canonical Account qualification -> exact guarded publication
   --
   --  State is observation-only here. On success it still describes the
   --  pre-publication Household; an interactive shell may re-admit the
   --  Household afterwards before accepting another mutation.
   function Record_Ordinary
     (State : HRA.Household.Household_State;
      Tx    : HRA.Ledger.Transaction;
      Diag  : out Record_Diagnostic) return Boolean;

   --  Record one explicit typed transaction as a source-durable identified Actual
   --  through the complete publication path:
   function Record_Identified
     (State     : HRA.Household.Household_State;
      Tx        : HRA.Ledger.Transaction;
      Actual_ID : HRA.Actual_Admission.Actual_Id;
      Diag      : out Record_Diagnostic) return Boolean;

end HRA.Household_Actual_Record;
