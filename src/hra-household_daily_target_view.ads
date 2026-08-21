with HRA.Cycle_Accounts_Observation;
with HRA.Cycle_Observation;
with HRA.Daily_Target_Observation;
with HRA.Daily_Target_Scope;
with HRA.Dates;
with HRA.Household;
with HRA.Ledger;
with HRA.Plan_Temporal_Observation;

--  Shared semantic Daily Target view over one admitted Household_State.
--
--  This package combines the admitted Household Daily Target scope state with
--  temporal Plan and Cycle Account contexts. It never reparses sources or
--  re-admits Plan/Cycle authorities.
--  - Project consumes already-observed Cycle Accounts contexts (such as Report).
--  - Project_From_Cycle evaluates Daily Target from a resolved Cycle Window,
--    observing Cycle Accounts once against the admitted Ledger when configured.
package HRA.Household_Daily_Target_View is

   type View_Status is
     (Unconfigured,
      Available,
      Scope_Unavailable,
      Observation_Unavailable,
      Cycle_Unavailable,
      Cycle_Accounts_Unavailable);

   type View (Status : View_Status := Unconfigured) is record
      case Status is
         when Unconfigured =>
            null;
         when Available =>
            Observation : HRA.Daily_Target_Observation.Observation;
         when Scope_Unavailable =>
            Scope_Diagnostic : HRA.Daily_Target_Scope.Admission_Diagnostic;
         when Observation_Unavailable =>
            Observation_Diagnostic : HRA.Daily_Target_Observation.Observe_Diagnostic;
         when Cycle_Unavailable =>
            Cycle_Error : HRA.Cycle_Observation.Resolve_Status;
         when Cycle_Accounts_Unavailable =>
            Cycle_Accounts_Diagnostic : HRA.Cycle_Accounts_Observation.Observe_Diagnostic;
      end case;
   end record;

   type Cycle_Availability is
     (Cycle_Window_Available,
      Cycle_Window_Unavailable);

   type Cycle_Window_Option
     (Status : Cycle_Availability := Cycle_Window_Unavailable) is record
      case Status is
         when Cycle_Window_Available   => Window : HRA.Cycle_Observation.Cycle_Window;
         when Cycle_Window_Unavailable => Error  : HRA.Cycle_Observation.Resolve_Status;
      end case;
   end record;

   --  Existing: for contexts with already-observed Cycle Accounts (such as Report).
   --    1. Scope_Unavailable  -> Scope_Unavailable
   --    2. Scope unconfigured -> Unconfigured (does not call Observe)
   --    3. Configured scope   -> Observe (Available or Observation_Unavailable)
   function Project
     (Scope_State   : HRA.Household.Daily_Target_Scope_State;
      Plans         : HRA.Plan_Temporal_Observation.Observation;
      Account_State : HRA.Cycle_Accounts_Observation.Observation) return View;

   --  For contexts evaluating Daily Target from Cycle availability (such as Home).
   --  Short-circuits in fixed order:
   --    1. Scope_Unavailable  -> Scope_Unavailable
   --    2. Scope unconfigured -> Unconfigured (does not require Cycle or Cycle Accounts)
   --    3. Cycle unavailable  -> Cycle_Unavailable
   --    4. Configured + Cycle available:
   --         Observe Cycle Accounts once
   --         - on failure: Cycle_Accounts_Unavailable
   --         - on success: delegates directly to existing Project
   function Project_From_Cycle
     (Scope_State   : HRA.Household.Daily_Target_Scope_State;
      Plans         : HRA.Plan_Temporal_Observation.Observation;
      Ledger        : HRA.Ledger.Ledger;
      Cycle_Window  : Cycle_Window_Option;
      Known_Through : HRA.Dates.Date) return View;

end HRA.Household_Daily_Target_View;
