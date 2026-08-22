with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA.Actual_Admission;
with HRA.Journal;
with HRA.Journal_Evidence;
with HRA.Ledger;

--  Pure source-local preparation of one explicit source-durable Actual.
--
--  This package renders one already-typed balanced Transaction into the current
--  Journal source grammar with one explicit event-id, then admits that block
--  back through Journal, Journal_Evidence, and Actual_Admission before exposing
--  it as a candidate. It does not append to a root Journal, resolve includes,
--  inspect Household Accounts, or publish files.
package HRA.Actual_Candidate is

   type Candidate_Block is private;

   function Text (Candidate : Candidate_Block) return String;

   type Candidate_Status is
     (Success,
      Unbalanced_Transaction,
      Transaction_Already_Owns_Identity,
      Description_Required,
      Description_Has_Surrounding_Whitespace,
      Description_Contains_Line_Break,
      Posting_Memo_Not_Representable,
      Journal_Admission_Failed,
      Evidence_Admission_Failed,
      Actual_Admission_Failed,
      Semantic_Roundtrip_Failed);

   type Candidate_Diagnostic is record
      Status          : Candidate_Status := Success;
      Journal         : HRA.Journal.Parse_Diagnostic;
      Evidence        : HRA.Journal_Evidence.Evidence_Diagnostic;
      Actual          : HRA.Actual_Admission.Admission_Diagnostic;
      Message         : Unbounded_String;
   end record;

   --  Prepare one canonical source block for an ordinary Actual transaction.
   --  Actual_ID becomes explicit `event-id` metadata owned by the source.
   --
   --  Tx.Event_ID and Tx.Reverses_ID must be empty. Reversal preparation is a
   --  separate semantic operation and source identity must not have two owners.
   --  Description is required and must not carry surrounding whitespace, so
   --  source generation never invents or silently normalizes semantic text.
   --  Posting memo is rejected until the Journal grammar has a lossless posting
   --  memo representation.
   function Prepare
     (Tx        : HRA.Ledger.Transaction;
      Actual_ID : HRA.Actual_Admission.Actual_Id;
      Candidate : out Candidate_Block;
      Diag      : out Candidate_Diagnostic) return Boolean;

private

   type Candidate_Block is record
      Source_Text : Unbounded_String;
   end record;

end HRA.Actual_Candidate;
