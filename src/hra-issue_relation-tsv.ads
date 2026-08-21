with Ada.Containers.Indefinite_Vectors;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

--  Source-local admission for the explicit Issue relation sidecar.
--
--  This child owns only the six-column TSV syntax and source-order relation
--  history. It does not resolve the sidecar path, read the filesystem, validate
--  Issue/Actual existence, mutate Issue lifecycle, or publish source bytes.
package HRA.Issue_Relation.TSV is

   type Relation_History is private;

   function Count (History : Relation_History) return Natural;

   function Element
     (History : Relation_History;
      Index   : Positive) return HRA.Issue_Relation.Relation_Event
     with Pre => Index <= Count (History);

   type Admission_Status is
     (Success,
      Invalid_Header,
      Malformed_Column_Count,
      Invalid_Relation_Event_Id,
      Duplicate_Relation_Event_Id,
      Invalid_Recorded_Date,
      Invalid_Issue_Id,
      Unknown_Relation_Kind,
      Invalid_Actual_Id,
      Invalid_Details);

   type Admission_Diagnostic is record
      Status            : Admission_Status := Success;
      Line_Number       : Natural := 0;
      Relation_Event_Id : Unbounded_String;
      Message           : Unbounded_String;
   end record;

   --  Blank and comment-only source means that no relation history exists yet.
   --  Once data is present, the header and all six columns are exact. Reference
   --  existence remains the parent domain owner's responsibility.
   function Admit
     (TSV_Text : String;
      History  : out Relation_History;
      Diag     : out Admission_Diagnostic) return Boolean;

private

   package Relation_Event_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => HRA.Issue_Relation.Relation_Event);

   type Relation_History is record
      Items : Relation_Event_Vectors.Vector;
   end record;

end HRA.Issue_Relation.TSV;
