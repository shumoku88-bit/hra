with Ada.Containers.Vectors;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with ALedger.Budget_Config;
with ALedger.Cycle_Observation;
with ALedger.Dates;
with ALedger.Envelope;
with ALedger.Envelope_Position;
with ALedger.Money; use ALedger.Money;

--  Same-cycle temporal relation between two already admitted Envelope
--  observations. This package does not read source data and does not recompute
--  Remaining or Headroom. It compares retained typed explanation evidence.
package ALedger.Household_Envelope_Change is

   type Explanation_Snapshot is private;

   type Snapshot_Status is
     (Success,
      Observation_Outside_Window,
      Unknown_Current_Envelope,
      Missing_Envelope_Explanation);

   type Snapshot_Diagnostic is record
      Status           : Snapshot_Status := Success;
      Envelope_Id_Text : Unbounded_String;
   end record;

   --  Capture one ordered typed explanation coordinate. Envelope membership and
   --  order come from current admitted policy; stable identity comes from the
   --  registry. Observed_Through must belong to Window.
   function Capture
     (Policy           : ALedger.Budget_Config.Budget_Policy;
      Registry         : ALedger.Envelope.Envelope_Registry;
      Window           : ALedger.Cycle_Observation.Cycle_Window;
      Observed_Through : ALedger.Dates.Date;
      Positions        : ALedger.Envelope_Position.Observation;
      Result           : out Explanation_Snapshot;
      Diag             : out Snapshot_Diagnostic) return Boolean;

   function Observed_Through
     (Snapshot : Explanation_Snapshot) return ALedger.Dates.Date;

   function Window_Of
     (Snapshot : Explanation_Snapshot)
      return ALedger.Cycle_Observation.Cycle_Window;

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

   --  Compare two typed explanation snapshots. Every Balance coordinate is
   --  Later - Earlier. A different cycle, reversed time, or different current
   --  Envelope order changes the question and therefore fails closed.
   function Observe_Change
     (Earlier : Explanation_Snapshot;
      Later   : Explanation_Snapshot;
      Result  : out Change_Observation;
      Diag    : out Change_Diagnostic) return Boolean;

private

   type Explanation_Line is record
      Env_Id : ALedger.Envelope.Envelope_Id;
      Why    : ALedger.Envelope_Position.Explanation;
   end record;

   package Explanation_Line_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Explanation_Line);

   type Explanation_Snapshot is record
      Window           : ALedger.Cycle_Observation.Cycle_Window;
      Observed_Through : ALedger.Dates.Date;
      Lines            : Explanation_Line_Vectors.Vector;
   end record;

end ALedger.Household_Envelope_Change;
