with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Containers.Indefinite_Ordered_Maps;
with Ada.Containers.Vectors;
with HRA.Money;          use HRA.Money;

package HRA.Account is

   --  ========================================================================
   --  Account Category / Meaning for Reports
   --  ========================================================================
   type Account_Type is
     (Asset,
      Liability,
      Equity,
      Income,
      Expense);

   function Account_Type_Image (Category : Account_Type) return String;

   --  ========================================================================
   --  Account Identity (e.g. "assets:bank:checking")
   --  ========================================================================
   type Account is private;

   type Account_Status is
     (Success,
      Empty_Account_Name,
      Account_Has_Surrounding_Whitespace,
      Account_Contains_Control_Character);

   function Create_Account
     (Name    : String;
      Acc     : out Account;
      Status  : out Account_Status) return Boolean;

   function Make_Account (Name : String) return Account
     with Pre => Name'Length > 0;
   --  Raises Constraint_Error if invalid.

   function Name (Acc : Account) return String;
   function To_Unbounded (Acc : Account) return Unbounded_String;

   function "=" (Left, Right : Account) return Boolean;
   function "<" (Left, Right : Account) return Boolean;

   --  ========================================================================
   --  Account Declaration & Metadata
   --  ========================================================================
   --  Ada variant data keeps the absent-default case genuinely absent instead
   --  of carrying a Boolean flag beside an otherwise meaningless Commodity.
   type Default_Commodity_Option (Has_Value : Boolean := False) is record
      case Has_Value is
         when True =>
            Value : Commodity;
         when False =>
            null;
      end case;
   end record;

   function No_Default_Commodity return Default_Commodity_Option;
   function Make_Default_Commodity
     (C : Commodity) return Default_Commodity_Option;

   type Account_Declaration is record
      Acc               : Account;
      Acc_Type          : Account_Type;
      Default_Commodity : Default_Commodity_Option;
   end record;

   function Declare_Account
     (Acc      : Account;
      Acc_Type : Account_Type) return Account_Declaration;

   function Declare_Account_With_Default_Commodity
     (Acc       : Account;
      Acc_Type  : Account_Type;
      Default_C : Commodity) return Account_Declaration;

   --  ========================================================================
   --  Account Registry
   --
   --  Declarations owns admitted source order. Name lookup is an index into
   --  that sequence; the ordered-map key order is never a domain order.
   --  ========================================================================
   type Account_Registry is private;

   type Registry_Status is
     (Success,
      Duplicate_Account_Declaration);

   function Empty_Registry return Account_Registry;

   function Register_Account
     (Reg    : in out Account_Registry;
      Decl   : Account_Declaration;
      Status : out Registry_Status) return Boolean;

   function Lookup_Declaration
     (Reg  : Account_Registry;
      Acc  : Account;
      Decl : out Account_Declaration) return Boolean;

   function Account_Type_For
     (Reg      : Account_Registry;
      Acc      : Account;
      Category : out Account_Type) return Boolean;

   type Declaration_Array is array (Positive range <>) of Account_Declaration;

   function Declarations (Reg : Account_Registry) return Declaration_Array;

   function Same_Declaration (Left, Right : Account_Declaration) return Boolean;
   function Same_Registry (Left, Right : Account_Registry) return Boolean;

private

   type Account is record
      Name_Text : Unbounded_String;
   end record;

   package Declaration_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Account_Declaration);

   package Registry_Index_Maps is new Ada.Containers.Indefinite_Ordered_Maps
     (Key_Type     => String,
      Element_Type => Positive);

   type Account_Registry is record
      In_Order : Declaration_Vectors.Vector;
      By_Name  : Registry_Index_Maps.Map;
   end record;

end HRA.Account;
