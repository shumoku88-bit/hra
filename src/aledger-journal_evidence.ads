with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Containers.Indefinite_Vectors;
with ALedger.Ledger;

package ALedger.Journal_Evidence is

   type Metadata_Entry is record
      Key         : Unbounded_String;
      Value       : Unbounded_String;
      Line_Number : Positive;
   end record;

   package Metadata_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Metadata_Entry);

   type Transaction_Source is record
      Source_Path : Unbounded_String;
      Header_Line : Positive;
      Date_Text   : Unbounded_String;
      Description : Unbounded_String;
      Metadata    : Metadata_Vectors.Vector;
   end record;

   package Transaction_Source_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Transaction_Source);

   type Journal_Evidence is record
      Transactions : Transaction_Source_Vectors.Vector;
   end record;

   type Evidence_Diagnostic is record
      Line_Number : Natural := 0;
      Message     : Unbounded_String;
   end record;

   --  Extract transaction-owned metadata from the exact same source bytes that
   --  produced L. This projection does not parse postings or amounts again.
   --  It verifies transaction count and header alignment against the admitted
   --  Ledger so metadata cannot silently drift onto a different transaction.
   function Extract
     (Input    : String;
      L        : ALedger.Ledger.Ledger;
      Evidence : out Journal_Evidence;
      Diag     : out Evidence_Diagnostic) return Boolean;

   --  Source-aware form used by Journal graph admission. Every transaction
   --  retains the physical document path and line that owned its metadata.
   function Extract
     (Input       : String;
      Source_Path : String;
      L           : ALedger.Ledger.Ledger;
      Evidence    : out Journal_Evidence;
      Diag        : out Evidence_Diagnostic) return Boolean;

end ALedger.Journal_Evidence;
