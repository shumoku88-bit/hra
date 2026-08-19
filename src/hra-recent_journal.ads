with Ada.Containers.Indefinite_Vectors;
with HRA.Dates;
with HRA.Journal_Evidence;
with HRA.Ledger;

--  Semantic Recent Journal result over one already-admitted Actual observation.
--  Selection is bounded by an explicit through date and source order. The
--  result retains the physical Journal evidence aligned with every selected
--  Transaction; renderers do not reread or reparse source text.
package HRA.Recent_Journal is

   type Recent_Entry is record
      Value  : HRA.Ledger.Transaction;
      Source : HRA.Journal_Evidence.Transaction_Source;
   end record;

   package Entry_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Recent_Entry);

   type Observation is record
      Through_Date : HRA.Dates.Date;
      Requested    : Positive := 5;
      Entries      : Entry_Vectors.Vector;
   end record;

   type Observe_Status is
     (Success,
      Evidence_Count_Mismatch,
      Evidence_Alignment_Mismatch);

   function Observe
     (Actual_Ledger   : HRA.Ledger.Ledger;
      Actual_Evidence : HRA.Journal_Evidence.Journal_Evidence;
      Through_Date    : HRA.Dates.Date;
      Count           : Positive;
      Result          : out Observation;
      Status          : out Observe_Status) return Boolean;

end HRA.Recent_Journal;
