with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA.Dates;
with HRA.Issues;

--  Pure preparation of one Issue lifecycle close against an already observed
--  complete issues.tsv source.
--
--  This package changes no files. It validates the current source, identifies
--  one Issue by stable Issue_Id, changes only status and closed coordinates in
--  that physical row, then re-admits the complete candidate source.
package HRA.Issue_Close is

   type Close_Disposition is (Resolve_Issue, Drop_Issue);

   type Candidate_Source is private;

   function Text (Candidate : Candidate_Source) return String;

   type Close_Status is
     (Success,
      Source_Admission_Failed,
      Issue_Not_Found,
      Issue_Not_Open,
      Close_Before_Recorded,
      Physical_Row_Mismatch,
      Candidate_Admission_Failed);

   type Close_Diagnostic is record
      Status  : Close_Status := Success;
      Issue   : Unbounded_String;
      Source  : HRA.Issues.Admission_Diagnostic;
      Message : Unbounded_String;
   end record;

   --  Prepare one explicit Issue closure. Closed_On is required; HRA does not
   --  invent or infer a closure coordinate from the Actual date, relation date,
   --  selected Home day, or the machine clock.
   --
   --  Every field except status and closed is retained from the observed row.
   --  In particular, details are not amended implicitly. A Realized_As relation
   --  may carry its own decision details without mutating the Issue narrative.
   function Prepare_Close
     (Existing_Source : String;
      Issue_ID        : HRA.Issues.Issue_Id;
      Disposition     : Close_Disposition;
      Closed_On       : HRA.Dates.Date;
      Candidate       : out Candidate_Source;
      Diag            : out Close_Diagnostic) return Boolean;

private

   type Candidate_Source is record
      Source_Text : Unbounded_String;
   end record;

end HRA.Issue_Close;
