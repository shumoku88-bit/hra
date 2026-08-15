with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Containers.Indefinite_Ordered_Maps;
with ALedger.Money; use ALedger.Money;
with ALedger.Account;
with ALedger.Envelope;
with ALedger.Envelope_Routing;
with ALedger.Fulfillment_Routing;
with ALedger.Plan_Observation;
with ALedger.Cycle_Observation;

package ALedger.Envelope_Commitment is

   package Envelope_Balance_Maps is new Ada.Containers.Indefinite_Ordered_Maps
     (Key_Type     => String,
      Element_Type => Balance);

   package Account_Balance_Maps is new Ada.Containers.Indefinite_Ordered_Maps
     (Key_Type     => String,
      Element_Type => Balance);

   type Commitment_Observation is record
      Observed_Through    : Unbounded_String;
      Cycle_End_Exclusive : Unbounded_String;
      Managed             : Envelope_Balance_Maps.Map;
      Unmanaged           : Account_Balance_Maps.Map;
      Unrouted            : Account_Balance_Maps.Map;
   end record;

   function Empty_Observation return Commitment_Observation;

   type Observe_Status is
     (Success,
      Observation_Outside_Cycle,
      Undeclared_Plan_Account,
      Unsupported_Expense_Plan_Flow);

   type Observe_Diagnostic is record
      Status  : Observe_Status := Success;
      Plan_Id : Unbounded_String;
      Message : Unbounded_String;
   end record;

   --  Compatibility observation with no Fulfillment routing. Non-Expense
   --  postings therefore create no Envelope claim.
   function Observe
     (Open_Plans       : ALedger.Plan_Observation.Open_Plan_Vectors.Vector;
      Registry         : ALedger.Account.Account_Registry;
      Routing          : ALedger.Envelope_Routing.Routing_History;
      Window           : ALedger.Cycle_Observation.Cycle_Window;
      Observed_Through : String;
      Result           : out Commitment_Observation;
      Diag             : out Observe_Diagnostic) return Boolean;

   --  Observe open Plan claims inside the current cycle horizon. Positive
   --  Expense postings route by Account through Expense routing. Positive
   --  non-Expense postings route only through the stable PlanId Fulfillment
   --  history effective at the observation day. Account identity is never a
   --  fallback for savings, investment, transfer, or liability intent.
   function Observe
     (Open_Plans       : ALedger.Plan_Observation.Open_Plan_Vectors.Vector;
      Registry         : ALedger.Account.Account_Registry;
      Routing          : ALedger.Envelope_Routing.Routing_History;
      Fulfillment      : ALedger.Fulfillment_Routing.Fulfillment_Routing_History;
      Window           : ALedger.Cycle_Observation.Cycle_Window;
      Observed_Through : String;
      Result           : out Commitment_Observation;
      Diag             : out Observe_Diagnostic) return Boolean;

   function Commitment_For
     (Obs : Commitment_Observation;
      Env : ALedger.Envelope.Envelope_Id) return Balance;

end ALedger.Envelope_Commitment;
