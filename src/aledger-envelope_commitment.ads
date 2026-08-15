with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Containers.Indefinite_Ordered_Maps;
with ALedger.Money; use ALedger.Money;
with ALedger.Account;
with ALedger.Envelope;
with ALedger.Envelope_Routing;
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
      Observed_Through   : Unbounded_String;
      Cycle_End_Exclusive : Unbounded_String;
      Managed            : Envelope_Balance_Maps.Map;
      Unmanaged          : Account_Balance_Maps.Map;
      Unrouted           : Account_Balance_Maps.Map;
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

   --  Observe open Plan claims inside the current cycle horizon. Positive
   --  Expense postings route through the effective-dated Expense history at
   --  the observation day. Missing routing remains explicit attention
   --  evidence; Not_Envelope_Managed remains distinct. Non-Expense positive
   --  targets do not inherit Envelope meaning from Account identity.
   function Observe
     (Open_Plans       : ALedger.Plan_Observation.Open_Plan_Vectors.Vector;
      Registry         : ALedger.Account.Account_Registry;
      Routing          : ALedger.Envelope_Routing.Routing_History;
      Window           : ALedger.Cycle_Observation.Cycle_Window;
      Observed_Through : String;
      Result           : out Commitment_Observation;
      Diag             : out Observe_Diagnostic) return Boolean;

   function Commitment_For
     (Obs : Commitment_Observation;
      Env : ALedger.Envelope.Envelope_Id) return Balance;

end ALedger.Envelope_Commitment;
