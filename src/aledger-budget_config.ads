with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Containers.Indefinite_Vectors;
with ALedger.Config_Support; use ALedger.Config_Support;

package ALedger.Budget_Config is

   type Pacing_Kind is (Daily, Flex);

   type Backing_Pool_Definition is record
      ID             : Unbounded_String;
      Asset_Accounts : String_Vectors.Vector;
   end record;

   type Envelope_Definition is record
      ID           : Unbounded_String;
      Label        : Unbounded_String;
      Pacing       : Pacing_Kind;
      Backing_Pool : Unbounded_String;
   end record;

   package Backing_Pool_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Positive, Element_Type => Backing_Pool_Definition);
   package Envelope_Definition_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Positive, Element_Type => Envelope_Definition);

   type Budget_Policy is record
      Backing_Pools : Backing_Pool_Vectors.Vector;
      Envelopes     : Envelope_Definition_Vectors.Vector;
   end record;

   function Parse_Budget_Policy
     (Text   : String;
      Policy : out Budget_Policy;
      Diag   : out Config_Diagnostic) return Boolean;

end ALedger.Budget_Config;
