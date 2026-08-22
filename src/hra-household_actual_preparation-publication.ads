with HRA.Actual_Publication;

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

end HRA.Household_Actual_Preparation.Publication;
