with Ada.Containers.Indefinite_Vectors;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA.Dates;
with HRA.Money;         use HRA.Money;

package HRA.Issues is

   --  ========================================================================
   --  Issue Identity
   --  ========================================================================

   type Issue_Id is private;

   type Issue_Id_Status is
     (Success,
      Empty_Issue_Id,
      Issue_Id_Contains_Whitespace,
      Issue_Id_Contains_Control_Character);

   function Create_Issue_Id
     (Value  : String;
      ID     : out Issue_Id;
      Status : out Issue_Id_Status) return Boolean;

   function Make_Issue_Id (Value : String) return Issue_Id;

   function Text (ID : Issue_Id) return String;
   function To_Unbounded (ID : Issue_Id) return Unbounded_String;
   function "=" (Left, Right : Issue_Id) return Boolean;
   function "<" (Left, Right : Issue_Id) return Boolean;

   --  ========================================================================
   --  Issue Status & Temporal Coordinates
   --  ========================================================================

   type Issue_Status is (Open, Resolved, Dropped);

   type Issue_Due_Kind is (Due_On, No_Due_Date, Due_Undetermined);

   type Issue_Due (Kind : Issue_Due_Kind := No_Due_Date) is record
      case Kind is
         when Due_On =>
            Due_Date : HRA.Dates.Date;
         when No_Due_Date | Due_Undetermined =>
            null;
      end case;
   end record;

   function Make_Due_On (D : HRA.Dates.Date) return Issue_Due;
   function No_Due return Issue_Due;
   function Undetermined_Due return Issue_Due;

   type Issue_Closed_Kind is (Closed_On, Not_Closed, Closed_Undetermined);

   type Issue_Closed (Kind : Issue_Closed_Kind := Not_Closed) is record
      case Kind is
         when Closed_On =>
            Closed_Date : HRA.Dates.Date;
         when Not_Closed | Closed_Undetermined =>
            null;
      end case;
   end record;

   function Make_Closed_On (D : HRA.Dates.Date) return Issue_Closed;
   function Not_Closed return Issue_Closed;
   function Undetermined_Closed return Issue_Closed;

   --  ========================================================================
   --  Optional Amount
   --  ========================================================================

   type Optional_Amount (Has_Amount : Boolean := False) is record
      case Has_Amount is
         when True =>
            Value : Amount;
         when False =>
            null;
      end case;
   end record;

   function No_Amount return Optional_Amount;
   function Make_Optional_Amount (A : Amount) return Optional_Amount;

   --  ========================================================================
   --  Household Issue Record & Inventory
   --  ========================================================================

   type Household_Issue is record
      ID          : Issue_Id;
      Status      : Issue_Status;
      Recorded_On : HRA.Dates.Date;
      Due         : Issue_Due;
      Closed      : Issue_Closed;
      Category    : Unbounded_String;
      Title       : Unbounded_String;
      Amt         : Optional_Amount;
      Details     : Unbounded_String;
   end record;

   type Issues_Inventory is private;

   function Empty_Inventory return Issues_Inventory;
   function Count (Inv : Issues_Inventory) return Natural;
   function Item_Count (Inv : Issues_Inventory) return Natural;
   function Is_Empty (Inv : Issues_Inventory) return Boolean;
   function Element
     (Inv   : Issues_Inventory;
      Index : Positive) return Household_Issue
     with Pre => Index in 1 .. Count (Inv);

   type Issue_Array is array (Positive range <>) of Household_Issue;

   function All_Issues (Inv : Issues_Inventory) return Issue_Array;
   function Open_Issues (Inv : Issues_Inventory) return Issues_Inventory;

   procedure Append
     (Inv   : in out Issues_Inventory;
      Issue : Household_Issue);

   procedure Clear (Inv : in out Issues_Inventory);

   --  ========================================================================
   --  Admission Status & Diagnostics
   --  ========================================================================

   type Admission_Status is
     (Success,
      Invalid_Header,
      Malformed_Column_Count,
      Invalid_Issue_Id,
      Duplicate_Issue_Id,
      Unknown_Status,
      Invalid_Recorded_Date,
      Invalid_Due_Date,
      Invalid_Closed_Date,
      Invalid_Amount,
      Invalid_Commodity,
      Partial_Amount_Currency,
      Open_Issue_With_Closure,
      Closed_Issue_Without_Closure,
      Closed_Before_Recorded,
      Contains_Control_Character);

   type Admission_Diagnostic is record
      Status      : Admission_Status := Success;
      Line_Number : Natural := 0;
      Issue_ID    : Unbounded_String;
      Message     : Unbounded_String;
   end record;

   function Admit_Issues_TSV
     (TSV_Text : String;
      Inv      : out Issues_Inventory;
      Diag     : out Admission_Diagnostic) return Boolean;

private

   type Issue_Id is record
      ID_Text : Unbounded_String;
   end record;

   package Issue_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Household_Issue);

   type Issues_Inventory is record
      Items : Issue_Vectors.Vector;
   end record;

end HRA.Issues;
