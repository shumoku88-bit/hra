with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Containers.Indefinite_Vectors;
with HRA.Config_Support; use HRA.Config_Support;
with HRA.Dates;
with HRA.Budget_Config;
with HRA.Money;

package HRA.Household_Config is

   type Cycle_Mode is (Income_Anchor);

   type Envelope_Coordinates is record
      ID                 : Unbounded_String;
      Allocation_Account : Unbounded_String;
   end record;

   type Daily_Target_Asset is record
      ID      : Unbounded_String;
      Account : Unbounded_String;
   end record;

   package Envelope_Coordinate_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Positive, Element_Type => Envelope_Coordinates);
   package Daily_Target_Asset_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Positive, Element_Type => Daily_Target_Asset);

   --  ========================================================================
   --  Envelope History Data (from [envelope-history] section)
   --  ========================================================================

   type Effective_Date_Kind is (Initial, From_Date);

   type Effective_Date_Data (Kind : Effective_Date_Kind := Initial) is record
      case Kind is
         when Initial   => null;
         when From_Date => Date : HRA.Dates.Date;
      end case;
   end record;

   type Expense_Route_Kind is (Managed, Not_Managed);

   type Expense_Route_Data (Kind : Expense_Route_Kind := Not_Managed) is record
      case Kind is
         when Managed     => Target : Unbounded_String;
         when Not_Managed => null;
      end case;
   end record;

   type Expense_Routing_Entry_Data is record
      Effective       : Effective_Date_Data;
      Expense_Account : Unbounded_String;
      Route           : Expense_Route_Data;
      Note            : Unbounded_String;
   end record;

   package Expense_Routing_Entry_Data_Vectors is
     new Ada.Containers.Indefinite_Vectors
       (Index_Type => Positive, Element_Type => Expense_Routing_Entry_Data);

   type Fulfillment_Route_Kind is (Fulfills, Not_Target);

   type Fulfillment_Route_Data
     (Kind : Fulfillment_Route_Kind := Not_Target)
   is record
      case Kind is
         when Fulfills   => Target : Unbounded_String;
         when Not_Target => null;
      end case;
   end record;

   type Fulfillment_Routing_Entry_Data is record
      Effective_From : HRA.Dates.Date;
      Plan_ID        : Unbounded_String;
      Route          : Fulfillment_Route_Data;
      Note           : Unbounded_String;
   end record;

   package Fulfillment_Routing_Entry_Data_Vectors is
     new Ada.Containers.Indefinite_Vectors
       (Index_Type => Positive, Element_Type => Fulfillment_Routing_Entry_Data);

   type Envelope_History_Data is record
      Identities          : String_Vectors.Vector;
      Expense_Routing     : Expense_Routing_Entry_Data_Vectors.Vector;
      Fulfillment_Routing : Fulfillment_Routing_Entry_Data_Vectors.Vector;
   end record;

   type Household_Configuration is record
      Cycle                 : Cycle_Mode;
      Cycle_Income_Account  : Unbounded_String;
      Has_Primary_Commodity : Boolean := False;
      Primary_Commodity     : HRA.Money.Commodity;
      Opening_Accounts      : String_Vectors.Vector;
      Unassigned_Accounts   : String_Vectors.Vector;
      Envelopes             : Envelope_Coordinate_Vectors.Vector;
      Daily_Target_Assets   : Daily_Target_Asset_Vectors.Vector;
      Envelope_History      : Envelope_History_Data;
   end record;

   function Parse_Household_Configuration
     (Text          : String;
      Budget_Policy : HRA.Budget_Config.Budget_Policy;
      Config        : out Household_Configuration;
      Diag          : out Config_Diagnostic) return Boolean;

end HRA.Household_Config;
