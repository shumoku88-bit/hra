with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with ALedger.Ledger;

package ALedger.Journal is

   --  ========================================================================
   --  Journal Document Parsing and Validation
   --  ========================================================================

   type Parse_Status is
     (Success,
      Parse_Error,
      Validation_Error);

   type Parse_Diagnostic is record
      File_Name   : Unbounded_String;
      Line_Number : Natural := 0;
      Raw_Text    : Unbounded_String;
      Message     : Unbounded_String;
   end record;

   function Format_Diagnostic (Diag : Parse_Diagnostic) return String;

   function Parse_Journal_Text
     (Input     : String;
      File_Name : String;
      L         : out Ledger.Ledger;
      Diag      : out Parse_Diagnostic) return Boolean;

   function Parse_Journal_Text
     (Input     : String;
      L         : out Ledger.Ledger;
      Error_Msg : out Unbounded_String) return Boolean;

end ALedger.Journal;
