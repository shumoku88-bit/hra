with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA.Plan_Account_Admission;
with HRA.Writer;

--  Filesystem publication boundary for an already Account-qualified Plan
--  candidate graph.
--
--  This package does not rebuild semantic admission and does not re-read graph
--  sources to invent new premises. It translates the retained exact source
--  witness into Writer coordinates: the observed root is the mutable target,
--  the candidate root is the proposed replacement, and included files are
--  read-only guarded premises.
package HRA.Plan_Publication is

   type Publication_Status is
     (Success,
      Invalid_Qualified_Source_Witness,
      Writer_Rejected);

   type Publication_Diagnostic is record
      Status        : Publication_Status := Success;
      Writer_Status : HRA.Writer.Writer_Status := HRA.Writer.Success;
      Message       : Unbounded_String;
   end record;

   --  Publish only the root bound to Candidate. The canonical Plan root is
   --  required to remain present with exactly the bytes retained as its
   --  observed premise. Every included source retained by graph admission must
   --  remain present and byte-identical across Writer's commit window.
   function Publish
     (Candidate : HRA.Plan_Account_Admission.Account_Qualified_Graph;
      Diag      : out Publication_Diagnostic) return Boolean;

   --  The caller may add exact read-only premises whose semantic admission is
   --  owned above the Plan graph. They join the graph include witnesses in
   --  the same Writer commit window; this package still interprets none of
   --  their contents.
   function Publish_With_Guards
     (Candidate         : HRA.Plan_Account_Admission.Account_Qualified_Graph;
      Additional_Guards : HRA.Writer.Source_Premise_Array;
      Diag              : out Publication_Diagnostic) return Boolean;

   --  Exact read-only premises for the world after Candidate has been
   --  published: candidate root bytes and retained include bytes.
   function Published_Source_Premises
     (Candidate : HRA.Plan_Account_Admission.Account_Qualified_Graph)
      return HRA.Writer.Source_Premise_Array;

end HRA.Plan_Publication;
