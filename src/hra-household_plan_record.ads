with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA.Household;
with HRA.Household_Plan_Preparation;
with HRA.Household_Plan_Preparation.Publication;
with HRA.Ledger;
with HRA.Plan;

--  UI-neutral application boundary for creating one Pending Plan from an
--  already-admitted Household.
--
--  Preparation owns candidate/admission semantics. Publication owns the exact
--  filesystem commit. This package only composes those two existing boundaries
--  so delivery adapters do not duplicate the use-case sequence.
package HRA.Household_Plan_Record is

   type Record_Status is
     (Success,
      Already_Present,
      Candidate_Rejected,
      Root_Candidate_Rejected,
      Graph_Admission_Rejected,
      Account_Admission_Rejected,
      Conflicting_Plan_Already_Exists,
      Publication_Rejected);

   type Record_Diagnostic is record
      Status      : Record_Status := Success;
      Preparation : HRA.Household_Plan_Preparation.Preparation_Diagnostic;
      Publication :
        HRA.Household_Plan_Preparation.Publication.Publication_Result;
      Message     : Unbounded_String;
   end record;

   --  Prepare and publish one explicit Pending Plan. State remains the
   --  pre-publication observation and must be re-admitted after mutation.
   --  An exact retry is successful and reported as Already_Present.
   function Record_Pending
     (State   : HRA.Household.Household_State;
      Plan_ID : HRA.Plan.Plan_Id;
      Tx      : HRA.Ledger.Transaction;
      Diag    : out Record_Diagnostic) return Boolean;

end HRA.Household_Plan_Record;
