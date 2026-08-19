with Ada.Containers.Vectors;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA.Budget_Config;
with HRA.Cycle_Observation;
with HRA.Dates;
with HRA.Envelope;
with HRA.Envelope_Position;
with HRA.Household;

--  First-class explanation of one admitted Household Envelope observation.
--  Explanation is a projection of typed evidence already retained by
--  Envelope_Position. It does not reread sources or recompute arithmetic.
package HRA.Household_Envelope_Explanation is

   type Explanation_Line is record
      Env_Id : HRA.Envelope.Envelope_Id;
      Why    : HRA.Envelope_Position.Explanation;
   end record;

   package Explanation_Line_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Explanation_Line);

   type Explanation_Observation is record
      Window           : HRA.Cycle_Observation.Cycle_Window;
      Observed_Through : HRA.Dates.Date;
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
            Rejected_Through : HRA.Dates.Date;
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
     (Policy           : HRA.Budget_Config.Budget_Policy;
      Registry         : HRA.Envelope.Envelope_Registry;
      Window           : HRA.Cycle_Observation.Cycle_Window;
      Observed_Through : HRA.Dates.Date;
      Positions        : HRA.Envelope_Position.Observation;
      Result           : out Explanation_Observation;
      Diag             : out Explain_Diagnostic) return Boolean;

   --  Application entry point: explain the current Envelope set at one day
   --  directly from an already-admitted Household. The same focused
   --  Household Envelope observation used by Report and Change is reused.
   function Explain
     (Observed_Through : HRA.Dates.Date;
      State            : HRA.Household.Household_State;
      Result           : out Explanation_Observation;
      Diag             : out Explain_Diagnostic) return Boolean;

end HRA.Household_Envelope_Explanation;
