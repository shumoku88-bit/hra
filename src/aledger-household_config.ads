with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Containers.Indefinite_Vectors;
with ALedger.Config_Support; use ALedger.Config_Support;
with ALedger.Budget_Config;
with ALedger.Money;

package ALedger.Household_Config is

   type Cycle_Mode is (Income_Anchor);

   type Envelope_Coordinates is record
      ID                        : Unbounded_String;
      Allocation_Account        : Unbounded_String;
      Plan_Destination_Accounts : String_Vectors.Vector;
   end record;

   type Daily_Target_Asset is record
      ID      : Unbounded_String;
      Account : Unbounded_String;
   end record;

   package Envelope_Coordinate_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Positive, Element_Type => Envelope_Coordinates);
   package Daily_Target_Asset_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Positive, Element_Type => Daily_Target_Asset);

   type Account_Policy is record
      Liquid_Assets       : String_Vectors.Vector;
      Savings_Assets      : String_Vectors.Vector;
      Investment_Assets   : String_Vectors.Vector;
      Opening_Budget      : String_Vectors.Vector;
      Unassigned_Budget   : String_Vectors.Vector;
      Spent_Budget        : String_Vectors.Vector;
      Envelope_Budget     : String_Vectors.Vector;
      Unassigned_Role     : String_Vectors.Vector;
      Dynamic_Role        : String_Vectors.Vector;
      Execution_Role      : String_Vectors.Vector;
      Daily_Group         : String_Vectors.Vector;
      Flex_Group          : String_Vectors.Vector;
      Reserve_Group       : String_Vectors.Vector;
      Fixed_Expenses      : String_Vectors.Vector;
      Variable_Expenses   : String_Vectors.Vector;
   end record;

   type Household_Configuration is record
      Cycle                    : Cycle_Mode;
      Cycle_Income_Account     : Unbounded_String;
      Has_Primary_Commodity    : Boolean := False;
      Primary_Commodity        : ALedger.Money.Commodity;
      Unassigned_Accounts      : String_Vectors.Vector;
      Envelopes                : Envelope_Coordinate_Vectors.Vector;
      Daily_Target_Assets      : Daily_Target_Asset_Vectors.Vector;
      Has_Account_Policy       : Boolean := False;
      Accounts                 : Account_Policy;
   end record;

   function Parse_Household_Configuration
     (Text          : String;
      Budget_Policy : ALedger.Budget_Config.Budget_Policy;
      Config        : out Household_Configuration;
      Diag          : out Config_Diagnostic) return Boolean;

end ALedger.Household_Config;
