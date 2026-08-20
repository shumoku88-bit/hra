with HRA.Account;
with HRA.Entitlement_Journal;

package body HRA.Household_Envelope_Observation is

   function Observe_Plans_At
     (Observed_Through : HRA.Dates.Date;
      State            : HRA.Household.Household_State;
      Open_Plans       : out HRA.Plan_Observation.Open_Plan_Vectors.Vector;
      Completed_Plans  : out HRA.Plan_Observation.Completed_Plan_Vectors.Vector;
      Error_Msg        : out Unbounded_String) return Boolean
   is
      Plan_Diag : HRA.Plan_Observation.Admission_Diagnostic;
   begin
      Open_Plans := HRA.Plan_Observation.Open_Plan_Vectors.Empty_Vector;
      Completed_Plans :=
        HRA.Plan_Observation.Completed_Plan_Vectors.Empty_Vector;

      if not HRA.Plan_Observation.Observe_Plans
        (State.Plan_Ledger,
         State.Plan_Evidence,
         State.Actual_Ledger,
         State.Actual_Evidence,
         Observed_Through,
         Open_Plans,
         Completed_Plans,
         Plan_Diag)
      then
         Error_Msg := To_Unbounded_String
           ("Plan observation failed: " &
            HRA.Plan_Observation.Admission_Status'Image
              (Plan_Diag.Status) &
            (if Length (Plan_Diag.Message) > 0
             then ": " & To_String (Plan_Diag.Message)
             else ""));
         return False;
      end if;

      Error_Msg := Null_Unbounded_String;
      return True;
   end Observe_Plans_At;

   function Compose
     (Observed_Through : HRA.Dates.Date;
      Window           : HRA.Cycle_Observation.Cycle_Window;
      State            : HRA.Household.Household_State;
      Open_Plans       : HRA.Plan_Observation.Open_Plan_Vectors.Vector;
      Completed_Plans  : HRA.Plan_Observation.Completed_Plan_Vectors.Vector;
      Result           : out Observation;
      Error_Msg        : out Unbounded_String) return Boolean
   is
      Fulfillment_Diag : HRA.Envelope_Fulfillment.Observe_Diagnostic;
      Commit_Diag      : HRA.Envelope_Commitment.Observe_Diagnostic;
   begin
      Result.Observed_Through := Observed_Through;
      Result.Open_Plans := Open_Plans;
      Result.Completed_Plans := Completed_Plans;
      Result.Current_Cycle := Window;
      Result.Entitlement :=
        HRA.Entitlement_Journal.Observe
          (State.Entitlement_History, Observed_Through);
      Result.Consumption := HRA.Envelope_Consumption.Empty_Consumption;
      Result.Fulfillment :=
        HRA.Envelope_Fulfillment.Empty_Fulfillment (Observed_Through);
      Result.Commitment := HRA.Envelope_Commitment.Empty_Observation
        (Observed_Through, HRA.Cycle_Observation.End_Exclusive (Window));
      Result.Envelope_Positions :=
        HRA.Envelope_Position.Empty_Observation;

      Result.Consumption :=
        HRA.Envelope_Consumption.Observe_Stock_Consumption
          (State.Actual_Ledger,
           State.Routing_History,
           Result.Entitlement,
           Observed_Through);

      if not HRA.Envelope_Fulfillment.Observe_Stock
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
            HRA.Envelope_Fulfillment.Observe_Status'Image
              (Fulfillment_Diag.Status) &
            (if Length (Fulfillment_Diag.Message) > 0
             then ": " & To_String (Fulfillment_Diag.Message)
             else ""));
         return False;
      end if;

      if not HRA.Envelope_Commitment.Observe
        (Result.Open_Plans,
         State.Registry,
         State.Routing_History,
         State.Fulfillment_History,
         Window,
         Observed_Through,
         Result.Commitment,
         Commit_Diag)
      then
         Error_Msg := To_Unbounded_String
           ("Envelope commitment observation failed: " &
            HRA.Envelope_Commitment.Observe_Status'Image
              (Commit_Diag.Status) &
            (if Length (Commit_Diag.Message) > 0
             then ": " & To_String (Commit_Diag.Message)
             else ""));
         return False;
      end if;

      declare
         Pos_Diag : HRA.Envelope_Position.Observe_Diagnostic;
      begin
         if not HRA.Envelope_Position.Observe
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
               HRA.Envelope_Position.Observe_Status'Image (Pos_Diag.Status) &
               (if Length (Pos_Diag.Envelope_Id_Text) > 0
                then " [envelope=" & To_String (Pos_Diag.Envelope_Id_Text) & "]"
                else "") &
               (if Length (Pos_Diag.Commodity_Code) > 0
                then " [commodity=" & To_String (Pos_Diag.Commodity_Code) & "]"
                else "") &
               " [role=" & HRA.Envelope_Position.Value_Role'Image (Pos_Diag.Role) & "]");
            return False;
         end if;
      end;

      Error_Msg := Null_Unbounded_String;
      return True;
   end Compose;

   function Observe
     (Observed_Through : HRA.Dates.Date;
      State            : HRA.Household.Household_State;
      Result           : out Observation;
      Error_Msg        : out Unbounded_String) return Boolean
   is
      Open_Plans      : HRA.Plan_Observation.Open_Plan_Vectors.Vector;
      Completed_Plans : HRA.Plan_Observation.Completed_Plan_Vectors.Vector;
      Window          : HRA.Cycle_Observation.Cycle_Window;
      Cycle_Status    : HRA.Cycle_Observation.Resolve_Status;
      Income_Acc      : constant HRA.Account.Account :=
        HRA.Account.Make_Account
          (To_String (State.Household_Policy.Cycle_Income_Account));
   begin
      if not Observe_Plans_At
        (Observed_Through,
         State,
         Open_Plans,
         Completed_Plans,
         Error_Msg)
      then
         return False;
      end if;

      if not HRA.Cycle_Observation.Resolve_Current
        (Observed_Through,
         State.Actual_Ledger,
         Open_Plans,
         State.Registry,
         Income_Acc,
         Window,
         Cycle_Status)
      then
         Error_Msg := To_Unbounded_String
           ("current cycle resolution failed: " &
            HRA.Cycle_Observation.Resolve_Status'Image (Cycle_Status));
         return False;
      end if;

      return Compose
        (Observed_Through,
         Window,
         State,
         Open_Plans,
         Completed_Plans,
         Result,
         Error_Msg);
   end Observe;

   function Observe_In_Window
     (Observed_Through : HRA.Dates.Date;
      Window           : HRA.Cycle_Observation.Cycle_Window;
      State            : HRA.Household.Household_State;
      Result           : out Observation;
      Error_Msg        : out Unbounded_String) return Boolean
   is
      Open_Plans      : HRA.Plan_Observation.Open_Plan_Vectors.Vector;
      Completed_Plans : HRA.Plan_Observation.Completed_Plan_Vectors.Vector;
   begin
      if not HRA.Cycle_Observation.Contains (Window, Observed_Through) then
         Error_Msg := To_Unbounded_String
           ("explicit Envelope observation day " & HRA.Dates.Image (Observed_Through) &
            " is outside supplied cycle " &
            HRA.Dates.Image (HRA.Cycle_Observation.Start_Date (Window)) & ".." &
            HRA.Dates.Image (HRA.Cycle_Observation.End_Exclusive (Window)));
         return False;
      end if;

      if not Observe_Plans_At
        (Observed_Through,
         State,
         Open_Plans,
         Completed_Plans,
         Error_Msg)
      then
         return False;
      end if;

      return Compose
        (Observed_Through,
         Window,
         State,
         Open_Plans,
         Completed_Plans,
         Result,
         Error_Msg);
   end Observe_In_Window;

end HRA.Household_Envelope_Observation;
