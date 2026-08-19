with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA.Ledger;
with HRA.Journal_Evidence;

--  Journal graph filesystem boundary.
--
--  The caller supplies the already-observed root bytes. Only included
--  documents are read here, relative to the document that names them.
--  Includes are expanded in source order before the complete Journal is
--  admitted. Cycles, duplicate loads, unreadable includes, and source-local
--  parse failures fail closed.
package HRA.Journal_Loader is

   type Journal_Observation is record
      Value    : HRA.Ledger.Ledger;
      Evidence : HRA.Journal_Evidence.Journal_Evidence;
   end record;

   function Load_From_Root_Source
     (Root_Path   : String;
      Root_Text   : String;
      Observation : out Journal_Observation;
      Error_Msg   : out Unbounded_String) return Boolean
     with Pre => Root_Path'Length > 0;

   --  Compatibility projection for callers that need only the resolved Ledger.
   function Load_From_Root_Source
     (Root_Path : String;
      Root_Text : String;
      L         : out HRA.Ledger.Ledger;
      Error_Msg : out Unbounded_String) return Boolean
     with Pre => Root_Path'Length > 0;

end HRA.Journal_Loader;
