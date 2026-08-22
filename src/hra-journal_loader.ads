with Ada.Containers.Vectors;
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
--
--  A successful observation also retains the exact bytes used for every
--  physical source in that same admission. The supplied root is distinguished
--  from included filesystem files so later publication can fence the graph
--  without reconstructing which bytes were actually admitted.
package HRA.Journal_Loader is

   type Source_Kind is (Supplied_Root, Included_File);

   type Source_Observation is record
      Kind : Source_Kind := Supplied_Root;
      Path : Unbounded_String;
      Text : Unbounded_String;
   end record;

   package Source_Observation_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Source_Observation);

   type Journal_Observation is record
      Value    : HRA.Ledger.Ledger;
      Evidence : HRA.Journal_Evidence.Journal_Evidence;
      Sources  : Source_Observation_Vectors.Vector;
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
