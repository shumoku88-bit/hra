with Ada.Text_IO; use Ada.Text_IO;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA.Account;
with HRA.Backing_Policy;
with HRA.Budget_Config;
with HRA.Config_Support;
with HRA.Cycle_Observation;
with HRA.Dates;
with HRA.Envelope;
with HRA.Envelope_Commitment;
with HRA.Envelope_Consumption;
with HRA.Envelope_Entitlement;
with HRA.Envelope_Fulfillment;
with HRA.Envelope_Position;
with HRA.Envelope_Routing;
with HRA.Fulfillment_Routing;
with HRA.Journal;
with HRA.Ledger;
with HRA.Money;
with HRA.Plan;
with HRA.Plan_Observation;

procedure Test_Envelope_Fulfillment is
   use type HRA.Backing_Policy.Policy_Status;
   use type HRA.Fulfillment_Routing.Admission_Status;
   use type HRA.Money.Quantity;

   Passed_Count : Natural := 0;
   Failed_Count : Natural := 0;

   procedure Assert (Condition : Boolean; Test_Name : String) is
   begin
      if Condition then
         Put_Line ("[PASS] " & Test_Name);
         Passed_Count := Passed_Count + 1;
      else
         Put_Line ("[FAIL] " & Test_Name);
         Failed_Count := Failed_Count + 1;
      end if;
   end Assert;

   function D (S : String) return HRA.Dates.Date is
      Val    : HRA.Dates.Date;
      Status : HRA.Dates.Date_Status;
   begin
      if not HRA.Dates.Parse (S, Val, Status) then
         raise Program_Error with "Invalid date in test: " & S;
      end if;
      return Val;
   end D;

   function H (S1, S2 : String) return HRA.Dates.Half_Open_Period is
      Res : HRA.Dates.Half_Open_Period;
   begin
      if not HRA.Dates.Make_Half_Open_Period (D (S1), D (S2), Res) then
         raise Program_Error with "Invalid half-open period: [" & S1 & ", " & S2 & ")";
      end if;
      return Res;
   end H;

   procedure Register
     (Registry : in out HRA.Account.Account_Registry;
      Name     : String;
      Kind     : HRA.Account.Account_Type)
   is
      Status : HRA.Account.Registry_Status;
   begin
      if not HRA.Account.Register_Account
        (Registry,
         HRA.Account.Declare_Account
           (HRA.Account.Make_Account (Name), Kind),
         Status)
      then
         raise Program_Error with "test registry admission failed: " & Name;
      end if;
   end Register;

   Plan_Source : constant String :=
     "2026-08-20 Save" & ASCII.LF &
     "    ; plan-id: plan-save" & ASCII.LF &
     "    assets:savings      500 JPY" & ASCII.LF &
     "    assets:cash        -500 JPY" & ASCII.LF & ASCII.LF &
     "2026-08-21 Same Account, different intent" & ASCII.LF &
     "    ; plan-id: plan-unrelated" & ASCII.LF &
     "    assets:savings      300 JPY" & ASCII.LF &
     "    assets:cash        -300 JPY" & ASCII.LF & ASCII.LF &
     "2026-08-22 Food" & ASCII.LF &
     "    ; plan-id: plan-food" & ASCII.LF &
     "    expenses:food        75 JPY" & ASCII.LF &
     "    assets:cash          -75 JPY" & ASCII.LF;

   Actual_Source : constant String :=
     "2026-08-16 Save [event-id: act-save]" & ASCII.LF &
     "    ; plan-id: plan-save" & ASCII.LF &
     "    assets:savings      450 JPY" & ASCII.LF &
     "    assets:cash        -450 JPY" & ASCII.LF & ASCII.LF &
     "2026-08-16 Same Account transfer [event-id: act-unrelated]" & ASCII.LF &
     "    ; plan-id: plan-unrelated" & ASCII.LF &
     "    assets:savings      300 JPY" & ASCII.LF &
     "    assets:cash        -300 JPY" & ASCII.LF & ASCII.LF &
     "2026-08-16 Food [event-id: act-food]" & ASCII.LF &
     "    ; plan-id: plan-food" & ASCII.LF &
     "    expenses:food        70 JPY" & ASCII.LF &
     "    assets:cash          -70 JPY" & ASCII.LF & ASCII.LF &
     "2026-08-17 Undo save [event-id: rev-save] [reverses: act-save]" & ASCII.LF &
     "    assets:savings     -450 JPY" & ASCII.LF &
     "    assets:cash         450 JPY" & ASCII.LF & ASCII.LF &
     "2026-08-18 Restore save [event-id: rev2-save] [reverses: rev-save]" & ASCII.LF &
     "    assets:savings      450 JPY" & ASCII.LF &
     "    assets:cash        -450 JPY" & ASCII.LF;

   Budget_TOML : constant String :=
     "[[backing-pools]]" & ASCII.LF &
     "id = ""liquid""" & ASCII.LF &
     "asset-accounts = [""assets:cash""]" & ASCII.LF &
     "[[envelopes]]" & ASCII.LF &
     "id = ""savings""" & ASCII.LF &
     "label = ""Savings""" & ASCII.LF &
     "pacing = ""daily""" & ASCII.LF &
     "backing-pool = ""liquid""" & ASCII.LF;

   Registry       : HRA.Account.Account_Registry := HRA.Account.Empty_Registry;
   Plans          : HRA.Ledger.Ledger;
   Actual         : HRA.Ledger.Ledger;
   Parse_Error    : Unbounded_String;
   Open_Plans     : HRA.Plan_Observation.Open_Plan_Vectors.Vector;
   Completed      : HRA.Plan_Observation.Completed_Plan_Vectors.Vector;
   Plan_Diag      : HRA.Plan_Observation.Admission_Diagnostic;
   Known_Plans    : HRA.Plan.Plan_Id_Universe;
   Env_Names      : HRA.Config_Support.String_Vectors.Vector;
   Env_Registry   : HRA.Envelope.Envelope_Registry;
   Env_Diag       : HRA.Config_Support.Config_Diagnostic;
   Savings_Env    : HRA.Envelope.Envelope_Id;
   Decisions      : HRA.Fulfillment_Routing.Decision_Vectors.Vector;
   Routing        : HRA.Fulfillment_Routing.Fulfillment_Routing_History;
   Routing_Status : HRA.Fulfillment_Routing.Admission_Status;
   Fulfillment    : HRA.Envelope_Fulfillment.Envelope_Fulfillment;
   Fulfill_Diag   : HRA.Envelope_Fulfillment.Observe_Diagnostic;
   JPY            : constant HRA.Money.Commodity :=
     HRA.Money.Make_Commodity ("JPY");

begin
   Put_Line ("--- Testing HRA.Envelope_Fulfillment ---");

   Register (Registry, "assets:cash", HRA.Account.Asset);
   Register (Registry, "assets:savings", HRA.Account.Asset);
   Register (Registry, "expenses:food", HRA.Account.Expense);

   Assert
     (HRA.Journal.Parse_Journal_Text (Plan_Source, Plans, Parse_Error),
      "Setup: parse role-neutral Plan journal");
   Assert
     (HRA.Journal.Parse_Journal_Text (Actual_Source, Actual, Parse_Error),
      "Setup: parse explicit completion and reversal chain");

   Assert
     (HRA.Plan_Observation.Observe_Plans
        (Plans, Plan_Source, Actual, Actual_Source,
         D ("2026-08-18"), Open_Plans, Completed, Plan_Diag),
      "Observe open/completed Plan lifecycle once");
   Assert
     (Natural (Open_Plans.Length) = 0
        and then Natural (Completed.Length) = 3,
      "Explicit Actual plan-id moves completed Plans out of open Commitment set");

   Assert
     (HRA.Plan_Observation.Admit_Plan_Identities
        (Plans, Plan_Source, Known_Plans, Plan_Diag),
      "Admit stable Plan identity universe");

   Env_Names.Append ("savings");
   Assert
     (HRA.Envelope.Admit_Registry
        (Env_Names, Env_Registry, Env_Diag),
      "Admit stable Envelope registry");
   Assert
     (HRA.Envelope.Lookup (Env_Registry, "savings", Savings_Env),
      "Lookup savings Envelope");

   Decisions.Append
     (HRA.Fulfillment_Routing.Fulfillment_Routing_Decision'
        (Effective_From => D ("2026-08-01"),
         Plan_ID        => HRA.Plan.Make_Plan_Id ("plan-save"),
         Route          => HRA.Fulfillment_Routing.Fulfills (Savings_Env),
         Note           => To_Unbounded_String ("save Plan fulfills savings")));
   Decisions.Append
     (HRA.Fulfillment_Routing.Fulfillment_Routing_Decision'
        (Effective_From => D ("2026-09-01"),
         Plan_ID        => HRA.Plan.Make_Plan_Id ("plan-save"),
         Route          => HRA.Fulfillment_Routing.Not_Target,
         Note           => To_Unbounded_String ("future intent change")));
   Decisions.Append
     (HRA.Fulfillment_Routing.Fulfillment_Routing_Decision'
        (Effective_From => D ("2026-08-01"),
         Plan_ID        => HRA.Plan.Make_Plan_Id ("plan-food"),
         Route          => HRA.Fulfillment_Routing.Fulfills (Savings_Env),
         Note           => To_Unbounded_String ("must not steal Expense ownership")));

   Assert
     (HRA.Fulfillment_Routing.Admit
        (Decisions, Known_Plans, Env_Registry, Routing, Routing_Status)
        and then Routing_Status = HRA.Fulfillment_Routing.Success,
      "Admit completion-day Fulfillment routing history");

   Assert
     (HRA.Envelope_Fulfillment.Observe
        (Completed, Actual, Registry, Routing, D ("2026-08-16"),
         Fulfillment, Fulfill_Diag),
      "Observe root completed Actual Fulfillment");
   declare
      Amounts : constant HRA.Envelope_Fulfillment.Fulfillment_Amounts :=
        HRA.Envelope_Fulfillment.Fulfillment_For
          (Fulfillment, Savings_Env);
   begin
      Assert
        (HRA.Money.Lookup_Balance (Amounts.Applied, JPY) = 450.0
           and then HRA.Money.Lookup_Balance (Amounts.Reversed, JPY) = 0.0,
         "Actual quantity, not planned quantity, is authoritative");
      Assert
        (Natural (Fulfillment.Evidence.Length) = 1,
         "same Account unrelated Plan and Expense Plan inherit no Fulfillment meaning");
   end;

   Assert
     (HRA.Envelope_Fulfillment.Observe
        (Completed, Actual, Registry, Routing, D ("2026-08-17"),
         Fulfillment, Fulfill_Diag),
      "Observe explicit reversal of Fulfillment");
   Assert
     (HRA.Money.Lookup_Balance
        (HRA.Envelope_Fulfillment.Net_For (Fulfillment, Savings_Env), JPY)
        = 0.0,
      "reversal removes the root Fulfillment effect");

   Assert
     (HRA.Envelope_Fulfillment.Observe
        (Completed, Actual, Registry, Routing, D ("2026-09-02"),
         Fulfillment, Fulfill_Diag),
      "Observe reversal-of-reversal after later routing change");
   declare
      Amounts : constant HRA.Envelope_Fulfillment.Fulfillment_Amounts :=
        HRA.Envelope_Fulfillment.Fulfillment_For
          (Fulfillment, Savings_Env);
      Evidence : constant HRA.Envelope_Fulfillment.Fulfillment_Evidence :=
        Fulfillment.Evidence.Element (1);
   begin
      Assert
        (HRA.Money.Lookup_Balance (Amounts.Applied, JPY) = 900.0
           and then HRA.Money.Lookup_Balance (Amounts.Reversed, JPY) = 450.0
           and then HRA.Money.Lookup_Balance
             (HRA.Envelope_Fulfillment.Net_Fulfillment (Amounts), JPY) = 450.0,
         "reversal chain restores root Fulfillment exactly");
      Assert
        (HRA.Dates.Image (Evidence.Route_Effective_From) = "2026-08-01"
           and then To_String (Evidence.Route_Note) =
             "save Plan fulfills savings",
         "completion-day route is frozen with historical provenance");
      Assert
        (Evidence.Plan_Header_Line > 0
           and then Evidence.Actual_Header_Line > 0
           and then To_String (Evidence.Root_Actual_Event_ID) = "act-save",
         "Fulfillment preserves exact-source and Actual identity evidence");
   end;

   --  Stock membership belongs to the completion root. A later reversal chain
   --  cannot pull a pre-origin completion into the clean Envelope epoch.
   declare
      Stock_Entitlement : HRA.Envelope_Entitlement.Entitlement_Observation :=
        HRA.Envelope_Entitlement.Empty_Observation;
      Stock_Fulfillment : HRA.Envelope_Fulfillment.Envelope_Fulfillment;
   begin
      Stock_Entitlement := HRA.Envelope_Entitlement.Record_Origin
        (Stock_Entitlement, JPY, D ("2026-08-17"));
      Assert
        (HRA.Envelope_Fulfillment.Observe_Stock
           (Completed,
            Actual,
            Registry,
            Routing,
            Stock_Entitlement,
            D ("2026-09-02"),
            Stock_Fulfillment,
            Fulfill_Diag),
         "Observe Fulfillment with source-owned stock origin");
      Assert
        (HRA.Money.Lookup_Balance
           (HRA.Envelope_Fulfillment.Net_For
              (Stock_Fulfillment, Savings_Env), JPY) = 0.0
           and then Stock_Fulfillment.Evidence.Is_Empty,
         "pre-origin completion stays outside stock after later reversals");

      Stock_Entitlement := HRA.Envelope_Entitlement.Empty_Observation;
      Stock_Entitlement := HRA.Envelope_Entitlement.Record_Origin
        (Stock_Entitlement, JPY, D ("2026-08-16"));
      Assert
        (HRA.Envelope_Fulfillment.Observe_Stock
           (Completed,
            Actual,
            Registry,
            Routing,
            Stock_Entitlement,
            D ("2026-09-02"),
            Stock_Fulfillment,
            Fulfill_Diag)
         and then HRA.Money.Lookup_Balance
           (HRA.Envelope_Fulfillment.Net_For
              (Stock_Fulfillment, Savings_Env), JPY) = 450.0,
         "completion at stock origin remains in cumulative Fulfillment");
   end;

   declare
      Window : constant HRA.Cycle_Observation.Cycle_Window :=
        H ("2026-08-01", "2026-10-01");
      Commitment  : HRA.Envelope_Commitment.Commitment_Observation;
      Commit_Diag : HRA.Envelope_Commitment.Observe_Diagnostic;
   begin
      Assert
        (HRA.Envelope_Commitment.Observe
           (Open_Plans,
            Registry,
            HRA.Envelope_Routing.Empty_History,
            Routing,
            Window,
            D ("2026-08-18"),
            Commitment,
            Commit_Diag),
         "Observe Commitment from the same role-neutral lifecycle result");
      Assert
        (HRA.Money.Lookup_Balance
           (HRA.Envelope_Commitment.Commitment_For
              (Commitment, Savings_Env), JPY) = 0.0,
         "completed Fulfillment is not simultaneously an open Commitment");
   end;

   declare
      Policy_Config : HRA.Budget_Config.Budget_Policy;
      Config_Diag   : HRA.Config_Support.Config_Diagnostic;
      Policy        : HRA.Backing_Policy.Backing_Policy;
      Policy_Status : HRA.Backing_Policy.Policy_Status;
      Entitlement   : HRA.Envelope_Entitlement.Entitlement_Observation :=
        HRA.Envelope_Entitlement.Empty_Observation;
      Positions     : HRA.Envelope_Position.Observation;
      Pos_Diag      : HRA.Envelope_Position.Observe_Diagnostic;
      Pos           : HRA.Envelope_Position.Position;
   begin
      Assert
        (HRA.Budget_Config.Parse_Budget_Policy
           (Budget_TOML, Policy_Config, Config_Diag),
         "Setup: parse Backing policy for Remaining law");
      Assert
        (HRA.Backing_Policy.Admit_Backing_Policy
           (Policy_Config, Env_Registry, Policy, Policy_Status)
           and then Policy_Status = HRA.Backing_Policy.Success,
         "Setup: admit Backing policy for Remaining law");

      Entitlement := HRA.Envelope_Entitlement.Fold_Movement
        (Entitlement,
         (Kind    => HRA.Envelope_Entitlement.Grant_From_Unallocated,
          Tx_Date => D ("2026-08-01"),
          Amt     => HRA.Money.Make_Amount (JPY, 1000.0),
          Target  => Savings_Env));

      Assert
        (HRA.Envelope_Position.Observe
           (Policy_Config,
            Env_Registry,
            Entitlement,
            HRA.Envelope_Consumption.Empty_Consumption,
            Fulfillment,
            HRA.Envelope_Commitment.Empty_Observation
              (D ("2026-08-18"), D ("2026-08-18")),
            Positions,
            Pos_Diag),
         "Observe Envelope positions with fulfillment");

      Pos := HRA.Envelope_Position.Position_For (Positions, Savings_Env);

      Assert
        (HRA.Money.Lookup_Balance (Pos.Remaining, JPY) = 550.0,
         "Remaining = Entitlement - Consumption - completed Fulfillment");
   end;

   Put_Line
     (Natural'Image (Passed_Count) & " passed, " &
      Natural'Image (Failed_Count) & " failed");

   if Failed_Count > 0 then
      raise Program_Error with "Envelope Fulfillment tests failed";
   end if;
end Test_Envelope_Fulfillment;
