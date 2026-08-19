with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Containers.Indefinite_Ordered_Maps;

package HRA.Money is

   --  ========================================================================
   --  Commodity: Identifier such as "JPY", "USD", "BTC"
   --  ========================================================================
   type Commodity is private;

   type Commodity_Status is
     (Success,
      Empty_Commodity_Code,
      Commodity_Contains_Whitespace);

   function Create_Commodity
     (Code   : String;
      Symbol : out Commodity;
      Status : out Commodity_Status) return Boolean;

   function Make_Commodity (Code : String) return Commodity
     with Pre => Code'Length > 0;
   --  Raises Constraint_Error if invalid.

   function Code (C : Commodity) return String;
   function To_Unbounded (C : Commodity) return Unbounded_String;

   function "=" (Left, Right : Commodity) return Boolean;
   function "<" (Left, Right : Commodity) return Boolean;

   --  ========================================================================
   --  Quantity: Exact decimal quantity (up to 8 decimal places, 18 digits)
   --  ========================================================================
   type Quantity is delta 0.00000001 digits 18;

   Zero_Quantity : constant Quantity := 0.0;

   function Parse_Quantity (Input : String; Value : out Quantity) return Boolean;
   function Render_Quantity (Q : Quantity) return String;
   function Is_Zero (Q : Quantity) return Boolean
     with Post => Is_Zero'Result = (Q = Zero_Quantity);

   --  ========================================================================
   --  Amount: Quantity tagged with a single Commodity
   --  ========================================================================
   type Amount is record
      Comm : Commodity;
      Val  : Quantity;
   end record;

   function Make_Amount (C : Commodity; Q : Quantity) return Amount
     with Post => Make_Amount'Result.Val = Q;

   function Negate_Amount (A : Amount) return Amount
     with Post => Negate_Amount'Result.Val = -A.Val;

   --  ========================================================================
   --  Balance: Canonical Multi-Commodity Balance (zero entries purged)
   --  ========================================================================
   type Balance is private;

   function Empty_Balance return Balance;
   function Singleton_Balance (A : Amount) return Balance;

   function Add_Balance (Left, Right : Balance) return Balance;
   function Subtract_Balance (Left, Right : Balance) return Balance;
   function Negate_Balance (B : Balance) return Balance;

   function Lookup_Balance (B : Balance; C : Commodity) return Quantity;
   function Is_Zero_Balance (B : Balance) return Boolean;

   type Balance_Entry is record
      Comm : Commodity;
      Val  : Quantity;
   end record;

   type Balance_Entry_Array is array (Positive range <>) of Balance_Entry;

   function Entries (B : Balance) return Balance_Entry_Array;

private

   type Commodity is record
      Code_Text : Unbounded_String;
   end record;

   package Commodity_Maps is new Ada.Containers.Indefinite_Ordered_Maps
     (Key_Type     => String,
      Element_Type  => Quantity);

   type Balance is record
      Map : Commodity_Maps.Map;
   end record;

end HRA.Money;
