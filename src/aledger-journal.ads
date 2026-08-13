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

   function Parse_Journal_Text
     (Input     : String;
      L         : out Ledger.Ledger;
      Error_Msg : out Unbounded_String) return Boolean;

end ALedger.Journal;
