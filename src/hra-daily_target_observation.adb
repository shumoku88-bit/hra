with HRA.Account;
with HRA.Plan;

package body HRA.Daily_Target_Observation is

   use type HRA.Account.Account;
   use type HRA.Dates.Date;
   use type HRA.Plan.Plan_Id;

   function Observe
     (Scope         : HRA.Daily_Target_Scope.Scope;
      Plans         : HRA.Plan_Temporal_Observation.Observation;
      Account_State : HRA.Cycle_Accounts_Observation.Observation;
      Result        : out Observation;
      Diag          : out Observe_Diagnostic) return Boolean
   is
      Eligible_Total : HRA.Money.Balance := HRA.Money.Empty_Balance;
      Obligation_Total : HRA.Money.Balance := HRA.Money.Empty_Balance;
      Excluded_Total : HRA.Money.Balance := HRA.Money.Empty_Balance;
   begin
      Result :=
        (Configured_Value       => HRA.Daily_Target_Scope.Is_Configured (Scope),
         Observed_Through_Value => Account_State.Observed_Through,
         Window_Value           => Account_State.Window,
         Eligible_Assets_Value  => HRA.Money.Empty_Balance,
         Open_Obligations_Value => HRA.Money.Empty_Balance,
         Already_Excluded_Value => HRA.Money.Empty_Balance);
      Diag :=
        (Status       => Success,
         Account_Name => Null_Unbounded_String,
         Message      => Null_Unbounded_String);

      if Plans.Observed_Through /= Account_State.Observed_Through then
         Diag.Status := Observation_Date_Mismatch;
         Diag.Message := To_Unbounded_String
           ("Plan and Account observations describe different days");
         return False;
      end if;

      if not HRA.Cycle_Observation.Contains
        (Account_State.Window, Account_State.Observed_Through)
      then
         Diag.Status := Account_Observation_Outside_Cycle;
         Diag.Message := To_Unbounded_String
           ("Account observation day is outside its typed cycle");
         return False;
      end if;

      for I in 1 .. HRA.Daily_Target_Scope.Eligible_Asset_Count (Scope) loop
         declare
            Asset : constant HRA.Account.Account :=
              HRA.Daily_Target_Scope.Eligible_Asset_At (Scope, I);
            Match_Count  : Natural := 0;
            Closing_Value : HRA.Money.Balance := HRA.Money.Empty_Balance;
         begin
            for Row of Account_State.Rows loop
               if Row.Acc = Asset then
                  Match_Count := Match_Count + 1;
                  Closing_Value := HRA.Cycle_Accounts_Observation.Closing (Row);
               end if;
            end loop;

            if Match_Count = 0 then
               Diag.Status := Eligible_Asset_Missing_From_Account_State;
               Diag.Account_Name := To_Unbounded_String (HRA.Account.Name (Asset));
               Diag.Message := To_Unbounded_String
                 ("eligible Asset is absent from current Account state");
               return False;
            elsif Match_Count > 1 then
               Diag.Status := Duplicate_Eligible_Asset_Row;
               Diag.Account_Name := To_Unbounded_String (HRA.Account.Name (Asset));
               Diag.Message := To_Unbounded_String
                 ("eligible Asset appears more than once in current Account state");
               return False;
            end if;

            Eligible_Total := HRA.Money.Add_Balance
              (Eligible_Total, Closing_Value);
         end;
      end loop;

      for I in 1 .. HRA.Daily_Target_Scope.Obligation_Count (Scope) loop
         declare
            Obligation : constant HRA.Daily_Target_Scope.Obligation :=
              HRA.Daily_Target_Scope.Obligation_At (Scope, I);
            Open_In_Current_Cycle : Boolean := False;
         begin
            for Open_Plan of Plans.Open_Plans loop
               if Open_Plan.ID = Obligation.Plan_ID
                 and then HRA.Cycle_Observation.Contains
                   (Account_State.Window, Open_Plan.Tx.Date)
               then
                  Open_In_Current_Cycle := True;
                  exit;
               end if;
            end loop;

            if Open_In_Current_Cycle then
               Obligation_Total := HRA.Money.Add_Balance
                 (Obligation_Total,
                  HRA.Money.Singleton_Balance (Obligation.Amount));

               if Obligation.Reservation.Present then
                  Excluded_Total := HRA.Money.Add_Balance
                    (Excluded_Total,
                     HRA.Money.Singleton_Balance
                       (Obligation.Reservation.Value.Amount));
               end if;
            end if;
         end;
      end loop;

      Result.Eligible_Assets_Value := Eligible_Total;
      Result.Open_Obligations_Value := Obligation_Total;
      Result.Already_Excluded_Value := Excluded_Total;
      return True;
   end Observe;

end HRA.Daily_Target_Observation;
