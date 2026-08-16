with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with ALedger.Ledger;

--  Journal graph filesystem boundary.
--
--  The caller supplies the already-observed root bytes.  Only included
--  documents are read here, relative to the document that names them.
--  Includes are expanded in source order before the complete Journal is
--  admitted.  Cycles, duplicate loads, unreadable includes, and source-local
--  parse failures fail closed.
package ALedger.Journal_Loader is

   function Load_From_Root_Source
     (Root_Path : String;
      Root_Text : String;
      L         : out ALedger.Ledger.Ledger;
      Error_Msg : out Unbounded_String) return Boolean
     with Pre => Root_Path'Length > 0;

end ALedger.Journal_Loader;
