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

   function Project_From_Cycle
     (Scope_State   : HRA.Household.Daily_Target_Scope_State;
      Plans         : HRA.Plan_Temporal_Observation.Observation;
      Ledger        : HRA.Ledger.Ledger;
      Cycle_Window  : Cycle_Window_Option;
      Known_Through : HRA.Dates.Date) return View
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

            case Cycle_Window.Status is
               when Cycle_Window_Unavailable =>
                  return View'
                    (Status      => Cycle_Unavailable,
                     Cycle_Error => Cycle_Window.Error);

               when Cycle_Window_Available =>
                  declare
                     Account_State : HRA.Cycle_Accounts_Observation.Observation;
                     Acc_Diag      : HRA.Cycle_Accounts_Observation.Observe_Diagnostic;
                  begin
                     if not HRA.Cycle_Accounts_Observation.Observe
                       (L                => Ledger,
                        Window           => Cycle_Window.Window,
                        Observed_Through => Known_Through,
                        Result           => Account_State,
                        Diag             => Acc_Diag)
                     then
                        return View'
                          (Status                    => Cycle_Accounts_Unavailable,
                           Cycle_Accounts_Diagnostic => Acc_Diag);
                     end if;

                     return Project (Scope_State, Plans, Account_State);
                  end;
            end case;
      end case;
   end Project_From_Cycle;

end HRA.Household_Daily_Target_View;
