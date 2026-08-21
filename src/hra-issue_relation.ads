with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA.Actual_Admission;
with HRA.Dates;
with HRA.Issues;

--  Explicit historical relations from one Household Issue to another admitted
--  household fact.
--
--  A relation is append-only evidence of a household decision. It does not
--  mutate Issue lifecycle by itself. In particular, Realized_As does not imply
--  that the Issue is Resolved, and reference admission does not require the
--  Issue to be Open.
--
--  This package owns domain meaning only. TSV syntax, sidecar path resolution,
--  source publication, and coordinated Issue/Actual mutation belong to later
--  source and application boundaries.
package HRA.Issue_Relation is

   --  Durable identity for one historical relation occurrence.
   type Relation_Event_Id is private;

   type Relation_Event_Id_Status is
     (Success,
      Empty_Relation_Event_Id,
      Relation_Event_Id_Contains_Whitespace,
      Relation_Event_Id_Contains_Control_Character);

   function Create_Relation_Event_Id
     (Value  : String;
      ID     : out Relation_Event_Id;
      Status : out Relation_Event_Id_Status) return Boolean;

   function Text (ID : Relation_Event_Id) return String;
   function "=" (Left, Right : Relation_Event_Id) return Boolean;

   --  Start with the first relation meaning needed by HRA. Additional meanings
   --  remain distinct discriminants rather than being flattened into a generic
   --  graph edge or one untyped target coordinate.
   type Relation_Kind is (Realized_As);

   type Relation_Event (Meaning : Relation_Kind := Realized_As) is private;

   type Create_Status is
     (Create_Success,
      Details_Have_Surrounding_Whitespace,
      Details_Contain_Control_Character);

   --  Record that one Issue was realized as one exact source-durable Actual.
   --  Recorded_On is the relation event coordinate. It is intentionally
   --  independent from the Actual event date and the Issue closure date.
   function Create_Realized_As
     (Event_ID    : Relation_Event_Id;
      Recorded_On : HRA.Dates.Date;
      Issue_ID    : HRA.Issues.Issue_Id;
      Actual_ID   : HRA.Actual_Admission.Actual_Id;
      Details     : String;
      Event       : out Relation_Event;
      Status      : out Create_Status) return Boolean;

   function Kind (Event : Relation_Event) return Relation_Kind;
   function Event_Id (Event : Relation_Event) return Relation_Event_Id;
   function Recorded_On (Event : Relation_Event) return HRA.Dates.Date;
   function Issue_Id (Event : Relation_Event) return HRA.Issues.Issue_Id;
   function Actual_Id (Event : Relation_Event) return HRA.Actual_Admission.Actual_Id;
   function Details (Event : Relation_Event) return String;

   --  Cross-source reference admission checks existence only. It deliberately
   --  does not inspect Issue status, compare temporal coordinates, infer an
   --  Actual by resemblance, or alter either endpoint.
   type Reference_Status is
     (Reference_Success,
      Unknown_Issue,
      Unknown_Source_Durable_Actual);

   type Reference_Diagnostic is record
      Status  : Reference_Status := Reference_Success;
      Message : Unbounded_String;
   end record;

   function Admit_References
     (Event   : Relation_Event;
      Issues  : HRA.Issues.Issues_Inventory;
      Actuals : HRA.Actual_Admission.Actual_Observation;
      Diag    : out Reference_Diagnostic) return Boolean;

private

   type Relation_Event_Id is record
      ID_Text : Unbounded_String;
   end record;

   type Relation_Event (Meaning : Relation_Kind := Realized_As) is record
      Event_Identity : Relation_Event_Id;
      Event_Date     : HRA.Dates.Date;
      Source_Issue   : HRA.Issues.Issue_Id;
      Event_Details  : Unbounded_String;
      case Meaning is
         when Realized_As =>
            Target_Actual : HRA.Actual_Admission.Actual_Id;
      end case;
   end record;

end HRA.Issue_Relation;
