with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Containers.Indefinite_Ordered_Maps;
with Ada.Containers.Indefinite_Vectors;
with ALedger.Money;          use ALedger.Money;
with ALedger.Envelope;       use ALedger.Envelope;
with ALedger.Envelope_Entitlement;
with ALedger.Envelope_Consumption;
with ALedger.Envelope_Commitment;
with ALedger.Plan_Observation;
with ALedger.Cycle_Observation;
with ALedger.Budget_Config;
with ALedger.Ledger;
with ALedger.Config_Support;

package ALedger.Backing_Policy is

   --  Remaining = Entitlement - Net Consumption.
   --  Headroom = Remaining - current-cycle Envelope Plan Commitment.
   type Backed_Envelope_Claim is record
      Env_Id    : Envelope.Envelope_Id;
      Remaining : Balance;
      Headroom  : Balance;
   end record;

   function "=" (Left, Right : Backed_Envelope_Claim) return Boolean;

   package Claim_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Backed_Envelope_Claim,
      "="          => "=");

   type Backing_Pool_Position is record
      Pool_Id                     : Unbounded_String;
      Claims                      : Claim_Vectors.Vector;
      Funding_Balance             : Balance;
      Funding_Commitment          : Balance;
      Gross_Envelope_Required     : Balance;
      Available_Envelope_Required : Balance;
   end record;

   function "=" (Left, Right : Backing_Pool_Position) return Boolean;

   function Available_Funding (Pos : Backing_Pool_Position) return Balance;
   function Gross_Surplus (Pos : Backing_Pool_Position) return Balance;
   function Available_Surplus (Pos : Backing_Pool_Position) return Balance;

   type Backing_Policy is private;

   type Policy_Status is
     (Success,
      Duplicate_Pool_Definition,
      Empty_Pool_Assets,
      Duplicate_Asset_Membership,
      Duplicate_Envelope_Assignment,
      Unknown_Pool_Reference);

   function Admit_Backing_Policy
     (Config   : Budget_Config.Budget_Policy;
      Registry : Envelope.Envelope_Registry;
      Policy   : out Backing_Policy;
      Status   : out Policy_Status) return Boolean;

   package Pool_Balance_Maps is new Ada.Containers.Indefinite_Ordered_Maps
     (Key_Type     => String,
      Element_Type => Balance);

   --  Independent funding horizon for open Plans. Destination meaning does not
   --  enter this projection: every negative posting from an Asset assigned to
   --  a Backing pool reserves its positive magnitude in that pool.
   type Funding_Commitment_Observation is record
      By_Pool : Pool_Balance_Maps.Map;
   end record;

   function Empty_Funding_Commitment return Funding_Commitment_Observation;

   function Observe_Funding_Commitment
     (Policy     : Backing_Policy;
      Open_Plans : ALedger.Plan_Observation.Open_Plan_Vectors.Vector;
      Window     : ALedger.Cycle_Observation.Cycle_Window)
      return Funding_Commitment_Observation;

   function Funding_Commitment_For
     (Obs     : Funding_Commitment_Observation;
      Pool_Id : String) return Balance;

   package Pool_Position_Maps is new Ada.Containers.Indefinite_Ordered_Maps
     (Key_Type     => String,
      Element_Type => Backing_Pool_Position,
      "="          => "=");

   type Backing_Observation is record
      Positions    : Pool_Position_Maps.Map;
      Total_Assets : Balance;
   end record;

   --  Base admitted-Household view. No application observation day has been
   --  supplied, so no Plan claims or funding commitments are applied.
   function Observe_Backing
     (Policy      : Backing_Policy;
      L           : Ledger.Ledger;
      Entitlement : Envelope_Entitlement.Entitlement_Observation;
      Consumption : Envelope_Consumption.Envelope_Consumption) return Backing_Observation;

   --  Observation-specific view. Envelope commitment and funding commitment
   --  are deliberately independent projections of the same role-neutral open
   --  Plan collection.
   function Observe_Backing
     (Policy             : Backing_Policy;
      L                  : Ledger.Ledger;
      Entitlement        : Envelope_Entitlement.Entitlement_Observation;
      Consumption        : Envelope_Consumption.Envelope_Consumption;
      Commitment         : Envelope_Commitment.Commitment_Observation;
      Funding_Commitment : Funding_Commitment_Observation)
      return Backing_Observation;

   function Position_For
     (Obs     : Backing_Observation;
      Pool_Id : String) return Backing_Pool_Position;

   function Claim_For
     (Obs : Backing_Observation;
      Env : Envelope.Envelope_Id) return Backed_Envelope_Claim;

   function Positive_Balance (B : Balance) return Balance;

private

   package String_Maps is new Ada.Containers.Indefinite_Ordered_Maps
     (Key_Type     => String,
      Element_Type => String);

   package String_Vector_Maps is new Ada.Containers.Indefinite_Ordered_Maps
     (Key_Type     => String,
      Element_Type => Config_Support.String_Vectors.Vector,
      "="          => Config_Support.String_Vectors."=");

   type Backing_Policy is record
      Pool_Ids          : Config_Support.String_Vectors.Vector;
      Pool_By_Asset     : String_Maps.Map;
      Pool_By_Envelope  : String_Maps.Map;
      Assets_By_Pool    : String_Vector_Maps.Map;
      Envelopes_By_Pool : String_Vector_Maps.Map;
   end record;

end ALedger.Backing_Policy;
