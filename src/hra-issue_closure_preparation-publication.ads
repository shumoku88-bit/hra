with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA.Writer;

--  Guarded single-target publication of one prepared Issue closure without
--  financial fact.
package HRA.Issue_Closure_Preparation.Publication is

   type Result_Kind is (Completed, Failed);
   type Completion_Kind is (Newly_Closed, Already_Closed);
   type Failure_Kind is (Writer_Failure, Post_Admission_Failure);

   type Publication_Result (Kind : Result_Kind := Completed) is record
      Writer_Status : HRA.Writer.Writer_Status := HRA.Writer.Success;
      Message       : Unbounded_String;
      case Kind is
         when Completed =>
            Completion : Completion_Kind := Newly_Closed;
         when Failed =>
            Failure    : Failure_Kind := Writer_Failure;
      end case;
   end record;

   --  Publish the prepared Issue closure to issues.tsv.
   --
   --  If Prepared was recognized as already closed, succeeds as a no-op with
   --  Completion => Already_Closed.
   --
   --  Otherwise, executes an exact single-target guarded atomic replacement on
   --  issues.tsv and re-admits the written source to verify domain lifecycle.
   function Publish
     (Prepared : Prepared_Closure;
      Result   : out Publication_Result) return Boolean
     with Post =>
       (if Publish'Result
        then Result.Kind = Completed
        else Result.Kind = Failed);

end HRA.Issue_Closure_Preparation.Publication;
