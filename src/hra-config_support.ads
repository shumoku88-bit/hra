with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Containers.Indefinite_Vectors;
with TOML;

package HRA.Config_Support is

   package String_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Positive, Element_Type => String);

   type Config_Diagnostic is record
      Source_Name : Unbounded_String;
      Path        : Unbounded_String;
      Message     : Unbounded_String;
      Line        : Natural := 0;
      Column      : Natural := 0;
   end record;

   function Format_Diagnostic (Diag : Config_Diagnostic) return String;

   procedure Set_Error
     (Diag        : out Config_Diagnostic;
      Source_Name : String;
      Path        : String;
      Message     : String;
      Value       : TOML.TOML_Value := TOML.No_TOML_Value);

   function Parse_Root
     (Text        : String;
      Source_Name : String;
      Root        : out TOML.TOML_Value;
      Diag        : out Config_Diagnostic) return Boolean;

   --  Allowed is a vertical-bar-separated exact key set.
   function Check_Keys
     (Table       : TOML.TOML_Value;
      Allowed     : String;
      Source_Name : String;
      Path        : String;
      Diag        : out Config_Diagnostic) return Boolean;

   function Require
     (Table       : TOML.TOML_Value;
      Key         : String;
      Kind        : TOML.Any_Value_Kind;
      Source_Name : String;
      Path        : String;
      Value       : out TOML.TOML_Value;
      Diag        : out Config_Diagnostic) return Boolean;

   function Optional
     (Table       : TOML.TOML_Value;
      Key         : String;
      Kind        : TOML.Any_Value_Kind;
      Source_Name : String;
      Path        : String;
      Value       : out TOML.TOML_Value;
      Present     : out Boolean;
      Diag        : out Config_Diagnostic) return Boolean;

   function Read_String_Array
     (Value       : TOML.TOML_Value;
      Source_Name : String;
      Path        : String;
      Items       : out String_Vectors.Vector;
      Diag        : out Config_Diagnostic) return Boolean;

end HRA.Config_Support;
