with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA.Journal;
with HRA.Journal_Evidence;
with HRA.Ledger;
with HRA.Plan;
with HRA.Plan_Admission;

--  Pure source-local preparation of one Plan candidate block.
--
--  This package renders one already-typed balanced Transaction carrying an
--  explicit source-durable Plan_Id into the current Journal source grammar,
--  then admits that block back through Journal, Journal_Evidence, and
--  Plan_Admission before exposing it as a candidate.
--  It does not append to a root Journal, resolve includes, inspect Household
--  Accounts, or publish files.
--
--  Description is required and must not carry surrounding whitespace, so
--  source generation never invents or silently normalizes semantic text.
package HRA.Plan_Candidate is

   type Candidate_Block is private;

   function Text (Candidate : Candidate_Block) return String;

   type Candidate_Status is
     (Success,
      Invalid_Plan_Id,
      Unbalanced_Transaction,
      Transaction_Already_Owns_Identity,
      Description_Required,
      Description_Has_Surrounding_Whitespace,
      Description_Contains_Line_Break,
      Posting_Memo_Not_Representable,
      Journal_Admission_Failed,
      Evidence_Admission_Failed,
      Plan_Admission_Failed,
      Semantic_Roundtrip_Failed);

   type Candidate_Diagnostic is record
      Status   : Candidate_Status := Success;
      Journal  : HRA.Journal.Parse_Diagnostic;
      Evidence : HRA.Journal_Evidence.Evidence_Diagnostic;
      Plan     : HRA.Plan_Admission.Admission_Diagnostic;
      Message  : Unbounded_String;
   end record;

   --  Prepare one pending Plan candidate block.
   --
   --  The rendered source carries exactly one `; plan-id: <id>` metadata line
   --  and no retirement metadata. The round-tripped Plan_Transaction_Entry
   --  must have Retirement.Kind = No_Retirement and ID = Plan_ID.
   --
   --  Plan_ID must not be null.
   --  Tx.Event_ID and Tx.Reverses_ID must be empty.
   --  Description is required and must not carry surrounding whitespace.
   --  Posting memo is rejected until the Journal grammar has a lossless
   --  posting memo representation.
   function Prepare_Pending
     (Tx        : HRA.Ledger.Transaction;
      Plan_ID   : HRA.Plan.Plan_Id;
      Candidate : out Candidate_Block;
      Diag      : out Candidate_Diagnostic) return Boolean;

private

   type Candidate_Block is record
      Source_Text : Unbounded_String;
   end record;

end HRA.Plan_Candidate;
