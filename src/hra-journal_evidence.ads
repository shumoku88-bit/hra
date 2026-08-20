with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Containers.Indefinite_Vectors;

--  Physical source evidence owned by Journal parsing.
--
--  This package intentionally contains data types only. It does not rescan or
--  reinterpret Journal text. HRA.Journal.Document produces these coordinates
--  from the same source-structure observation that owns include directives,
--  and HRA.Journal_Loader pairs them with admitted semantic Transactions.
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

end HRA.Journal_Evidence;
