with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA.Actual_Admission;
with HRA.Issue_Relation.TSV;
with HRA.Issues;

--  Cross-source admission for an already observed Issue relation source.
--
--  TSV syntax is admitted first by HRA.Issue_Relation.TSV. This child then
--  establishes that every typed relation points into the admitted Issue and
--  source-durable Actual identity universes. Filesystem observation, sidecar
--  path resolution, Issue lifecycle mutation, and publication remain outside.
package HRA.Issue_Relation.Admission is

   type Admitted_History is private;

   function Count (History : Admitted_History) return Natural;

   function Element
     (History : Admitted_History;
      Index   : Positive) return HRA.Issue_Relation.Relation_Event
     with Pre => Index <= Count (History);

   type Admission_Status is
     (Success,
      Source_Error,
      Reference_Error);

   type Admission_Diagnostic (Status : Admission_Status := Success) is record
      case Status is
         when Success =>
            null;
         when Source_Error =>
            Source : HRA.Issue_Relation.TSV.Admission_Diagnostic;
         when Reference_Error =>
            Relation_Index    : Positive;
            Relation_Event_Id : Unbounded_String;
            Reference         : HRA.Issue_Relation.Reference_Diagnostic;
      end case;
   end record;

   --  Admit one complete relation source against already admitted endpoint
   --  owners. Validation follows relation source order and fails closed at the
   --  first dangling reference. No relation is inferred from endpoint shape.
   function Admit
     (TSV_Text : String;
      Issues   : HRA.Issues.Issues_Inventory;
      Actuals  : HRA.Actual_Admission.Actual_Observation;
      History  : out Admitted_History;
      Diag     : out Admission_Diagnostic) return Boolean;

private

   type Admitted_History is record
      Source_History : HRA.Issue_Relation.TSV.Relation_History;
   end record;

end HRA.Issue_Relation.Admission;
