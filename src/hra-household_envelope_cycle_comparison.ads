with Ada.Containers.Vectors;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA.Cycle_Observation;
with HRA.Dates;
with HRA.Envelope;
with HRA.Envelope_Consumption;
with HRA.Envelope_Fulfillment;
with HRA.Household;
with HRA.Money; use HRA.Money;

--  Explicit comparison between two Envelope cycles at the same elapsed day.
--
--  This is deliberately distinct from HRA.Household_Envelope_Change. Change is
--  a relation between two observations inside one cycle. Crossing a cycle
--  boundary changes the question: bounded activity is compared cycle-to-cycle,
--  while Entitlement/Remaining/Commitment/Headroom remain point-in-time
--  positions at aligned observation days.
package HRA.Household_Envelope_Cycle_Comparison is

   type Comparison_Side is (Current_Cycle, Baseline_Cycle);

   type Comparison_Line is record
      Env_Id                : HRA.Envelope.Envelope_Id;
      Current_Consumption   : HRA.Envelope_Consumption.Consumption_Amounts;
      Baseline_Consumption  : HRA.Envelope_Consumption.Consumption_Amounts;
      Current_Fulfillment   : HRA.Envelope_Fulfillment.Fulfillment_Amounts;
      Baseline_Fulfillment  : HRA.Envelope_Fulfillment.Fulfillment_Amounts;
      Current_Entitlement   : Balance;
      Baseline_Entitlement  : Balance;
      Current_Remaining     : Balance;
      Baseline_Remaining    : Balance;
      Current_Commitment    : Balance;
      Baseline_Commitment   : Balance;
      Current_Headroom      : Balance;
      Baseline_Headroom     : Balance;
   end record;

   package Comparison_Line_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Comparison_Line);

   type Comparison_Observation is record
      Current_Window   : HRA.Cycle_Observation.Cycle_Window;
      Baseline_Window  : HRA.Cycle_Observation.Cycle_Window;
      Current_Through  : HRA.Dates.Date;
      Baseline_Through : HRA.Dates.Date;
      Lines            : Comparison_Line_Vectors.Vector;
   end record;

   type Observe_Status is
     (Success,
      Period_Order_Invalid,
      Current_Observation_Outside_Window,
      Aligned_Baseline_Outside_Window,
      Current_Observation_Unavailable,
      Baseline_Observation_Unavailable,
      Current_Explanation_Unavailable,
      Baseline_Explanation_Unavailable,
      Current_Fulfillment_Unavailable,
      Baseline_Fulfillment_Unavailable,
      Envelope_Order_Mismatch);

   type Observe_Diagnostic is record
      Status         : Observe_Status := Success;
      Side           : Comparison_Side := Current_Cycle;
      Mismatch_Index : Natural := 0;
      Message        : Unbounded_String := Null_Unbounded_String;
   end record;

   --  Compare Current_Window against an earlier Baseline_Window at the same
   --  elapsed day from each cycle start. Both windows are explicit evidence.
   --  The observer never weakens same-cycle Change and never infers a baseline
   --  from journal activity.
   function Observe_Aligned
     (Current_Through : HRA.Dates.Date;
      Current_Window  : HRA.Cycle_Observation.Cycle_Window;
      Baseline_Window : HRA.Cycle_Observation.Cycle_Window;
      State           : HRA.Household.Household_State;
      Result          : out Comparison_Observation;
      Diag            : out Observe_Diagnostic) return Boolean;

   function Consumption_Net_Difference
     (Line : Comparison_Line) return Balance;

   function Fulfillment_Net_Difference
     (Line : Comparison_Line) return Balance;

   function Entitlement_Difference
     (Line : Comparison_Line) return Balance;

   function Remaining_Difference
     (Line : Comparison_Line) return Balance;

   function Commitment_Difference
     (Line : Comparison_Line) return Balance;

   function Headroom_Difference
     (Line : Comparison_Line) return Balance;

end HRA.Household_Envelope_Cycle_Comparison;
