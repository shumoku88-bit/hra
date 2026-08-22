with HRA.Writer;

--  Explicit filesystem publication boundary for one Household-prepared Plan.
--
--  As a child of Household_Plan_Preparation, this package can consume the
--  private graph/premise binding without exposing either coordinate for caller
--  recombination. The parent preparation package remains publication-free.
package HRA.Household_Plan_Preparation.Publication is

   type Publication_Kind is (Completed, Failed);
   type Completion_Kind is (Newly_Published, Already_Present);
   type Failure_Kind is (None, Writer_Failure, Post_Admission_Failure);

   type Publication_Result is record
      Kind          : Publication_Kind := Completed;
      Completion    : Completion_Kind  := Newly_Published;
      Failure       : Failure_Kind     := None;
      Writer_Status : HRA.Writer.Writer_Status := HRA.Writer.Success;
      Message       : Unbounded_String;
   end record;

   function Publish
     (Prepared : Prepared_Plan;
      Result   : out Publication_Result) return Boolean;

   --  Publish the same opaque prepared Plan while additional composition
   --  premises remain exact. The additional guards do not acquire meaning at
   --  this boundary; they only join the existing Account and include-graph
   --  fences in the one Plan target's Writer commit window.
   function Publish_With_Guards
     (Prepared          : Prepared_Plan;
      Additional_Guards : HRA.Writer.Source_Premise_Array;
      Result            : out Publication_Result) return Boolean;

   --  Exact read-only premises for the world after Prepared has been
   --  published: candidate root bytes, retained include bytes, and the Account
   --  source used for qualification.
   function Published_Source_Premises
     (Prepared : Prepared_Plan) return HRA.Writer.Source_Premise_Array;

end HRA.Household_Plan_Preparation.Publication;
