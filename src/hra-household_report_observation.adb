with HRA.Account;
with HRA.Cycle_Accounts_Observation;
with HRA.Envelope_Commitment;
with HRA.Envelope_Consumption;
with HRA.Envelope_Entitlement;
with HRA.Envelope_Position;
with HRA.Household_Daily_Target_View;
with HRA.Household_Envelope_Observation;
with HRA.Plan_Temporal_Observation;
with HRA.Report_Cycle_Accounts;
with HRA.Report_Flow;

package body HRA.Household_Report_Observation is

   Current_Section_Order : constant Current_Report_Section_Order :=
     [1  => Envelope_And_Backing_Section,
      2  => Cycle_Accounts_Section,
      3  => Daily_Target_Section,
      4  => Account_Balances_Section,
      5  => Balance_Sheet_Section,
      6  => Profit_And_Loss_Section,
      7  => Daily_Flow_Section,
      8  => Monthly_Accounts_Section,
      9  => Recent_Journal_Section,
      10 => Planned_Payments_Section,
      11 => Open_Issues_Section];

   function Observe
     (Observed_Through : HRA.Dates.Date;
      State            : HRA.Household.Household_State;
      Result           : out Report_Observation;
      Error_Msg        : out Unbounded_String) return Boolean
   is
      Report_Status : HRA.Report_Plan.Resolve_Status;
      Payment_Diag  : HRA.Planned_Payments.Projection_Diagnostic;
      Payment_Value : HRA.Planned_Payments.Observation;
      Flow_Diag     : HRA.Report_Flow.Observe_Diagnostic;
      Cycle_Status  : HRA.Cycle_Observation.Resolve_Status;
      Cycle_Context : HRA.Cycle_Observation.Observation;
      Cycle_Current : HRA.Cycle_Accounts_Observation.Observation;
      Cycle_Current_Diag : HRA.Cycle_Accounts_Observation.Observe_Diagnostic;
      Cycle_Comparison : HRA.Report_Cycle_Accounts.Cycle_Comparison_Observation;
      Cycle_Comparison_Diag : HRA.Report_Cycle_Accounts.Comparison_Diagnostic;
      Plan_Obs : constant HRA.Plan_Temporal_Observation.Observation :=
        HRA.Plan_Temporal_Observation.Observe
          (State.Plan_Journal, State.Plan_Completions, Observed_Through);
      Income_Acc : constant HRA.Account.Account :=
        HRA.Account.Make_Account
          (To_String (State.Household_Policy.Cycle_Income_Account));
      Envelope_Obs : HRA.Household_Envelope_Observation.Observation;
      Funding      : HRA.Backing_Policy.Funding_Commitment_Observation;
      Backing      : HRA.Backing_Policy.Backing_Observation;
      Output       : Report_Observation;

      function Build_Envelope_Report return Boolean is
         View : Envelope_Report_Observation;
      begin
         View.Observed_Through := Observed_Through;
         View.Current_Cycle := Envelope_Obs.Current_Cycle;
         View.Signed_Envelope_Total := Empty_Balance;
         View.Unallocated :=
           HRA.Envelope_Entitlement.Unallocated_Balance
             (Envelope_Obs.Entitlement);
         View.Total_Funding_Assets := Backing.Total_Assets;
         View.Backing_Status :=
           HRA.Backing_Policy.Backing_Condition_For (Backing);

         --  Current membership and order are admitted policy. Resolve stable
         --  identity once here; a renderer must never reconstruct it from text.
         for Definition of State.Envelope_Policy.Envelopes loop
            declare
               Id_Text : constant String := To_String (Definition.ID);
               Env_Id  : HRA.Envelope.Envelope_Id;
            begin
               if not HRA.Envelope.Lookup
                 (State.Envelope_Registry, Id_Text, Env_Id)
               then
                  Error_Msg := To_Unbounded_String
                    ("report Envelope identity is unavailable: " & Id_Text);
                  return False;
               elsif not HRA.Envelope_Position.Has_Explanation
                 (Envelope_Obs.Envelope_Positions, Env_Id)
               then
                  Error_Msg := To_Unbounded_String
                    ("report Envelope explanation is unavailable: " & Id_Text);
                  return False;
               end if;

               declare
                  Why : constant HRA.Envelope_Position.Explanation :=
                    HRA.Envelope_Position.Explain
                      (Envelope_Obs.Envelope_Positions, Env_Id);
               begin
                  View.Lines.Append
                    (Envelope_Report_Line'
                       (Env_Id                 => Env_Id,
                        Entitlement            => Why.Evidence.Entitlement,
                        Consumption_Charges    =>
                          Why.Evidence.Consumption_Charges,
                        Consumption_Refunds    =>
                          Why.Evidence.Consumption_Refunds,
                        Net_Consumption        => Why.Evidence.Net_Consumption,
                        Fulfillment_Applied    =>
                          Why.Evidence.Fulfillment_Applied,
                        Fulfillment_Reversed   =>
                          Why.Evidence.Fulfillment_Reversed,
                        Net_Fulfillment        => Why.Evidence.Net_Fulfillment,
                        Remaining              => Why.Observed_Position.Remaining,
                        Plan_Commitment        => Why.Evidence.Plan_Commitment,
                        Headroom               => Why.Observed_Position.Headroom));
                  View.Signed_Envelope_Total := Add_Balance
                    (View.Signed_Envelope_Total, Why.Evidence.Entitlement);
               end;
            end;
         end loop;

         for Cursor in Envelope_Obs.Consumption.Unmanaged.Iterate loop
            declare
               Name : constant String :=
                 HRA.Envelope_Consumption.Account_Amounts_Maps.Key (Cursor);
               Amounts : constant HRA.Envelope_Consumption.Consumption_Amounts :=
                 HRA.Envelope_Consumption.Account_Amounts_Maps.Element (Cursor);
            begin
               View.Unmanaged_Consumption.Append
                 (Account_Consumption_Line'
                    (Account_Name => To_Unbounded_String (Name),
                     Charges       => Amounts.Charges,
                     Refunds       => Amounts.Refunds,
                     Net           =>
                       HRA.Envelope_Consumption.Net_Consumption (Amounts)));
            end;
         end loop;

         for Cursor in Envelope_Obs.Consumption.Unrouted.Iterate loop
            declare
               Name : constant String :=
                 HRA.Envelope_Consumption.Account_Amounts_Maps.Key (Cursor);
               Amounts : constant HRA.Envelope_Consumption.Consumption_Amounts :=
                 HRA.Envelope_Consumption.Account_Amounts_Maps.Element (Cursor);
            begin
               View.Unrouted_Consumption.Append
                 (Account_Consumption_Line'
                    (Account_Name => To_Unbounded_String (Name),
                     Charges       => Amounts.Charges,
                     Refunds       => Amounts.Refunds,
                     Net           =>
                       HRA.Envelope_Consumption.Net_Consumption (Amounts)));
            end;
         end loop;

         for Cursor in Envelope_Obs.Commitment.Unmanaged.Iterate loop
            View.Unmanaged_Commitment.Append
              (Account_Commitment_Line'
                 (Account_Name => To_Unbounded_String
                    (HRA.Envelope_Commitment.Account_Balance_Maps.Key (Cursor)),
                  Commitment =>
                    HRA.Envelope_Commitment.Account_Balance_Maps.Element
                      (Cursor)));
         end loop;

         for Cursor in Envelope_Obs.Commitment.Unrouted.Iterate loop
            View.Unrouted_Commitment.Append
              (Account_Commitment_Line'
                 (Account_Name => To_Unbounded_String
                    (HRA.Envelope_Commitment.Account_Balance_Maps.Key (Cursor)),
                  Commitment =>
                    HRA.Envelope_Commitment.Account_Balance_Maps.Element
                      (Cursor)));
         end loop;

         for Cursor in Backing.Positions.Iterate loop
            declare
               Position : constant HRA.Backing_Policy.Backing_Pool_Position :=
                 HRA.Backing_Policy.Pool_Position_Maps.Element (Cursor);
               Gross : constant Balance :=
                 HRA.Backing_Policy.Gross_Surplus (Position);
            begin
               View.Backing_Lines.Append
                 (Backing_Report_Line'
                    (Pool_Id                     => Position.Pool_Id,
                     Funding_Balance             => Position.Funding_Balance,
                     Funding_Commitment          => Position.Funding_Commitment,
                     Available_Funding           =>
                       HRA.Backing_Policy.Available_Funding (Position),
                     Gross_Envelope_Required     =>
                       Position.Gross_Envelope_Required,
                     Available_Envelope_Required =>
                       Position.Available_Envelope_Required,
                     Gross_Surplus               => Gross,
                     Available_Surplus           =>
                       HRA.Backing_Policy.Available_Surplus (Position)));
            end;
         end loop;

         Output.Envelope_Report := View;
         return True;
      end Build_Envelope_Report;

   begin
      --  Resolve the Household cycle context once for this report composition.
      --  The Plan temporal observer consumes admitted Plan authorities; it does
      --  not reparse source text or create a second Plan authority.
      if not HRA.Cycle_Observation.Observe
        (Observed_Through,
         State.Actual_Ledger,
         Plan_Obs.Open_Plans,
         State.Registry,
         Income_Acc,
         Cycle_Context,
         Cycle_Status)
      then
         Error_Msg := To_Unbounded_String
           ("report cycle context failed: " &
            HRA.Cycle_Observation.Resolve_Status'Image (Cycle_Status));
         return False;
      end if;

      --  Envelope composition receives the already resolved current window.
      --  This keeps Cycle Accounts and Envelope on exactly one temporal axis.
      if not HRA.Household_Envelope_Observation.Observe_In_Window
        (Observed_Through,
         Cycle_Context.Current_Window,
         State,
         Envelope_Obs,
         Error_Msg)
      then
         return False;
      end if;

      Output.Observed_Through := Envelope_Obs.Observed_Through;
      Output.Section_Order := Current_Section_Order;

      if not HRA.Cycle_Accounts_Observation.Observe
        (State.Actual_Ledger,
         Cycle_Context.Current_Window,
         Observed_Through,
         Cycle_Current,
         Cycle_Current_Diag)
      then
         Error_Msg := To_Unbounded_String
           ("current Cycle Accounts observation failed: " &
            HRA.Cycle_Accounts_Observation.Observe_Status'Image
              (Cycle_Current_Diag.Status) &
            (if Length (Cycle_Current_Diag.Account_Name) > 0
             then " [account=" & To_String (Cycle_Current_Diag.Account_Name) & "]"
             else "") &
            (if Length (Cycle_Current_Diag.Message) > 0
             then ": " & To_String (Cycle_Current_Diag.Message)
             else ""));
         return False;
      end if;

      if HRA.Report_Cycle_Accounts.Observe_Aligned
        (State.Actual_Ledger,
         Cycle_Context.Previous_Window,
         Cycle_Current,
         Cycle_Comparison,
         Cycle_Comparison_Diag)
      then
         Output.Cycle_Accounts :=
           (Current    => Cycle_Current,
            Comparison =>
              (Status => HRA.Report_Cycle_Accounts.Comparison_Available,
               Value  => Cycle_Comparison));
      else
         Output.Cycle_Accounts :=
           (Current    => Cycle_Current,
            Comparison =>
              (Status     => HRA.Report_Cycle_Accounts.Comparison_Unavailable,
               Diagnostic => Cycle_Comparison_Diag));
      end if;

      Output.Daily_Target := HRA.Household_Daily_Target_View.Project
        (Scope_State   => State.Daily_Target,
         Plans         => Plan_Obs,
         Account_State => Cycle_Current);

      --  Report policy is resolved exactly once. Configurable bounded sections
      --  consume coordinates from this resolved plan. Cycle Accounts does not
      --  invent a second report range; its coordinate is Household cycle evidence.
      if not HRA.Report_Plan.Resolve_With_Current_Cycle
        (Observed_Through,
         State.Actual_Ledger,
         Cycle_Context.Current_Window,
         State.Report_Policy.Plan,
         Output.Query_Plan,
         Report_Status)
      then
         Error_Msg := To_Unbounded_String
           ("report query resolution failed: " &
            HRA.Report_Plan.Resolve_Status'Image (Report_Status));
         return False;
      end if;

      Output.Account_Balances.As_Of :=
        Output.Query_Plan.Trial_Balance_As_Of;
      Output.Account_Balances.Value := HRA.Report.Generate_Trial_Balance_As_Of
        (State.Actual_Ledger, Output.Account_Balances.As_Of);
      for Line of Output.Account_Balances.Value.Lines loop
         if not Is_Zero_Balance (Line.Bal) then
            Output.Account_Balances.Display_Lines.Append (Line);
         end if;
      end loop;
      Output.Balance_Sheet.As_Of := Output.Query_Plan.Balance_Sheet_As_Of;
      Output.Balance_Sheet.Value := HRA.Report.Generate_Balance_Sheet_As_Of
        (State.Actual_Ledger, Output.Balance_Sheet.As_Of);
      Output.Profit_And_Loss.Period := Output.Query_Plan.Profit_And_Loss;
      Output.Profit_And_Loss.Value := HRA.Report.Generate_Profit_And_Loss_Period
        (State.Actual_Ledger, Output.Profit_And_Loss.Period);

      --  Daily Flow and Monthly Accounts share one typed aggregation owner and
      --  consume their independently resolved periods from the same report plan.
      if not HRA.Report_Flow.Observe
        (State.Actual_Ledger,
         Output.Query_Plan.Daily_Flow,
         Output.Query_Plan.Monthly_Accounts,
         Output.Daily_Flow,
         Output.Monthly_Accounts,
         Flow_Diag)
      then
         Error_Msg := To_Unbounded_String
           ("report flow observation failed: " &
            HRA.Report_Flow.Observe_Status'Image (Flow_Diag.Status) &
            (if Length (Flow_Diag.Account_Name) > 0
             then " [account=" & To_String (Flow_Diag.Account_Name) & "]"
             else "") &
            (if Length (Flow_Diag.Message) > 0
             then ": " & To_String (Flow_Diag.Message)
             else ""));
         return False;
      end if;

      Output.Recent_Journal := HRA.Recent_Journal.Observe
        (State.Actual_Identity,
         Output.Query_Plan.Recent_Transactions_Through,
         Output.Query_Plan.Recent_Transactions_Count);

      if HRA.Planned_Payments.Project
        (Envelope_Obs.Open_Plans,
         State.Registry,
         Observed_Through,
         Payment_Value,
         Payment_Diag)
      then
         Output.Planned_Payments :=
           (Status => Available,
            Value  => Payment_Value);
      else
         Output.Planned_Payments :=
           (Status     => Unavailable,
            Diagnostic => Payment_Diag);
      end if;

      Output.Open_Issues.Open_Items := HRA.Issues.Open_Issues (State.Issues);
      Output.Open_Issues.Total_Count := HRA.Issues.Count (State.Issues);
      Output.Open_Issues.Resolved_Count :=
        Output.Open_Issues.Total_Count -
        HRA.Issues.Count (Output.Open_Issues.Open_Items);

      Funding := HRA.Backing_Policy.Observe_Funding_Commitment
        (State.Backing_Policy_Spec,
         Envelope_Obs.Open_Plans,
         Cycle_Context.Current_Window);

      Backing := HRA.Backing_Policy.Observe_Backing
        (State.Backing_Policy_Spec,
         State.Actual_Ledger,
         Observed_Through,
         Envelope_Obs.Envelope_Positions,
         Funding);

      if not Build_Envelope_Report then
         return False;
      end if;

      Result := Output;
      Error_Msg := Null_Unbounded_String;
      return True;
   end Observe;

end HRA.Household_Report_Observation;
