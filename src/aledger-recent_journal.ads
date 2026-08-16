with Ada.Containers.Indefinite_Vectors;
with ALedger.Dates;
with ALedger.Journal_Evidence;
with ALedger.Ledger;

--  Semantic Recent Journal result over one already-admitted Actual observation.
--  Selection is bounded by an explicit through date and source order. The
--  result retains the physical Journal evidence aligned with every selected
--  Transaction; renderers do not reread or reparse source text.
package ALedger.Recent_Journal is

   type Recent_Entry is record
      Value  : ALedger.Ledger.Transaction;
      Source : ALedger.Journal_Evidence.Transaction_Source;
   end record;

   package Entry_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Recent_Entry);

   type Observation is record
      Through_Date : ALedger.Dates.Date;
      Requested    : Positive := 5;
      Entries      : Entry_Vectors.Vector;
   end record;

   type Observe_Status is
     (Success,
      Evidence_Count_Mismatch,
      Evidence_Alignment_Mismatch);

   function Observe
     (Actual_Ledger   : ALedger.Ledger.Ledger;
      Actual_Evidence : ALedger.Journal_Evidence.Journal_Evidence;
      Through_Date    : ALedger.Dates.Date;
      Count           : Positive;
      Result          : out Observation;
      Status          : out Observe_Status) return Boolean;

end ALedger.Recent_Journal;
