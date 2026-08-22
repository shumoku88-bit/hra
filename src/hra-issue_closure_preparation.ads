with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA.Dates;
with HRA.Household;
with HRA.Issue_Close;
with HRA.Issues;

--  Publication-free preparation of one Issue lifecycle close without financial
--  fact (Resolve_Issue or Drop_Issue).
--
--  The opaque result binds an Issue close candidate to its exact observed
--  source premises. It also recognizes exact retry requests when the Issue
--  is already closed with identical disposition and closure coordinate.
package HRA.Issue_Closure_Preparation is

   type Prepared_Closure is private;

   function Issue_Id_Of (Prepared : Prepared_Closure) return HRA.Issues.Issue_Id;
   function Disposition_Of (Prepared : Prepared_Closure) return HRA.Issue_Close.Close_Disposition;
   function Closed_On_Of (Prepared : Prepared_Closure) return HRA.Dates.Date;
   function Is_Already_Closed (Prepared : Prepared_Closure) return Boolean;

   type Preparation_Status is
     (Success,
      Already_Closed_As_Requested,
      Issue_Close_Rejected);

   type Preparation_Diagnostic is record
      Status      : Preparation_Status := Success;
      Issue_Close : HRA.Issue_Close.Close_Diagnostic;
      Message     : Unbounded_String;
   end record;

   --  Prepare one explicit Issue closure without financial fact.
   --
   --  If the Issue is Open, prepares a candidate issues.tsv source changing only
   --  status and closed coordinate while preserving all other fields.
   --
   --  If the Issue is already closed with the exact requested disposition,
   --  exact requested Closed_On, and consistent identity, recognizes it as
   --  Already_Closed_As_Requested (valid witness for a no-op publication).
   --
   --  Any other state (non-open with different date or disposition, nonexistent
   --  issue, invalid closed date before recorded date, etc.) fails closed.
   function Prepare
     (State       : HRA.Household.Household_State;
      Issue_ID    : HRA.Issues.Issue_Id;
      Disposition : HRA.Issue_Close.Close_Disposition;
      Closed_On   : HRA.Dates.Date;
      Prepared    : out Prepared_Closure;
      Diag        : out Preparation_Diagnostic) return Boolean;

private

   type Prepared_Closure is record
      Target_Path        : Unbounded_String;
      Expected_Text      : Unbounded_String;
      Candidate          : HRA.Issue_Close.Candidate_Source;
      Target_Issue_ID    : HRA.Issues.Issue_Id;
      Target_Disposition : HRA.Issue_Close.Close_Disposition;
      Target_Closed_On   : HRA.Dates.Date;
      Already_Closed     : Boolean := False;
   end record;

   function Issue_Id_Of (Prepared : Prepared_Closure) return HRA.Issues.Issue_Id is
     (Prepared.Target_Issue_ID);

   function Disposition_Of (Prepared : Prepared_Closure) return HRA.Issue_Close.Close_Disposition is
     (Prepared.Target_Disposition);

   function Closed_On_Of (Prepared : Prepared_Closure) return HRA.Dates.Date is
     (Prepared.Target_Closed_On);

   function Is_Already_Closed (Prepared : Prepared_Closure) return Boolean is
     (Prepared.Already_Closed);

end HRA.Issue_Closure_Preparation;
