with Ada.Containers.Indefinite_Vectors;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA.Actual_Admission;
with HRA.Dates;
with HRA.Plan;
with HRA.Plan_Admission;

--  Cross-source Plan -> Actual completion relation.
--
--  Both endpoint facts are already admitted before this boundary runs. The
--  relation owner never reparses Journal text and never infers completion from
--  dates, amounts, descriptions, or posting shape. It reads only the retained
--  parser-owned plan-id coordinate on an admitted Actual entry, resolves that
--  coordinate against the admitted Plan Journal, and preserves both whole
--  endpoint facts in source order.
package HRA.Plan_Completion is

   type Completion_Relation is record
      Plan_ID : HRA.Plan.Plan_Id;
      Plan    : HRA.Plan_Admission.Plan_Transaction_Entry;
      Actual  : HRA.Actual_Admission.Actual_Transaction_Entry;
   end record;

   type Completion_Relations is private;

   function Empty_Relations return Completion_Relations;
   function Count (Relations : Completion_Relations) return Natural;

   function Relation_At
     (Relations : Completion_Relations;
      Index     : Positive) return Completion_Relation
     with Pre => Index <= Count (Relations);

   function Has_Completion
     (Relations : Completion_Relations;
      Plan_ID   : HRA.Plan.Plan_Id) return Boolean;

   --  Query whether an admitted Plan has a completed Actual visible as of
   --  Observed_Through, and if so return the matching relation without
   --  copying non-matching relations.
   function Has_Visible_Completion
     (Relations        : Completion_Relations;
      Plan_ID          : HRA.Plan.Plan_Id;
      Observed_Through : HRA.Dates.Date;
      Relation         : out Completion_Relation) return Boolean;

   type Admission_Status is
     (Success,
      Actual_Admission_Invariant_Violation,
      Unknown_Completion_Plan,
      Multiple_Completion_Actuals);

   type Admission_Diagnostic is record
      Status      : Admission_Status := Success;
      Line_Number : Natural := 0;
      Plan_Id     : Unbounded_String;
      Message     : Unbounded_String;
   end record;

   function Admit
     (Plans   : HRA.Plan_Admission.Plan_Journal;
      Actuals : HRA.Actual_Admission.Actual_Observation;
      Result  : out Completion_Relations;
      Diag    : out Admission_Diagnostic) return Boolean;

private

   package Completion_Relation_Vectors is new
     Ada.Containers.Indefinite_Vectors
       (Index_Type   => Positive,
        Element_Type => Completion_Relation);

   type Completion_Relations is record
      In_Order : Completion_Relation_Vectors.Vector;
   end record;

   function Count (Relations : Completion_Relations) return Natural is
     (Natural (Relations.In_Order.Length));

   function Relation_At
     (Relations : Completion_Relations;
      Index     : Positive) return Completion_Relation is
     (Relations.In_Order.Element (Index));

end HRA.Plan_Completion;
