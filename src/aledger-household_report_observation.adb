with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with ALedger.Account;
with ALedger.Canonical_Source;

package body ALedger.Household_Report_Observation is

   function Observe
     (Observed_Through : String;
      State            : ALedger.Household.Household_State;
      Result           : out Report_Observation;
      Error_Msg        : out Unbounded_String) return Boolean
   is
      Plan_Diag    : ALedger.Plan_Observation.Admission_Diagnostic;
      Cycle_Status : ALedger.Cycle_Observation.Resolve_Status;
      Commit_Diag  : ALedger.Envelope_Commitment.Observe_Diagnostic;
      Income_Acc   : constant ALedger.Account.Account :=
        ALedger.Account.Make_Account
          (To_String (State.Household_Policy.Cycle_Income_Account));
   begin
      Result.Observed_Through := To_Unbounded_String (Observed_Through);
      Result.Open_Plans := ALedger.Plan_Observation.Open_Plan_Vectors.Empty_Vector;
      Result.Consumption := ALedger.Envelope_Consumption.Empty_Consumption;
      Result.Commitment := ALedger.Envelope_Commitment.Empty_Observation;
      Result.Funding_Commitment :=
        ALedger.Backing_Policy.Empty_Funding_Commitment;

      if not ALedger.Plan_Observation.Observe_Open_Plans
        (State.Plan_Ledger,
         ALedger.Canonical_Source.Text_For
           (State.Sources, ALedger.Canonical_Source.Plan_Source),
         State.Actual_Ledger,
         ALedger.Canonical_Source.Text_For
           (State.Sources, ALedger.Canonical_Source.Actual_Source),
         Observed_Through,
         Result.Open_Plans,
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

      Result.Consumption :=
        ALedger.Envelope_Consumption.Observe_Consumption
          (State.Actual_Ledger,
           State.Routing_History,
           Observed_Through);

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

      Result.Funding_Commitment :=
        ALedger.Backing_Policy.Observe_Funding_Commitment
          (State.Backing_Policy_Spec,
           Result.Open_Plans,
           Result.Current_Cycle);

      Result.Backing :=
        ALedger.Backing_Policy.Observe_Backing
          (State.Backing_Policy_Spec,
           State.Actual_Ledger,
           State.Entitlement,
           Result.Consumption,
           Result.Commitment,
           Result.Funding_Commitment);

      Error_Msg := Null_Unbounded_String;
      return True;
   end Observe;

end ALedger.Household_Report_Observation;
