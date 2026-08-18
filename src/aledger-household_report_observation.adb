with ALedger.Household_Envelope_Observation;

package body ALedger.Household_Report_Observation is

   function Observe
     (Observed_Through : ALedger.Dates.Date;
      State            : ALedger.Household.Household_State;
      Result           : out Report_Observation;
      Error_Msg        : out Unbounded_String) return Boolean
   is
      Report_Status : ALedger.Report_Plan.Resolve_Status;
      Recent_Status : ALedger.Recent_Journal.Observe_Status;
      Envelope_Obs  : ALedger.Household_Envelope_Observation.Observation;
   begin
      if not ALedger.Household_Envelope_Observation.Observe
        (Observed_Through, State, Envelope_Obs, Error_Msg)
      then
         return False;
      end if;

      Result.Observed_Through := Envelope_Obs.Observed_Through;
      Result.Open_Plans := Envelope_Obs.Open_Plans;
      Result.Completed_Plans := Envelope_Obs.Completed_Plans;
      Result.Current_Cycle := Envelope_Obs.Current_Cycle;
      Result.Entitlement := Envelope_Obs.Entitlement;
      Result.Consumption := Envelope_Obs.Consumption;
      Result.Fulfillment := Envelope_Obs.Fulfillment;
      Result.Commitment := Envelope_Obs.Commitment;
      Result.Envelope_Positions := Envelope_Obs.Envelope_Positions;

      if not ALedger.Report_Plan.Resolve_With_Current_Cycle
        (Observed_Through,
         State.Actual_Ledger,
         Result.Current_Cycle,
         State.Report_Policy.Plan,
         Result.Query_Plan,
         Report_Status)
      then
         Error_Msg := To_Unbounded_String
           ("report query resolution failed: " &
            ALedger.Report_Plan.Resolve_Status'Image (Report_Status));
         return False;
      end if;

      if not ALedger.Recent_Journal.Observe
        (State.Actual_Ledger,
         State.Actual_Evidence,
         Result.Query_Plan.Recent_Transactions_Through,
         Result.Query_Plan.Recent_Transactions_Count,
         Result.Recent_Journal,
         Recent_Status)
      then
         Error_Msg := To_Unbounded_String
           ("Recent Journal observation failed: " &
            ALedger.Recent_Journal.Observe_Status'Image (Recent_Status));
         return False;
      end if;

      Result.Funding_Commitment :=
        ALedger.Backing_Policy.Observe_Funding_Commitment
          (State.Backing_Policy_Spec,
           Result.Open_Plans,
           Result.Current_Cycle);

      Result.Backing :=
        ALedger.Backing_Policy.Observe_Backing
          (State.Backing_Policy_Spec,
           State.Actual_Ledger,
           Observed_Through,
           Result.Envelope_Positions,
           Result.Funding_Commitment);

      Error_Msg := Null_Unbounded_String;
      return True;
   end Observe;

end ALedger.Household_Report_Observation;
