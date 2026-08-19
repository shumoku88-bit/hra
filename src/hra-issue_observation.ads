with Ada.Containers.Indefinite_Vectors;
with HRA.Dates;
with HRA.Issues;

--  Pure temporal projection for canonical Issue facts over an explicit
--  observation date. This package resolves as-of lifecycle state and
--  due-date queries without modifying the admitted issue inventory.
package HRA.Issue_Observation is

   type As_Of_Status is
     (Open,
      Resolved,
      Dropped,
      Closure_Undetermined);

   type Observed_Issue is record
      Issue        : HRA.Issues.Household_Issue;
      Status_As_Of : As_Of_Status;
   end record;

   package Observed_Issue_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Observed_Issue);

   type Observation is record
      Observed_Through : HRA.Dates.Date;
      All_Observed     : Observed_Issue_Vectors.Vector;
      Open_Issues      : Observed_Issue_Vectors.Vector;
      Resolved_Issues  : Observed_Issue_Vectors.Vector;
      Dropped_Issues   : Observed_Issue_Vectors.Vector;
      Undetermined     : Observed_Issue_Vectors.Vector;
   end record;

   --  Project admitted issue inventory as of Observed_Through.
   --  Issues recorded strictly after Observed_Through are not visible.
   function Observe
     (Inventory        : HRA.Issues.Issues_Inventory;
      Observed_Through : HRA.Dates.Date) return Observation;

   --  Select issues that are Open as-of Observed_Through and have
   --  Due = Due_On (Target_Day).
   function Due_Issues_On
     (Obs        : Observation;
      Target_Day : HRA.Dates.Date) return Observed_Issue_Vectors.Vector;

   --  Return True if there is at least one visible issue whose closure is
   --  undetermined as-of Observed_Through and whose Due is Due_On (Target_Day).
   function Has_Undetermined_Due_On
     (Obs        : Observation;
      Target_Day : HRA.Dates.Date) return Boolean;

end HRA.Issue_Observation;
