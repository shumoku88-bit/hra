with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Containers.Indefinite_Ordered_Maps;
with ALedger.Money;          use ALedger.Money;

package ALedger.Account is

   --  ========================================================================
   --  Account Category / Meaning for Reports
   --  ========================================================================
   type Account_Type is
     (Asset,
      Liability,
      Equity,
      Income,
      Expense,
      Budget);

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

   function Make_Account (Name : String) return Account;
   --  Raises Constraint_Error if invalid.

   function Name (Acc : Account) return String;
   function To_Unbounded (Acc : Account) return Unbounded_String;

   function "=" (Left, Right : Account) return Boolean;
   function "<" (Left, Right : Account) return Boolean;

   --  ========================================================================
   --  Account Declaration & Metadata
   --  ========================================================================
   type Account_Declaration is record
      Acc                    : Account;
      Acc_Type               : Account_Type;
      Has_Default_Commodity  : Boolean := False;
      Default_Commodity      : Commodity;
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

   procedure Register_Or_Update_Account
     (Reg  : in out Account_Registry;
      Decl : Account_Declaration);

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

private

   type Account is record
      Name_Text : Unbounded_String;
   end record;

   package Registry_Maps is new Ada.Containers.Indefinite_Ordered_Maps
     (Key_Type     => String,
      Element_Type  => Account_Declaration);

   type Account_Registry is record
      Map : Registry_Maps.Map;
   end record;

end ALedger.Account;
