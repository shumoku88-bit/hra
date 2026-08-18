with ALedger.Account;
with ALedger.Budget_Source_Adapter;

package body ALedger.Household_Envelope_Observation is

   function Observe
     (Observed_Through : ALedger.Dates.Date;
      State            : ALedger.Household.Household_State;
      Result           : out Observation;
      Error_Msg        : out Unbounded_String) return Boolean
   is
      Plan_Diag        : ALedger.Plan_Observation.Admission_Diagnostic;
      Cycle_Status     : ALedger.Cycle_Observation.Resolve_Status;
      Fulfillment_Diag : ALedger.Envelope_Fulfillment.Observe_Diagnostic;
      Commit_Diag      : ALedger.Envelope_Commitment.Observe_Diagnostic;
      Income_Acc       : constant ALedger.Account.Account :=
        ALedger.Account.Make_Account
          (To_String (State.Household_Policy.Cycle_Income_Account));
   begin
      Result.Observed_Through := Observed_Through;
      Result.Open_Plans := ALedger.Plan_Observation.Open_Plan_Vectors.Empty_Vector;
      Result.Completed_Plans :=
        ALedger.Plan_Observation.Completed_Plan_Vectors.Empty_Vector;
      Result.Entitlement := ALedger.Envelope_Entitlement.Empty_Observation;
      Result.Consumption := ALedger.Envelope_Consumption.Empty_Consumption;
      Result.Envelope_Positions :=
        ALedger.Envelope_Position.Empty_Observation;

      if not ALedger.Plan_Observation.Observe_Plans
        (State.Plan_Ledger,
         State.Plan_Evidence,
         State.Actual_Ledger,
         State.Actual_Evidence,
         Observed_Through,
         Result.Open_Plans,
         Result.Completed_Plans,
         Plan_Diag)
      then
         Error_Msg := To_Unbounded_String
           ("Plan observation failed: " &
            ALedger.Plan_Observation.Admission_Status'Image
              (Plan_Diag.Status) &
            (if Length (Plan_Diag.Message) > 0
             then ": " & To_String (Plan_Diag.Message)
             else ""));
         return False;
      end if;

      if not ALedger.Cycle_Observation.Resolve_Current
        (Observed_Through,
         State.Actual_Ledger,
         Result.Open_Plans,
         State.Registry,
         Income_Acc,
         Result.Current_Cycle,
         Cycle_Status)
      then
         Error_Msg := To_Unbounded_String
           ("current cycle resolution failed: " &
            ALedger.Cycle_Observation.Resolve_Status'Image (Cycle_Status));
         return False;
      end if;

      declare
         Adapter_Diag : ALedger.Budget_Source_Adapter.Adapter_Diagnostic;
      begin
         if not ALedger.Budget_Source_Adapter.Observe_Entitlements
           (State.Budget_Ledger.Transactions,
            State.Household_Policy,
            State.Envelope_Registry,
            Observed_Through,
            Result.Entitlement,
            Adapter_Diag)
         then
            Error_Msg := To_Unbounded_String
              ("Budget source adapter failed: " &
               ALedger.Budget_Source_Adapter.Adapter_Status'Image
                 (Adapter_Diag.Status) &
               (if Length (Adapter_Diag.Message) > 0
                then ": " & To_String (Adapter_Diag.Message)
                else ""));
            return False;
         end if;
      end;

      Result.Consumption :=
        ALedger.Envelope_Consumption.Observe_Stock_Consumption
          (State.Actual_Ledger,
           State.Routing_History,
           Result.Entitlement,
           Observed_Through);

      if not ALedger.Envelope_Fulfillment.Observe_Stock
        (Result.Completed_Plans,
         State.Actual_Ledger,
         State.Registry,
         State.Fulfillment_History,
         Result.Entitlement,
         Observed_Through,
         Result.Fulfillment,
         Fulfillment_Diag)
      then
         Error_Msg := To_Unbounded_String
           ("Envelope fulfillment observation failed: " &
            ALedger.Envelope_Fulfillment.Observe_Status'Image
              (Fulfillment_Diag.Status) &
            (if Length (Fulfillment_Diag.Message) > 0
             then ": " & To_String (Fulfillment_Diag.Message)
             else ""));
         return False;
      end if;

      if not ALedger.Envelope_Commitment.Observe
        (Result.Open_Plans,
         State.Registry,
         State.Routing_History,
         State.Fulfillment_History,
         Result.Current_Cycle,
         Observed_Through,
         Result.Commitment,
         Commit_Diag)
      then
         Error_Msg := To_Unbounded_String
           ("Envelope commitment observation failed: " &
            ALedger.Envelope_Commitment.Observe_Status'Image
              (Commit_Diag.Status) &
            (if Length (Commit_Diag.Message) > 0
             then ": " & To_String (Commit_Diag.Message)
             else ""));
         return False;
      end if;

      declare
         Pos_Diag : ALedger.Envelope_Position.Observe_Diagnostic;
      begin
         if not ALedger.Envelope_Position.Observe
           (State.Budget_Policy,
            State.Envelope_Registry,
            Result.Entitlement,
            Result.Consumption,
            Result.Fulfillment,
            Result.Commitment,
            Result.Envelope_Positions,
            Pos_Diag)
         then
            Error_Msg := To_Unbounded_String
              ("Envelope position observation failed: " &
               ALedger.Envelope_Position.Observe_Status'Image (Pos_Diag.Status) &
               (if Length (Pos_Diag.Envelope_Id_Text) > 0
                then " [envelope=" & To_String (Pos_Diag.Envelope_Id_Text) & "]"
                else "") &
               (if Length (Pos_Diag.Commodity_Code) > 0
                then " [commodity=" & To_String (Pos_Diag.Commodity_Code) & "]"
                else "") &
               " [role=" & ALedger.Envelope_Position.Value_Role'Image (Pos_Diag.Role) & "]");
            return False;
         end if;
      end;

      Error_Msg := Null_Unbounded_String;
      return True;
   end Observe;

end ALedger.Household_Envelope_Observation;
