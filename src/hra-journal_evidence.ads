with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Containers.Indefinite_Vectors;
with HRA.Ledger;

--  Physical source evidence owned by Journal parsing.
--
--  The data model lives here so domain consumers can retain source coordinates.
--  Extract is only a projection/validation boundary: it delegates all lexical
--  recognition to HRA.Journal.Document and owns no Journal grammar of its own.
package HRA.Journal_Evidence is

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

   function Extract
     (Input    : String;
      L        : HRA.Ledger.Ledger;
      Evidence : out Journal_Evidence;
      Diag     : out Evidence_Diagnostic) return Boolean;

   function Extract
     (Input       : String;
      Source_Path : String;
      L           : HRA.Ledger.Ledger;
      Evidence    : out Journal_Evidence;
      Diag        : out Evidence_Diagnostic) return Boolean;

end HRA.Journal_Evidence;
