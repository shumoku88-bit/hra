with Ada.Text_IO; use Ada.Text_IO;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with ALedger.Account;
with ALedger.Backing_Policy;
with ALedger.Budget_Config;
with ALedger.Config_Support;
with ALedger.Cycle_Observation;
with ALedger.Dates;
with ALedger.Envelope;
with ALedger.Envelope_Commitment;
with ALedger.Envelope_Consumption;
with ALedger.Envelope_Entitlement;
with ALedger.Envelope_Fulfillment;
with ALedger.Envelope_Routing;
with ALedger.Fulfillment_Routing;
with ALedger.Journal;
with ALedger.Ledger;
with ALedger.Money;
with ALedger.Plan;
with ALedger.Plan_Observation;

procedure Test_Envelope_Fulfillment is
   use type ALedger.Backing_Policy.Policy_Status;
   use type ALedger.Fulfillment_Routing.Admission_Status;
   use type ALedger.Money.Quantity;

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

   function D (S : String) return ALedger.Dates.Date is
      Val    : ALedger.Dates.Date;
      Status : ALedger.Dates.Date_Status;
   begin
      if not ALedger.Dates.Parse (S, Val, Status) then
         raise Program_Error with "Invalid date in test: " & S;
      end if;
      return Val;
   end D;

   function H (S1, S2 : String) return ALedger.Dates.Half_Open_Period is
      Res : ALedger.Dates.Half_Open_Period;
   begin
      if not ALedger.Dates.Make_Half_Open_Period (D (S1), D (S2), Res) then
         raise Program_Error with "Invalid half-open period: [" & S1 & ", " & S2 & ")";
      end if;
      return Res;
   end H;

   procedure Register
     (Registry : in out ALedger.Account.Account_Registry;
      Name     : String;
      Kind     : ALedger.Account.Account_Type)
   is
      Status : ALedger.Account.Registry_Status;
   begin
      if not ALedger.Account.Register_Account
        (Registry,
         ALedger.Account.Declare_Account
           (ALedger.Account.Make_Account (Name), Kind),
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
     "backing-pool = ""liquid""" & ASCII.LF &
     "expense-accounts = []" & ASCII.LF;

   Registry       : ALedger.Account.Account_Registry := ALedger.Account.Empty_Registry;
   Plans          : ALedger.Ledger.Ledger;
   Actual         : ALedger.Ledger.Ledger;
   Parse_Error    : Unbounded_String;
   Open_Plans     : ALedger.Plan_Observation.Open_Plan_Vectors.Vector;
   Completed      : ALedger.Plan_Observation.Completed_Plan_Vectors.Vector;
   Plan_Diag      : ALedger.Plan_Observation.Admission_Diagnostic;
   Known_Plans    : ALedger.Plan.Plan_Id_Universe;
   Env_Names      : ALedger.Config_Support.String_Vectors.Vector;
   Env_Registry   : ALedger.Envelope.Envelope_Registry;
   Env_Diag       : ALedger.Config_Support.Config_Diagnostic;
   Savings_Env    : ALedger.Envelope.Envelope_Id;
   Decisions      : ALedger.Fulfillment_Routing.Decision_Vectors.Vector;
   Routing        : ALedger.Fulfillment_Routing.Fulfillment_Routing_History;
   Routing_Status : ALedger.Fulfillment_Routing.Admission_Status;
   Fulfillment    : ALedger.Envelope_Fulfillment.Envelope_Fulfillment;
   Fulfill_Diag   : ALedger.Envelope_Fulfillment.Observe_Diagnostic;
   JPY            : constant ALedger.Money.Commodity :=
     ALedger.Money.Make_Commodity ("JPY");

begin
   Put_Line ("--- Testing ALedger.Envelope_Fulfillment ---");

   Register (Registry, "assets:cash", ALedger.Account.Asset);
   Register (Registry, "assets:savings", ALedger.Account.Asset);
   Register (Registry, "expenses:food", ALedger.Account.Expense);

   Assert
     (ALedger.Journal.Parse_Journal_Text (Plan_Source, Plans, Parse_Error),
      "Setup: parse role-neutral Plan journal");
   Assert
     (ALedger.Journal.Parse_Journal_Text (Actual_Source, Actual, Parse_Error),
      "Setup: parse explicit completion and reversal chain");

   Assert
     (ALedger.Plan_Observation.Observe_Plans
        (Plans, Plan_Source, Actual, Actual_Source,
         D ("2026-08-18"), Open_Plans, Completed, Plan_Diag),
      "Observe open/completed Plan lifecycle once");
   Assert
     (Natural (Open_Plans.Length) = 0
        and then Natural (Completed.Length) = 3,
      "Explicit Actual plan-id moves completed Plans out of open Commitment set");

   Assert
     (ALedger.Plan_Observation.Admit_Plan_Identities
        (Plans, Plan_Source, Known_Plans, Plan_Diag),
      "Admit stable Plan identity universe");

   Env_Names.Append ("savings");
   Assert
     (ALedger.Envelope.Admit_Registry
        (Env_Names, Env_Registry, Env_Diag),
      "Admit stable Envelope registry");
   Assert
     (ALedger.Envelope.Lookup (Env_Registry, "savings", Savings_Env),
      "Lookup savings Envelope");

   Decisions.Append
     (ALedger.Fulfillment_Routing.Fulfillment_Routing_Decision'
        (Effective_From => D ("2026-08-01"),
         Plan_ID        => ALedger.Plan.Make_Plan_Id ("plan-save"),
         Route          => ALedger.Fulfillment_Routing.Fulfills (Savings_Env),
         Note           => To_Unbounded_String ("save Plan fulfills savings")));
   Decisions.Append
     (ALedger.Fulfillment_Routing.Fulfillment_Routing_Decision'
        (Effective_From => D ("2026-09-01"),
         Plan_ID        => ALedger.Plan.Make_Plan_Id ("plan-save"),
         Route          => ALedger.Fulfillment_Routing.Not_Target,
         Note           => To_Unbounded_String ("future intent change")));
   Decisions.Append
     (ALedger.Fulfillment_Routing.Fulfillment_Routing_Decision'
        (Effective_From => D ("2026-08-01"),
         Plan_ID        => ALedger.Plan.Make_Plan_Id ("plan-food"),
         Route          => ALedger.Fulfillment_Routing.Fulfills (Savings_Env),
         Note           => To_Unbounded_String ("must not steal Expense ownership")));

   Assert
     (ALedger.Fulfillment_Routing.Admit
        (Decisions, Known_Plans, Env_Registry, Routing, Routing_Status)
        and then Routing_Status = ALedger.Fulfillment_Routing.Success,
      "Admit completion-day Fulfillment routing history");

   Assert
     (ALedger.Envelope_Fulfillment.Observe
        (Completed, Actual, Registry, Routing, D ("2026-08-16"),
         Fulfillment, Fulfill_Diag),
      "Observe root completed Actual Fulfillment");
   declare
      Amounts : constant ALedger.Envelope_Fulfillment.Fulfillment_Amounts :=
        ALedger.Envelope_Fulfillment.Fulfillment_For
          (Fulfillment, Savings_Env);
   begin
      Assert
        (ALedger.Money.Lookup_Balance (Amounts.Applied, JPY) = 450.0
           and then ALedger.Money.Lookup_Balance (Amounts.Reversed, JPY) = 0.0,
         "Actual quantity, not planned quantity, is authoritative");
      Assert
        (Natural (Fulfillment.Evidence.Length) = 1,
         "same Account unrelated Plan and Expense Plan inherit no Fulfillment meaning");
   end;

   Assert
     (ALedger.Envelope_Fulfillment.Observe
        (Completed, Actual, Registry, Routing, D ("2026-08-17"),
         Fulfillment, Fulfill_Diag),
      "Observe explicit reversal of Fulfillment");
   Assert
     (ALedger.Money.Lookup_Balance
        (ALedger.Envelope_Fulfillment.Net_For (Fulfillment, Savings_Env), JPY)
        = 0.0,
      "reversal removes the root Fulfillment effect");

   Assert
     (ALedger.Envelope_Fulfillment.Observe
        (Completed, Actual, Registry, Routing, D ("2026-09-02"),
         Fulfillment, Fulfill_Diag),
      "Observe reversal-of-reversal after later routing change");
   declare
      Amounts : constant ALedger.Envelope_Fulfillment.Fulfillment_Amounts :=
        ALedger.Envelope_Fulfillment.Fulfillment_For
          (Fulfillment, Savings_Env);
      Evidence : constant ALedger.Envelope_Fulfillment.Fulfillment_Evidence :=
        Fulfillment.Evidence.Element (1);
   begin
      Assert
        (ALedger.Money.Lookup_Balance (Amounts.Applied, JPY) = 900.0
           and then ALedger.Money.Lookup_Balance (Amounts.Reversed, JPY) = 450.0
           and then ALedger.Money.Lookup_Balance
             (ALedger.Envelope_Fulfillment.Net_Fulfillment (Amounts), JPY) = 450.0,
         "reversal chain restores root Fulfillment exactly");
      Assert
        (ALedger.Dates.Image (Evidence.Route_Effective_From) = "2026-08-01"
           and then To_String (Evidence.Route_Note) =
             "save Plan fulfills savings",
         "completion-day route is frozen with historical provenance");
      Assert
        (Evidence.Plan_Header_Line > 0
           and then Evidence.Actual_Header_Line > 0
           and then To_String (Evidence.Root_Actual_Event_ID) = "act-save",
         "Fulfillment preserves exact-source and Actual identity evidence");
   end;

   declare
      Window : constant ALedger.Cycle_Observation.Cycle_Window :=
        H ("2026-08-01", "2026-10-01");
      Commitment  : ALedger.Envelope_Commitment.Commitment_Observation;
      Commit_Diag : ALedger.Envelope_Commitment.Observe_Diagnostic;
   begin
      Assert
        (ALedger.Envelope_Commitment.Observe
           (Open_Plans,
            Registry,
            ALedger.Envelope_Routing.Empty_History,
            Routing,
            Window,
            D ("2026-08-18"),
            Commitment,
            Commit_Diag),
         "Observe Commitment from the same role-neutral lifecycle result");
      Assert
        (ALedger.Money.Lookup_Balance
           (ALedger.Envelope_Commitment.Commitment_For
              (Commitment, Savings_Env), JPY) = 0.0,
         "completed Fulfillment is not simultaneously an open Commitment");
   end;

   declare
      Policy_Config : ALedger.Budget_Config.Budget_Policy;
      Config_Diag   : ALedger.Config_Support.Config_Diagnostic;
      Policy        : ALedger.Backing_Policy.Backing_Policy;
      Policy_Status : ALedger.Backing_Policy.Policy_Status;
      Entitlement   : ALedger.Envelope_Entitlement.Entitlement_Observation :=
        ALedger.Envelope_Entitlement.Empty_Observation;
      Backing       : ALedger.Backing_Policy.Backing_Observation;
      Claim         : ALedger.Backing_Policy.Backed_Envelope_Claim;
   begin
      Assert
        (ALedger.Budget_Config.Parse_Budget_Policy
           (Budget_TOML, Policy_Config, Config_Diag),
         "Setup: parse Backing policy for Remaining law");
      Assert
        (ALedger.Backing_Policy.Admit_Backing_Policy
           (Policy_Config, Env_Registry, Policy, Policy_Status)
           and then Policy_Status = ALedger.Backing_Policy.Success,
         "Setup: admit Backing policy for Remaining law");

      Entitlement := ALedger.Envelope_Entitlement.Fold_Movement
        (Entitlement,
         (Kind    => ALedger.Envelope_Entitlement.Grant_From_Unallocated,
          Tx_Date => D ("2026-08-01"),
          Amt     => ALedger.Money.Make_Amount (JPY, 1000.0),
          Target  => Savings_Env));

      Backing := ALedger.Backing_Policy.Observe_Backing
        (Policy,
         Actual,
         Entitlement,
         ALedger.Envelope_Consumption.Empty_Consumption,
         Fulfillment,
         ALedger.Envelope_Commitment.Empty_Observation,
         ALedger.Backing_Policy.Empty_Funding_Commitment);
      Claim := ALedger.Backing_Policy.Claim_For (Backing, Savings_Env);

      Assert
        (ALedger.Money.Lookup_Balance (Claim.Remaining, JPY) = 550.0,
         "Remaining = Entitlement - Consumption - completed Fulfillment");
   end;

   Put_Line
     (Natural'Image (Passed_Count) & " passed, " &
      Natural'Image (Failed_Count) & " failed");

   if Failed_Count > 0 then
      raise Program_Error with "Envelope Fulfillment tests failed";
   end if;
end Test_Envelope_Fulfillment;
