with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Containers.Indefinite_Ordered_Maps;
with ALedger.Config_Support; use ALedger.Config_Support;

package ALedger.Envelope is

   --  ========================================================================
   --  Envelope Identity
   --
   --  An Envelope_Id identifies a stable household spending purpose such as
   --  "食費" or "タバコ".  It is NOT an Account: the string "食費" as an
   --  Envelope identity has no relation to the Account name "expenses:食費"
   --  or the Budget allocation Account "budget:食費".
   --
   --  Construction is controlled.  Use Create_Envelope_Id for validated
   --  admission or Admit_Registry to build the canonical identity universe.
   --  ========================================================================

   type Envelope_Id is private;

   type Envelope_Id_Status is
     (Success,
      Empty_Identity,
      Leading_Or_Trailing_Whitespace,
      Identity_Contains_Control);

   function Create_Envelope_Id
     (Name   : String;
      Id     : out Envelope_Id;
      Status : out Envelope_Id_Status) return Boolean
     with Post =>
       (if Create_Envelope_Id'Result
        then Status = Success and then Image (Id) = Name);

   --  Convenience constructor: raises Constraint_Error if Name is invalid.
   --  Use only when validity is already established by source admission.
   function Make_Envelope_Id (Name : String) return Envelope_Id
     with Pre => Name'Length > 0;

   function Image (Id : Envelope_Id) return String
     with Post => Image'Result'Length > 0;

   function "=" (Left, Right : Envelope_Id) return Boolean;
   function "<" (Left, Right : Envelope_Id) return Boolean;

   --  ========================================================================
   --  Envelope Registry
   --
   --  The admitted universe of stable Envelope identities.  Constructed once
   --  during Household admission from envelope-history.identities.  After
   --  successful admission the registry is immutable: no API exists to add,
   --  remove, or rename entries.
   --
   --  Changing today's Envelope set must not erase historical identity.
   --  A retired Envelope remains in the registry if it was ever admitted.
   --  ========================================================================

   type Envelope_Registry is private;

   function Empty_Registry return Envelope_Registry
     with Post => Length (Empty_Registry'Result) = 0;

   function Admit_Registry
     (Identities : String_Vectors.Vector;
      Registry   : out Envelope_Registry;
      Diag       : out Config_Diagnostic) return Boolean
     with Post =>
       (if Admit_Registry'Result
        then Length (Registry) = Natural (Identities.Length));

   function Contains (R : Envelope_Registry; Name : String) return Boolean;

   function Lookup
     (R    : Envelope_Registry;
      Name : String;
      Id   : out Envelope_Id) return Boolean
     with Post =>
       (if Lookup'Result
        then Contains (R, Name) and then Image (Id) = Name);

   function Length (R : Envelope_Registry) return Natural;

   --  Return all admitted identities in canonical sort order.
   type Envelope_Id_Array is array (Positive range <>) of Envelope_Id;

   function All_Ids (R : Envelope_Registry) return Envelope_Id_Array
     with Post => All_Ids'Result'Length = Length (R);

private

   type Envelope_Id is record
      Name : Unbounded_String;
   end record;

   package Envelope_Name_Maps is new Ada.Containers.Indefinite_Ordered_Maps
     (Key_Type     => String,
      Element_Type => Envelope_Id);

   type Envelope_Registry is record
      By_Name : Envelope_Name_Maps.Map;
   end record;

end ALedger.Envelope;
