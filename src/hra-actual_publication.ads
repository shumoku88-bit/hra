with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA.Actual_Account_Admission;
with HRA.Writer;

--  Filesystem publication boundary for an already Account-qualified Actual
--  candidate graph.
--
--  This package does not rebuild semantic admission and does not re-read graph
--  sources to invent new premises. It translates the retained exact source
--  witness into Writer coordinates: the observed root is the mutable target,
--  the candidate root is the proposed replacement, and included files are
--  read-only guarded premises.
package HRA.Actual_Publication is

   type Publication_Status is
     (Success,
      Invalid_Qualified_Source_Witness,
      Writer_Rejected);

   type Publication_Diagnostic is record
      Status        : Publication_Status := Success;
      Writer_Status : HRA.Writer.Writer_Status := HRA.Writer.Success;
      Message       : Unbounded_String;
   end record;

   --  Publish only the root bound to Candidate. The canonical Actual root is
   --  required to remain present with exactly the bytes retained as its
   --  observed premise. Every included source retained by graph admission must
   --  remain present and byte-identical across Writer's commit window.
   function Publish
     (Candidate : HRA.Actual_Account_Admission.Account_Qualified_Graph;
      Diag      : out Publication_Diagnostic) return Boolean;

end HRA.Actual_Publication;
