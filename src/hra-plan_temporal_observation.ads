with Ada.Containers.Indefinite_Vectors;
with HRA.Dates;
with HRA.Journal_Evidence;
with HRA.Ledger;
with HRA.Plan;
with HRA.Plan_Admission;
with HRA.Plan_Completion;

--  Pure temporal projection over already-admitted Plan and completion facts.
--
--  This owner performs no source admission and no cross-source reference
--  resolution. It answers only what is visible through one inclusive day.
package HRA.Plan_Temporal_Observation is

   type Open_Plan is record
      ID : HRA.Plan.Plan_Id;
      Tx : HRA.Ledger.Transaction;
   end record;

   package Open_Plan_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Open_Plan);

   type Completed_Plan is record
      ID            : HRA.Plan.Plan_Id;
      Plan_Tx       : HRA.Ledger.Transaction;
      Actual_Tx     : HRA.Ledger.Transaction;
      Plan_Source   : HRA.Journal_Evidence.Transaction_Source;
      Actual_Source : HRA.Journal_Evidence.Transaction_Source;
   end record;

   package Completed_Plan_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Completed_Plan);

   type Observation is record
      Observed_Through : HRA.Dates.Date;
      Open_Plans       : Open_Plan_Vectors.Vector;
      Completed_Plans  : Completed_Plan_Vectors.Vector;
   end record;

   function Observe
     (Plans            : HRA.Plan_Admission.Plan_Journal;
      Completions      : HRA.Plan_Completion.Completion_Relations;
      Observed_Through : HRA.Dates.Date) return Observation;

end HRA.Plan_Temporal_Observation;
