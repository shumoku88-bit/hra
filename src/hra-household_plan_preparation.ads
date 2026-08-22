with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA.Household;
with HRA.Ledger;
with HRA.Plan;
with HRA.Plan_Account_Admission;
with HRA.Plan_Candidate;
with HRA.Plan_Graph_Admission;
with HRA.Plan_Root_Candidate;
with HRA.Writer;

--  Household-qualified, publication-free preparation of one Plan creation request.
--
--  The opaque result binds the Account-qualified candidate graph to the exact
--  canonical Accounts source premise used by the already-admitted Household.
--  Preparation may read the existing Plan include graph for admission, but
--  it does not publish or otherwise mutate any filesystem source.
--
--  It also recognizes exact retry requests when the Plan is already present
--  in the admitted Household with identical intention date, description,
--  postings, pending lifecycle status, and durable Plan_Id.
package HRA.Household_Plan_Preparation is

   type Prepared_Plan is private;

   function Plan_Id_Of (Prepared : Prepared_Plan) return HRA.Plan.Plan_Id;
   function Transaction_Of (Prepared : Prepared_Plan) return HRA.Ledger.Transaction;
   function Is_Already_Present (Prepared : Prepared_Plan) return Boolean;

   type Preparation_Status is
     (Success,
      Already_Present_As_Requested,
      Candidate_Rejected,
      Root_Candidate_Rejected,
      Graph_Admission_Rejected,
      Account_Admission_Rejected,
      Conflicting_Plan_Already_Exists);

   type Preparation_Diagnostic is record
      Status    : Preparation_Status := Success;
      Candidate : HRA.Plan_Candidate.Candidate_Diagnostic;
      Root      : HRA.Plan_Root_Candidate.Candidate_Diagnostic;
      Graph     : HRA.Plan_Graph_Admission.Admission_Diagnostic;
      Account   : HRA.Plan_Account_Admission.Admission_Diagnostic;
      Message   : Unbounded_String;
   end record;

   --  Prepare one explicit Plan creation request.
   --
   --  If the Plan does not exist in State.Plan_Journal, prepares candidate
   --  block, root candidate, candidate graph, and validates all postings
   --  against State.Registry.
   --
   --  If the Plan is already present in State.Plan_Journal, verifies exact
   --  equality on:
   --    1. stable Plan_Id matches target
   --    2. lifecycle retirement status is No_Retirement (Pending)
   --    3. transaction date matches Tx.Date
   --    4. description matches Tx.Code_Or_Payee
   --    5. postings match Tx.Postings exactly
   --  When these match, recognizes the world as Already_Present_As_Requested
   --  (valid witness for a guarded no-op publication).
   --
   --  Any conflicting existing Plan with different meaning fails closed.
   function Prepare
     (State    : HRA.Household.Household_State;
      Plan_ID  : HRA.Plan.Plan_Id;
      Tx       : HRA.Ledger.Transaction;
      Prepared : out Prepared_Plan;
      Diag     : out Preparation_Diagnostic) return Boolean;

private

   type Prepared_Plan is record
      Target_Plan_ID     : HRA.Plan.Plan_Id;
      Target_Tx          : HRA.Ledger.Transaction;
      Target_Path        : Unbounded_String;
      Expected_Root_Text : Unbounded_String;
      Account_Guard_Path : Unbounded_String;
      Account_Guard_Text : Unbounded_String;
      Account_Guard      : HRA.Writer.Source_Premise;
      Qualified          : HRA.Plan_Account_Admission.Account_Qualified_Graph;
      Already_Present    : Boolean := False;
   end record;

   function Plan_Id_Of (Prepared : Prepared_Plan) return HRA.Plan.Plan_Id is
     (Prepared.Target_Plan_ID);

   function Transaction_Of (Prepared : Prepared_Plan) return HRA.Ledger.Transaction is
     (Prepared.Target_Tx);

   function Is_Already_Present (Prepared : Prepared_Plan) return Boolean is
     (Prepared.Already_Present);

end HRA.Household_Plan_Preparation;
