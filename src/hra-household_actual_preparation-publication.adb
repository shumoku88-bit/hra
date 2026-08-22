with HRA.Writer;

package body HRA.Household_Actual_Preparation.Publication is

   function Publish
     (Prepared : Prepared_Actual;
      Diag     : out HRA.Actual_Publication.Publication_Diagnostic)
      return Boolean
   is
      Account_Guards : constant HRA.Writer.Source_Premise_Array (1 .. 1) :=
        [1 => Prepared.Account_Guard];
   begin
      return HRA.Actual_Publication.Publish_With_Guards
        (Prepared.Qualified, Account_Guards, Diag);
   end Publish;

end HRA.Household_Actual_Preparation.Publication;
