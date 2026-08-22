with HRA.Actual_Publication;
with HRA.Writer;

--  Explicit filesystem publication boundary for one Household-prepared Actual.
--
--  As a child of Household_Actual_Preparation, this package can consume the
--  private graph/premise binding without exposing either coordinate for caller
--  recombination. The parent preparation package remains publication-free.
package HRA.Household_Actual_Preparation.Publication is

   function Publish
     (Prepared : Prepared_Actual;
      Diag     : out HRA.Actual_Publication.Publication_Diagnostic)
      return Boolean;

   --  Publish the same opaque prepared Actual while additional composition
   --  premises remain exact. The additional guards do not acquire meaning at
   --  this boundary; they only join the existing Account and include-graph
   --  fences in the one Actual target's Writer commit window.
   function Publish_With_Guards
     (Prepared         : Prepared_Actual;
      Additional_Guards : HRA.Writer.Source_Premise_Array;
      Diag              : out HRA.Actual_Publication.Publication_Diagnostic)
      return Boolean;

   --  Exact read-only premises for the world after Prepared has been
   --  published: candidate root bytes, retained include bytes, and the Account
   --  source used for qualification. Source_Premise is opaque, so composition
   --  boundaries may fence this world without recovering source semantics.
   function Published_Source_Premises
     (Prepared : Prepared_Actual) return HRA.Writer.Source_Premise_Array;

end HRA.Household_Actual_Preparation.Publication;
