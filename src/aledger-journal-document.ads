with Ada.Containers.Vectors;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

--  Parsed source-level structure owned by Journal syntax.
--  This child package does not perform filesystem I/O or graph traversal.
package ALedger.Journal.Document is

   type Include_Directive is record
      Line_Number : Positive;
      Path        : Unbounded_String;
   end record;

   package Include_Directive_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Include_Directive);

   type Parsed_Document is record
      Includes : Include_Directive_Vectors.Vector;
   end record;

   function Parse
     (Input     : String;
      File_Name : String;
      Result    : out Parsed_Document;
      Diag      : out ALedger.Journal.Parse_Diagnostic) return Boolean;

end ALedger.Journal.Document;
