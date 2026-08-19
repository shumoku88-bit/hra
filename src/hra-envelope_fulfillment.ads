with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Containers.Indefinite_Ordered_Maps;
with Ada.Containers.Indefinite_Vectors;
with HRA.Account;
with HRA.Dates;
with HRA.Envelope;
with HRA.Envelope_Entitlement;
with HRA.Fulfillment_Routing;
with HRA.Ledger;
with HRA.Money; use HRA.Money;
with HRA.Plan;
with HRA.Plan_Observation;

package HRA.Envelope_Fulfillment is

   type Fulfillment_Amounts is record
      Applied  : Balance;
      Reversed : Balance;
   end record;

   function Empty_Amounts return Fulfillment_Amounts;
   function Add_Amounts
     (Left, Right : Fulfillment_Amounts) return Fulfillment_Amounts;
   function Net_Fulfillment (Amounts : Fulfillment_Amounts) return Balance;

   package Envelope_Amounts_Maps is new Ada.Containers.Indefinite_Ordered_Maps
     (Key_Type     => String,
      Element_Type => Fulfillment_Amounts);

   type Fulfillment_Evidence is record
      Plan_ID              : HRA.Plan.Plan_Id;
      Envelope_ID          : HRA.Envelope.Envelope_Id;
      Completion_Date      : HRA.Dates.Date;
      Root_Actual_Event_ID : Unbounded_String;
      Plan_Header_Line     : Natural;
      Actual_Header_Line   : Natural;
      Target_Posting_Index : Positive;
      Route_Effective_From : HRA.Dates.Date;
      Route_Note           : Unbounded_String;
      Applied              : Balance;
      Reversed             : Balance;
   end record;

   package Evidence_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Fulfillment_Evidence);

   type Envelope_Fulfillment is record
      Observed_Through : HRA.Dates.Date;
      Managed          : Envelope_Amounts_Maps.Map;
      Evidence         : Evidence_Vectors.Vector;
   end record;

   function Empty_Fulfillment
     (Observed_Through : HRA.Dates.Date) return Envelope_Fulfillment;

   type Observe_Status is
     (Success,
      Duplicate_Actual_Event_Id,
      Missing_Completion_Event_Id,
      Completion_Actual_Is_Reversal,
      Completion_Posting_Count_Mismatch,
      Completion_Account_Shape_Mismatch,
      Completion_Direction_Mismatch,
      Completion_Commodity_Mismatch,
      Undeclared_Plan_Account,
      Reversal_Shape_Mismatch);

   type Observe_Diagnostic is record
      Status  : Observe_Status := Success;
      Plan_Id : Unbounded_String;
      Message : Unbounded_String;
   end record;

   --  Activity observation through one inclusive day.
   function Observe
     (Completed        : HRA.Plan_Observation.Completed_Plan_Vectors.Vector;
      Actual_Ledger    : HRA.Ledger.Ledger;
      Registry         : HRA.Account.Account_Registry;
      Routing          : HRA.Fulfillment_Routing.Fulfillment_Routing_History;
      Observed_Through : HRA.Dates.Date;
      Result           : out Envelope_Fulfillment;
      Diag             : out Observe_Diagnostic) return Boolean;

   --  Household stock observation. A target posting contributes only when its
   --  completion root is on or after that Commodity's source-owned Entitlement
   --  origin. The whole reversal chain inherits that same root membership.
   function Observe_Stock
     (Completed        : HRA.Plan_Observation.Completed_Plan_Vectors.Vector;
      Actual_Ledger    : HRA.Ledger.Ledger;
      Registry         : HRA.Account.Account_Registry;
      Routing          : HRA.Fulfillment_Routing.Fulfillment_Routing_History;
      Entitlement      : HRA.Envelope_Entitlement.Entitlement_Observation;
      Observed_Through : HRA.Dates.Date;
      Result           : out Envelope_Fulfillment;
      Diag             : out Observe_Diagnostic) return Boolean;

   function Fulfillment_For
     (Obs : Envelope_Fulfillment;
      Env : HRA.Envelope.Envelope_Id) return Fulfillment_Amounts;

   function Net_For
     (Obs : Envelope_Fulfillment;
      Env : HRA.Envelope.Envelope_Id) return Balance;

end HRA.Envelope_Fulfillment;
