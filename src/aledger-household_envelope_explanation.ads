with Ada.Containers.Vectors;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with ALedger.Budget_Config;
with ALedger.Cycle_Observation;
with ALedger.Dates;
with ALedger.Envelope;
with ALedger.Envelope_Position;
with ALedger.Household;

--  First-class explanation of one admitted Household Envelope observation.
--  Explanation is a projection of typed evidence already retained by
--  Envelope_Position. It does not reread sources or recompute arithmetic.
package ALedger.Household_Envelope_Explanation is

   type Explanation_Line is record
      Env_Id : ALedger.Envelope.Envelope_Id;
      Why    : ALedger.Envelope_Position.Explanation;
   end record;

   package Explanation_Line_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Explanation_Line);

   type Explanation_Observation is record
      Window           : ALedger.Cycle_Observation.Cycle_Window;
      Observed_Through : ALedger.Dates.Date;
      Lines            : Explanation_Line_Vectors.Vector;
   end record;

   type Explain_Status is
     (Success,
      Observation_Unavailable,
      Observation_Outside_Window,
      Unknown_Current_Envelope,
      Missing_Envelope_Explanation);

   type Explain_Diagnostic (Status : Explain_Status := Success) is record
      case Status is
         when Success =>
            null;
         when Observation_Unavailable =>
            Observation_Error : Unbounded_String;
         when Observation_Outside_Window =>
            Rejected_Through : ALedger.Dates.Date;
         when Unknown_Current_Envelope |
              Missing_Envelope_Explanation =>
            Envelope_Id_Text : Unbounded_String;
      end case;
   end record;

   --  Capture one ordered explanation from an already-observed Position set.
   --  Current membership and order come from Budget_Policy, stable identity
   --  comes from Envelope_Registry, and arithmetic evidence comes only from
   --  the supplied Position observation.
   function Capture
     (Policy           : ALedger.Budget_Config.Budget_Policy;
      Registry         : ALedger.Envelope.Envelope_Registry;
      Window           : ALedger.Cycle_Observation.Cycle_Window;
      Observed_Through : ALedger.Dates.Date;
      Positions        : ALedger.Envelope_Position.Observation;
      Result           : out Explanation_Observation;
      Diag             : out Explain_Diagnostic) return Boolean;

   --  Application entry point: explain the current Envelope set at one day
   --  directly from an already-admitted Household. The same focused
   --  Household Envelope observation used by Report and Change is reused.
   function Explain
     (Observed_Through : ALedger.Dates.Date;
      State            : ALedger.Household.Household_State;
      Result           : out Explanation_Observation;
      Diag             : out Explain_Diagnostic) return Boolean;

end ALedger.Household_Envelope_Explanation;
