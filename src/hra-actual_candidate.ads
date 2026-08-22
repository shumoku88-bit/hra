with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA.Actual_Admission;
with HRA.Journal;
with HRA.Journal_Evidence;
with HRA.Ledger;

--  Pure source-local preparation of one Actual candidate block.
--
--  This package renders one already-typed balanced Transaction into the current
--  Journal source grammar, then admits that block back through Journal,
--  Journal_Evidence, and Actual_Admission before exposing it as a candidate.
--  It does not append to a root Journal, resolve includes, inspect Household
--  Accounts, or publish files.
--
--  Two preparation modes are supported:
--
--    Prepare_Ordinary   — identity-free Actual (no event-id metadata)
--    Prepare_Identified — one explicit source-durable event-id
--
--  Description is required and must not carry surrounding whitespace, so
--  source generation never invents or silently normalizes semantic text.
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

   --  Prepare one identity-free ordinary Actual block.
   --
   --  The rendered source carries no event-id metadata. The round-tripped
   --  Actual_Transaction_Entry has Identity.Present = False and
   --  Source_Durable_Identity.Present = False.
   --
   --  Tx.Event_ID and Tx.Reverses_ID must be empty.
   --  Description is required and must not carry surrounding whitespace.
   --  Posting memo is rejected until the Journal grammar has a lossless
   --  posting memo representation.
   function Prepare_Ordinary
     (Tx        : HRA.Ledger.Transaction;
      Candidate : out Candidate_Block;
      Diag      : out Candidate_Diagnostic) return Boolean;

   --  Prepare one source-durable identified Actual block.
   --
   --  The rendered source carries one `; event-id: <id>` metadata line.
   --  The round-tripped Actual_Transaction_Entry has Identity.Present = True
   --  and Source_Durable_Identity.Present = True, both holding Actual_ID.
   --
   --  Same preconditions as Prepare_Ordinary apply.
   function Prepare_Identified
     (Tx        : HRA.Ledger.Transaction;
      Actual_ID : HRA.Actual_Admission.Actual_Id;
      Candidate : out Candidate_Block;
      Diag      : out Candidate_Diagnostic) return Boolean;

private

   type Candidate_Block is record
      Source_Text : Unbounded_String;
   end record;

end HRA.Actual_Candidate;
