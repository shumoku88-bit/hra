package body HRA.Household_Daily_Target_View is

   function Project
     (Scope_State   : HRA.Household.Daily_Target_Scope_State;
      Plans         : HRA.Plan_Temporal_Observation.Observation;
      Account_State : HRA.Cycle_Accounts_Observation.Observation) return View
   is
   begin
      case Scope_State.Status is
         when HRA.Household.Daily_Target_Scope_Unavailable =>
            return View'
              (Status           => Scope_Unavailable,
               Scope_Diagnostic => Scope_State.Diagnostic);

         when HRA.Household.Daily_Target_Scope_Available =>
            if not HRA.Daily_Target_Scope.Is_Configured (Scope_State.Value) then
               return View'(Status => Unconfigured);
            end if;

            declare
               Obs  : HRA.Daily_Target_Observation.Observation;
               Diag : HRA.Daily_Target_Observation.Observe_Diagnostic;
            begin
               if HRA.Daily_Target_Observation.Observe
                 (Scope_State.Value, Plans, Account_State, Obs, Diag)
               then
                  return View'
                    (Status      => Available,
                     Observation => Obs);
               else
                  return View'
                    (Status                 => Observation_Unavailable,
                     Observation_Diagnostic => Diag);
               end if;
            end;
      end case;
   end Project;

end HRA.Household_Daily_Target_View;
