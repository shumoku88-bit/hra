with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Containers.Indefinite_Ordered_Maps;
with ALedger.Budget_Config;
with ALedger.Envelope;
with ALedger.Envelope_Entitlement;
with ALedger.Envelope_Consumption;
with ALedger.Envelope_Fulfillment;
with ALedger.Envelope_Commitment;
with ALedger.Money; use ALedger.Money;

--  Current Envelope position observation.
--
--  The current Envelope set comes from typed budget policy. Stable historical
--  identity remains owned by Envelope_Registry and is never inferred from the
--  current policy. Arithmetic authority is ALedger.Proof_Core, reached only
--  through ALedger.Proof_Money_Bridge.
package ALedger.Envelope_Position is

   type Position is record
      Env_Id    : ALedger.Envelope.Envelope_Id;
      Remaining : Balance;
      Headroom  : Balance;
   end record;

   function "=" (Left, Right : Position) return Boolean;

   --  Typed evidence used to explain one proof-backed Position. Gross activity
   --  remains beside the net values passed to the proof core so cancellation
   --  cannot erase the fact that opposite movements occurred.
   type Arithmetic_Evidence is record
      Entitlement          : Balance;
      Consumption_Charges  : Balance;
      Consumption_Refunds  : Balance;
      Net_Consumption      : Balance;
      Fulfillment_Applied  : Balance;
      Fulfillment_Reversed : Balance;
      Net_Fulfillment      : Balance;
      Plan_Commitment      : Balance;
   end record;

   function "=" (Left, Right : Arithmetic_Evidence) return Boolean;

   --  Explanation combines the exact typed evidence retained by the observer
   --  with the proof-backed result derived from that same observation.
   type Explanation is record
      Evidence          : Arithmetic_Evidence;
      Observed_Position : Position;
   end record;

   package Position_Maps is new Ada.Containers.Indefinite_Ordered_Maps
     (Key_Type     => String,
      Element_Type => Position,
      "="          => "=");

   package Arithmetic_Evidence_Maps is new
     Ada.Containers.Indefinite_Ordered_Maps
       (Key_Type     => String,
        Element_Type => Arithmetic_Evidence,
        "="          => "=");

   type Observation is record
      Positions : Position_Maps.Map;
      Evidence  : Arithmetic_Evidence_Maps.Map;
   end record;

   function Empty_Observation return Observation;

   type Value_Role is
     (Entitlement_Value,
      Net_Consumption_Value,
      Net_Fulfillment_Value,
      Plan_Commitment_Value,
      Remaining_Result,
      Headroom_Result);

   type Observe_Status is
     (Success,
      Unknown_Current_Envelope,
      Duplicate_Current_Envelope,
      Negative_Plan_Commitment,
      Proof_Input_Out_Of_Range,
      Proof_Output_Out_Of_Range,
      Non_Exact_Proof_Conversion);

   type Observe_Diagnostic is record
      Status           : Observe_Status := Success;
      Envelope_Id_Text : Unbounded_String;
      Commodity_Code   : Unbounded_String;
      Role             : Value_Role := Entitlement_Value;
   end record;

   --  Base Household view: Remaining uses Entitlement and stock Consumption;
   --  Fulfillment and Plan Commitment are zero because no application
   --  observation day has been supplied.
   function Observe_Base
     (Policy      : ALedger.Budget_Config.Budget_Policy;
      Registry    : ALedger.Envelope.Envelope_Registry;
      Entitlement : ALedger.Envelope_Entitlement.Entitlement_Observation;
      Consumption : ALedger.Envelope_Consumption.Envelope_Consumption;
      Result      : out Observation;
      Diag        : out Observe_Diagnostic) return Boolean;

   --  Observation-specific view. All four inputs are already admitted for the
   --  same Household observation horizon. The observer only coordinates
   --  Commodity-wise exact proof evaluation; it does not classify source facts.
   function Observe
     (Policy      : ALedger.Budget_Config.Budget_Policy;
      Registry    : ALedger.Envelope.Envelope_Registry;
      Entitlement : ALedger.Envelope_Entitlement.Entitlement_Observation;
      Consumption : ALedger.Envelope_Consumption.Envelope_Consumption;
      Fulfillment : ALedger.Envelope_Fulfillment.Envelope_Fulfillment;
      Commitment  : ALedger.Envelope_Commitment.Commitment_Observation;
      Result      : out Observation;
      Diag        : out Observe_Diagnostic) return Boolean;

   function Has_Position
     (Obs : Observation;
      Env : ALedger.Envelope.Envelope_Id) return Boolean;

   function Position_For
     (Obs : Observation;
      Env : ALedger.Envelope.Envelope_Id) return Position
     with Pre => Has_Position (Obs, Env);

   function Has_Explanation
     (Obs : Observation;
      Env : ALedger.Envelope.Envelope_Id) return Boolean;

   --  Pure projection only: no source read, no arithmetic recomputation, and no
   --  new authority. The explanation is the evidence and result retained by the
   --  same successful position observation.
   function Explain
     (Obs : Observation;
      Env : ALedger.Envelope.Envelope_Id) return Explanation
     with Pre => Has_Explanation (Obs, Env);

end ALedger.Envelope_Position;
