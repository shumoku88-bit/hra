with Ada.Containers.Indefinite_Vectors;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA.Account;
with HRA.Household_Config;
with HRA.Money;
with HRA.Plan;
with HRA.Plan_Admission;

--  Daily Target meaning assembled from already-admitted source authorities.
--
--  Household admission owns validity of the long-lived eligible Asset policy.
--  Plan_Journal owns general Plan identity, lifecycle evidence, transactions,
--  and parser-produced metadata. This package owns only the cross-source Daily
--  Target selection meaning and the narrower selected-obligation/reservation
--  laws. It does not parse either source and does not narrow general Plan
--  admission.
package HRA.Daily_Target_Scope is

   type Selection_Id is private;
   function Text (ID : Selection_Id) return String;
   function "=" (Left, Right : Selection_Id) return Boolean;

   type Reservation_Id is private;
   function Text (ID : Reservation_Id) return String;
   function "=" (Left, Right : Reservation_Id) return Boolean;

   type Reservation_Evidence is record
      ID     : Reservation_Id;
      Amount : HRA.Money.Amount;
   end record;

   type Reservation_Option (Present : Boolean := False) is record
      case Present is
         when True  => Value : Reservation_Evidence;
         when False => null;
      end case;
   end record;

   --  A selected obligation retains only the evidence Daily Target actually
   --  consumes. The general transaction remains owned by Plan_Journal.
   type Obligation is record
      Selection   : Selection_Id;
      Plan_ID     : HRA.Plan.Plan_Id;
      Amount      : HRA.Money.Amount;
      Reservation : Reservation_Option;
   end record;

   function "=" (Left, Right : Obligation) return Boolean;

   package Account_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => HRA.Account.Account,
      "="          => HRA.Account."=");

   --  Scope storage is deliberately opaque. In particular, do not expose the
   --  generic container instantiated for Obligation: Obligation contains
   --  private semantic identities, and a visible generic instantiation would
   --  force Ada to use those private components prematurely. Consumers read a
   --  stable source-order snapshot through Count/At instead.
   type Scope is private;

   function Empty_Scope return Scope;
   function Is_Configured (Value : Scope) return Boolean;
   function Eligible_Assets (Value : Scope) return Account_Vectors.Vector;
   function Obligation_Count (Value : Scope) return Natural;
   function Obligation_At
     (Value : Scope;
      Index : Positive) return Obligation
     with Pre => Index <= Obligation_Count (Value);

   type Admission_Status is
     (Success,
      Empty_Selection_Id,
      Duplicate_Selection_Id,
      Duplicate_Daily_Target_Metadata,
      Reservation_Without_Selection,
      Incomplete_Reservation,
      Invalid_Reservation_Id,
      Invalid_Reservation_Amount,
      Invalid_Reservation_Commodity,
      Nonpositive_Reservation_Amount,
      Unsupported_Selected_Plan_Shape,
      Reservation_Commodity_Mismatch,
      Reservation_Exceeds_Obligation,
      Duplicate_Reservation_Id,
      Missing_Eligible_Assets);

   type Admission_Diagnostic is record
      Status       : Admission_Status := Success;
      Line_Number  : Natural := 0;
      Selection    : Unbounded_String;
      Plan_Id      : Unbounded_String;
      Message      : Unbounded_String;
   end record;

   --  Policy and Registry are read from one successfully admitted Household.
   --  Their Account-reference/type validity is therefore not re-admitted here.
   function Admit
     (Policy   : HRA.Household_Config.Household_Configuration;
      Registry : HRA.Account.Account_Registry;
      Plans    : HRA.Plan_Admission.Plan_Journal;
      Result   : out Scope;
      Diag     : out Admission_Diagnostic) return Boolean;

private

   type Selection_Id is record
      Value : Unbounded_String;
   end record;

   type Reservation_Id is record
      Value : Unbounded_String;
   end record;

   package Obligation_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Obligation,
      "="          => "=");

   type Scope is record
      Assets      : Account_Vectors.Vector;
      Obligations : Obligation_Vectors.Vector;
   end record;

   function Text (ID : Selection_Id) return String is
     (To_String (ID.Value));

   function Text (ID : Reservation_Id) return String is
     (To_String (ID.Value));

   function "=" (Left, Right : Selection_Id) return Boolean is
     (Left.Value = Right.Value);

   function "=" (Left, Right : Reservation_Id) return Boolean is
     (Left.Value = Right.Value);

   function Empty_Scope return Scope is
     (Assets => Account_Vectors.Empty_Vector,
      Obligations => Obligation_Vectors.Empty_Vector);

   function Is_Configured (Value : Scope) return Boolean is
     (not Value.Assets.Is_Empty);

   function Eligible_Assets (Value : Scope) return Account_Vectors.Vector is
     (Value.Assets);

   function Obligation_Count (Value : Scope) return Natural is
     (Natural (Value.Obligations.Length));

   function Obligation_At
     (Value : Scope;
      Index : Positive) return Obligation is
     (Value.Obligations.Element (Index));

end HRA.Daily_Target_Scope;
