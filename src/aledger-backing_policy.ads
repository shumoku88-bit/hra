with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Containers.Indefinite_Ordered_Maps;
with Ada.Containers.Indefinite_Vectors;
with ALedger.Money;          use ALedger.Money;
with ALedger.Dates;
with ALedger.Envelope;       use ALedger.Envelope;
with ALedger.Envelope_Position;
with ALedger.Plan_Observation;
with ALedger.Cycle_Observation;
with ALedger.Budget_Config;
with ALedger.Ledger;
with ALedger.Config_Support;

package ALedger.Backing_Policy is

   package Claim_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => ALedger.Envelope_Position.Position,
      "="          => ALedger.Envelope_Position."=");

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

   --  Base admitted-Household view. Funding reflects the complete admitted
   --  Ledger; claims come directly from base Envelope_Position.Observation.
   function Observe_Backing
     (Policy    : Backing_Policy;
      L         : Ledger.Ledger;
      Positions : ALedger.Envelope_Position.Observation) return Backing_Observation;

   --  Observation-specific view. Funding is observed through the same inclusive
   --  day as Consumption and Fulfillment. Claims come directly from evaluated
   --  Envelope_Position.Observation; pool commitments come from Funding_Commitment.
   function Observe_Backing
     (Policy             : Backing_Policy;
      L                  : Ledger.Ledger;
      Observed_Through   : ALedger.Dates.Date;
      Positions          : ALedger.Envelope_Position.Observation;
      Funding_Commitment : Funding_Commitment_Observation)
      return Backing_Observation;

   function Position_For
     (Obs     : Backing_Observation;
      Pool_Id : String) return Backing_Pool_Position;

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
