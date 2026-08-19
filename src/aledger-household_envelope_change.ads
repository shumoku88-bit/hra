with Ada.Containers.Vectors;
with ALedger.Cycle_Observation;
with ALedger.Dates;
with ALedger.Envelope;
with ALedger.Household_Envelope_Explanation;
with ALedger.Money; use ALedger.Money;

--  Same-cycle temporal relation between already admitted Envelope explanations.
--  This package owns temporal comparison questions, not source reading,
--  explanation capture, or proof arithmetic.
package ALedger.Household_Envelope_Change is

   --  Selecting the earlier observation is a temporal question distinct from
   --  fieldwise Change arithmetic.
   type Baseline_Kind is
     (Previous_Observation,
      Previous_Day,
      Cycle_Start,
      Explicit_Day);

   type Baseline_Request (Kind : Baseline_Kind := Previous_Observation) is record
      case Kind is
         when Explicit_Day =>
            Requested_Day : ALedger.Dates.Date;
         when others =>
            null;
      end case;
   end record;

   type Previous_Observation_Kind is
     (No_Previous_Observation,
      Previous_Observation_Available);

   type Previous_Observation_Context
     (Kind : Previous_Observation_Kind := No_Previous_Observation)
   is record
      case Kind is
         when No_Previous_Observation =>
            null;
         when Previous_Observation_Available =>
            Observed_Through : ALedger.Dates.Date;
      end case;
   end record;

   type Resolved_Change_Baseline is private;

   type Baseline_Status is
     (Success,
      Through_Outside_Window,
      Previous_Observation_Unavailable,
      Previous_Observation_Not_Before,
      Previous_Day_Unavailable,
      Baseline_Day_Outside_Window,
      Baseline_Day_After_Observation);

   type Baseline_Diagnostic (Status : Baseline_Status := Success) is record
      case Status is
         when Success =>
            null;
         when Through_Outside_Window =>
            Rejected_Through : ALedger.Dates.Date;
         when Previous_Observation_Unavailable =>
            null;
         when Previous_Observation_Not_Before =>
            Previous_Day_Value : ALedger.Dates.Date;
            Current_Through    : ALedger.Dates.Date;
         when Previous_Day_Unavailable =>
            Boundary_Through : ALedger.Dates.Date;
         when Baseline_Day_Outside_Window =>
            Outside_Request : Baseline_Request;
            Outside_Day     : ALedger.Dates.Date;
         when Baseline_Day_After_Observation =>
            Future_Request  : Baseline_Request;
            Future_Day      : ALedger.Dates.Date;
            Observation_Day : ALedger.Dates.Date;
      end case;
   end record;

   --  Resolve an earlier day without reading accounting evidence. A previous
   --  observation belongs to caller-supplied observation context and is never
   --  inferred from Journal or Envelope activity. Explicit_Day may equal Through
   --  for an intentional zero-length comparison; Previous_Observation must be
   --  strictly earlier because "previous" itself carries temporal meaning.
   function Resolve_Baseline
     (Window   : ALedger.Cycle_Observation.Cycle_Window;
      Through  : ALedger.Dates.Date;
      Previous : Previous_Observation_Context;
      Request  : Baseline_Request;
      Result   : out Resolved_Change_Baseline;
      Diag     : out Baseline_Diagnostic) return Boolean;

   function Resolved_Request
     (Baseline : Resolved_Change_Baseline) return Baseline_Request;

   function Resolved_Day
     (Baseline : Resolved_Change_Baseline) return ALedger.Dates.Date;

   type Change_Line is record
      Env_Id                 : ALedger.Envelope.Envelope_Id;
      Entitlement            : Balance;
      Consumption_Charges    : Balance;
      Consumption_Refunds    : Balance;
      Net_Consumption        : Balance;
      Fulfillment_Applied    : Balance;
      Fulfillment_Reversed   : Balance;
      Net_Fulfillment        : Balance;
      Remaining              : Balance;
      Plan_Commitment        : Balance;
      Headroom               : Balance;
   end record;

   package Change_Line_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Change_Line);

   type Change_Observation is record
      Window       : ALedger.Cycle_Observation.Cycle_Window;
      From_Date    : ALedger.Dates.Date;
      Through_Date : ALedger.Dates.Date;
      Lines        : Change_Line_Vectors.Vector;
   end record;

   type Change_Status is
     (Success,
      Window_Mismatch,
      Observation_Order_Invalid,
      Envelope_Order_Mismatch);

   type Change_Diagnostic is record
      Status         : Change_Status := Success;
      Mismatch_Index : Natural := 0;
   end record;

   --  Compare two first-class typed explanations. Every Balance coordinate is
   --  Later - Earlier. A different cycle, reversed time, or different current
   --  Envelope order changes the question and therefore fails closed.
   function Observe_Change
     (Earlier : ALedger.Household_Envelope_Explanation.Explanation_Observation;
      Later   : ALedger.Household_Envelope_Explanation.Explanation_Observation;
      Result  : out Change_Observation;
      Diag    : out Change_Diagnostic) return Boolean;

private

   type Resolved_Change_Baseline is record
      Request : Baseline_Request;
      Day     : ALedger.Dates.Date;
   end record;

end ALedger.Household_Envelope_Change;
