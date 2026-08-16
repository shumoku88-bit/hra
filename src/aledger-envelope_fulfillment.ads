with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Containers.Indefinite_Ordered_Maps;
with Ada.Containers.Indefinite_Vectors;
with ALedger.Account;
with ALedger.Dates;
with ALedger.Envelope;
with ALedger.Fulfillment_Routing;
with ALedger.Ledger;
with ALedger.Money; use ALedger.Money;
with ALedger.Plan;
with ALedger.Plan_Observation;

package ALedger.Envelope_Fulfillment is

   --  Gross completed-Plan fulfillment and explicit reversal evidence.
   --  Reversed is stored as a positive magnitude; net is Applied - Reversed.
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

   --  Provenance for one routed target posting. The route is frozen at the root
   --  completion Actual date. Exact Plan/Actual source header coordinates remain
   --  attached to the resulting observation.
   type Fulfillment_Evidence is record
      Plan_ID              : ALedger.Plan.Plan_Id;
      Envelope_ID          : ALedger.Envelope.Envelope_Id;
      Completion_Date      : ALedger.Dates.Date;
      Root_Actual_Event_ID : Unbounded_String;
      Plan_Header_Line     : Natural;
      Actual_Header_Line   : Natural;
      Target_Posting_Index : Positive;
      Route_Effective_From : ALedger.Dates.Date;
      Route_Note           : Unbounded_String;
      Applied              : Balance;
      Reversed             : Balance;
   end record;

   package Evidence_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Fulfillment_Evidence);

   type Envelope_Fulfillment is record
      Observed_Through : ALedger.Dates.Date;
      Managed          : Envelope_Amounts_Maps.Map;
      Evidence         : Evidence_Vectors.Vector;
   end record;

   function Empty_Fulfillment return Envelope_Fulfillment;

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

   --  Observe explicit completed Plan fulfillment through one inclusive day.
   --
   --  * completion comes only from Plan_Observation's explicit Actual plan-id
   --  * the completion Actual is the non-reversal root of its evidence chain
   --  * route identity is resolved at the root completion Actual day
   --  * only positive non-Expense Plan posting positions are fulfillment targets
   --  * corresponding Actual quantities are authoritative
   --  * Event_ID/Reverses_ID chains reverse or restore the same root evidence
   function Observe
     (Completed        : ALedger.Plan_Observation.Completed_Plan_Vectors.Vector;
      Actual_Ledger    : ALedger.Ledger.Ledger;
      Registry         : ALedger.Account.Account_Registry;
      Routing          : ALedger.Fulfillment_Routing.Fulfillment_Routing_History;
      Observed_Through : ALedger.Dates.Date;
      Result           : out Envelope_Fulfillment;
      Diag             : out Observe_Diagnostic) return Boolean;

   function Fulfillment_For
     (Obs : Envelope_Fulfillment;
      Env : ALedger.Envelope.Envelope_Id) return Fulfillment_Amounts;

   function Net_For
     (Obs : Envelope_Fulfillment;
      Env : ALedger.Envelope.Envelope_Id) return Balance;

end ALedger.Envelope_Fulfillment;
