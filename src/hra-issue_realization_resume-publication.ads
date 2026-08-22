with HRA.Issue_Realization_Preparation.Publication;

--  Ordered single-target publication of one opaque resume witness.
--
--  Executes only the missing suffix steps for the recognized world:
--    W0: Actual -> Relation -> Issue
--    W1: Relation -> Issue
--    W2: Issue
--    W3: no-op (already complete)
--
--  Each step is a single-target guarded write. A failure at any step preserves
--  the last confirmed world without cross-step rollback.
package HRA.Issue_Realization_Resume.Publication is

   use type HRA.Issue_Realization_Preparation.Publication.Confirmed_World;
   use type HRA.Issue_Realization_Preparation.Publication.Result_Kind;

   subtype Confirmed_World is
     HRA.Issue_Realization_Preparation.Publication.Confirmed_World;

   subtype Publication_Step is
     HRA.Issue_Realization_Preparation.Publication.Publication_Step;

   subtype Failure_Kind is
     HRA.Issue_Realization_Preparation.Publication.Failure_Kind;

   subtype Result_Kind is
     HRA.Issue_Realization_Preparation.Publication.Result_Kind;

   subtype Publication_Result is
     HRA.Issue_Realization_Preparation.Publication.Publication_Result;

   function Publish
     (Prepared : Prepared_Resume;
      Result   : out Publication_Result) return Boolean
     with Post =>
       (if Publish'Result
        then Result.Kind = HRA.Issue_Realization_Preparation.Publication.Completed
             and then Result.Last_Confirmed = HRA.Issue_Realization_Preparation.Publication.W3
        else Result.Kind = HRA.Issue_Realization_Preparation.Publication.Failed);

end HRA.Issue_Realization_Resume.Publication;
