with HRA.Cycle_Accounts_Observation;
with HRA.Daily_Target_Observation;
with HRA.Daily_Target_Scope;
with HRA.Household;
with HRA.Plan_Temporal_Observation;

--  Shared semantic Daily Target view over one admitted Household_State.
--
--  This package combines the admitted Household scope state with already-built
--  temporal Plan and Cycle Account contexts. It does not reparse sources, query
--  the Ledger, or re-admit Plan/Cycle state.
package HRA.Household_Daily_Target_View is

   type View_Status is
     (Unconfigured,
      Available,
      Scope_Unavailable,
      Observation_Unavailable);

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
      end case;
   end record;

   --  Project the Daily Target view following the fixed law:
   --    1. Scope_Unavailable  -> Scope_Unavailable
   --    2. Scope_Available but not configured -> Unconfigured (no Observe call)
   --    3. Configured scope   -> Observe (Available or Observation_Unavailable)
   function Project
     (Scope_State   : HRA.Household.Daily_Target_Scope_State;
      Plans         : HRA.Plan_Temporal_Observation.Observation;
      Account_State : HRA.Cycle_Accounts_Observation.Observation) return View;

end HRA.Household_Daily_Target_View;
