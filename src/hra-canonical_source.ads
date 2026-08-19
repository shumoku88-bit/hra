with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

package HRA.Canonical_Source is

   --  The canonical Household topology is fixed and shared with h-kernel.
   --  Basenames are resolved only by this package.
   type Source_Name is
     (Accounts_Source,
      Actual_Source,
      Plan_Source,
      Budget_Journal_Source,
      Budget_Config_Source,
      Household_Config_Source,
      Report_Config_Source,
      Issues_Source);

   type Source_Paths is record
      Accounts_Journal : Unbounded_String;
      Actual_Journal   : Unbounded_String;
      Plan_Journal     : Unbounded_String;
      Budget_Journal   : Unbounded_String;
      Budget_TOML      : Unbounded_String;
      Household_TOML   : Unbounded_String;
      Report_TOML      : Unbounded_String;
      Issues_TSV       : Unbounded_String;
   end record;

   type Source_Text_Array is array (Source_Name) of Unbounded_String;

   type Source_Observation is record
      Root_Path : Unbounded_String;
      Paths     : Source_Paths;
      Texts     : Source_Text_Array;
   end record;

   function Basename (Source : Source_Name) return String;

   function Resolve_Source_Paths (Root_Dir : String) return Source_Paths
     with Pre => Root_Dir'Length > 0;

   function Path_For
     (Paths  : Source_Paths;
      Source : Source_Name) return String;

   function Text_For
     (Observation : Source_Observation;
      Source      : Source_Name) return String;

   --  Observe all eight roots as exact bytes.  Missing or unreadable sources
   --  fail the complete observation; no fallback topology is attempted.
   function Observe_Canonical_Sources
     (Root_Dir    : String;
      Observation : out Source_Observation;
      Error_Msg   : out Unbounded_String) return Boolean
     with Pre => Root_Dir'Length > 0;

end HRA.Canonical_Source;
