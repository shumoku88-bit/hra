with Ada.Text_IO; use Ada.Text_IO;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with ALedger.Account;
with ALedger.Budget_Config;
with ALedger.Config_Support;
with ALedger.Cycle_Observation;
with ALedger.Envelope;
with ALedger.Envelope_Commitment;
with ALedger.Envelope_Routing;
with ALedger.Fulfillment_Routing;
with ALedger.Household_Config;
with ALedger.Journal;
with ALedger.Ledger;
with ALedger.Money;
with ALedger.Plan;
with ALedger.Plan_Observation;

procedure Test_Fulfillment_Routing is
   use type ALedger.Cycle_Observation.Resolve_Status;
   use type ALedger.Envelope.Envelope_Id;
   use type ALedger.Fulfillment_Routing.Admission_Status;
   use type ALedger.Fulfillment_Routing.Fulfillment_Route_Kind;
   use type ALedger.Household_Config.Fulfillment_Route_Kind;
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

   Household_TOML : constant String :=
     "[cycle]" & ASCII.LF &
     "mode = ""income-anchor""" & ASCII.LF &
     "income-account = ""income:pension""" & ASCII.LF &
     "[budget]" & ASCII.LF &
     "unassigned-accounts = [""budget:unassigned""]" & ASCII.LF &
     "[[budget.envelopes]]" & ASCII.LF &
     "id = ""savings""" & ASCII.LF &
     "allocation-account = ""budget:savings""" & ASCII.LF &
     "plan-destination-accounts = [""assets:savings""]" & ASCII.LF &
     "[envelope-history]" & ASCII.LF &
     "identities = [""savings""]" & ASCII.LF &
     "[[envelope-history.fulfillment-routing]]" & ASCII.LF &
     "effective-from = ""2026-08-01""" & ASCII.LF &
     "plan-id = ""plan-save""" & ASCII.LF &
     "route = ""fulfills""" & ASCII.LF &
     "target = ""savings""" & ASCII.LF &
     "note = ""save Plan fulfills savings Envelope""" & ASCII.LF &
     "[[envelope-history.fulfillment-routing]]" & ASCII.LF &
     "effective-from = ""2026-09-01""" & ASCII.LF &
     "plan-id = ""plan-save""" & ASCII.LF &
     "route = ""not-target""" & ASCII.LF &
     "note = ""intent retired prospectively""" & ASCII.LF;

   Actual_Source : constant String :=
     "2026-06-15 Pension" & ASCII.LF &
     "    assets:cash        1000 JPY" & ASCII.LF &
     "    income:pension    -1000 JPY" & ASCII.LF & ASCII.LF &
     "2026-08-14 Pension" & ASCII.LF &
     "    assets:cash        1000 JPY" & ASCII.LF &
     "    income:pension    -1000 JPY" & ASCII.LF;

   Plan_Source : constant String :=
     "2026-08-20 Save" & ASCII.LF &
     "    ; plan-id: plan-save" & ASCII.LF &
     "    assets:savings      500 JPY" & ASCII.LF &
     "    assets:cash        -500 JPY" & ASCII.LF & ASCII.LF &
     "2026-08-25 Unrelated transfer to same Account" & ASCII.LF &
     "    ; plan-id: plan-unrelated" & ASCII.LF &
     "    assets:savings      300 JPY" & ASCII.LF &
     "    assets:cash        -300 JPY" & ASCII.LF & ASCII.LF &
     "2026-08-26 Debt payment not an Envelope target" & ASCII.LF &
     "    ; plan-id: plan-debt" & ASCII.LF &
     "    liabilities:loan    200 JPY" & ASCII.LF &
     "    assets:cash        -200 JPY" & ASCII.LF & ASCII.LF &
     "2026-10-15 Next pension" & ASCII.LF &
     "    ; plan-id: plan-next-income" & ASCII.LF &
     "    assets:cash        1000 JPY" & ASCII.LF &
     "    income:pension    -1000 JPY" & ASCII.LF;

   Registry     : ALedger.Account.Account_Registry := ALedger.Account.Empty_Registry;
   Actual       : ALedger.Ledger.Ledger;
   Plans        : ALedger.Ledger.Ledger;
   Parse_Error  : Unbounded_String;
   Known_Plans  : ALedger.Plan.Plan_Id_Vectors.Vector;
   Plan_Diag    : ALedger.Plan_Observation.Admission_Diagnostic;
   Open_Plans   : ALedger.Plan_Observation.Open_Plan_Vectors.Vector;
   Window       : ALedger.Cycle_Observation.Cycle_Window;
   Cycle_Status : ALedger.Cycle_Observation.Resolve_Status;
   Income_Acc   : constant ALedger.Account.Account :=
     ALedger.Account.Make_Account ("income:pension");
   Env_Names    : ALedger.Config_Support.String_Vectors.Vector;
   Env_Registry : ALedger.Envelope.Envelope_Registry;
   Env_Diag     : ALedger.Config_Support.Config_Diagnostic;
   Savings_Env  : ALedger.Envelope.Envelope_Id;
   Decisions    : ALedger.Fulfillment_Routing.Decision_Vectors.Vector;
   History      : ALedger.Fulfillment_Routing.Fulfillment_Routing_History;
   Route_Status : ALedger.Fulfillment_Routing.Admission_Status;
   Commitment   : ALedger.Envelope_Commitment.Commitment_Observation;
   Commit_Diag  : ALedger.Envelope_Commitment.Observe_Diagnostic;
   JPY          : constant ALedger.Money.Commodity := ALedger.Money.Make_Commodity ("JPY");

begin
   Put_Line ("--- Testing ALedger.Fulfillment_Routing ---");

   declare
      Budget_Policy : ALedger.Budget_Config.Budget_Policy;
      Budget_Diag   : ALedger.Config_Support.Config_Diagnostic;
      Household     : ALedger.Household_Config.Household_Configuration;
      Household_Diag : ALedger.Config_Support.Config_Diagnostic;
   begin
      Assert
        (ALedger.Budget_Config.Parse_Budget_Policy
           (Budget_TOML, Budget_Policy, Budget_Diag),
         "Setup: parse Budget policy for Fulfillment routing source shape");
      Assert
        (ALedger.Household_Config.Parse_Household_Configuration
           (Household_TOML, Budget_Policy, Household, Household_Diag),
         "Admit fulfillment-routing from household.toml");
      Assert
        (Natural (Household.Envelope_History.Fulfillment_Routing.Length) = 2,
         "Typed source retains two Fulfillment routing decisions");
      Assert
        (Household.Envelope_History.Fulfillment_Routing.Element (1).Route.Kind =
           ALedger.Household_Config.Fulfills
         and then To_String
           (Household.Envelope_History.Fulfillment_Routing.Element (1).Route.Target) =
             "savings",
         "fulfills source decision requires and preserves Envelope target");
      Assert
        (Household.Envelope_History.Fulfillment_Routing.Element (2).Route.Kind =
           ALedger.Household_Config.Not_Target,
         "not-target source decision is admitted without target");
   end;

   Register (Registry, "income:pension", ALedger.Account.Income);
   Register (Registry, "assets:cash", ALedger.Account.Asset);
   Register (Registry, "assets:savings", ALedger.Account.Asset);
   Register (Registry, "liabilities:loan", ALedger.Account.Liability);

   Assert
     (ALedger.Journal.Parse_Journal_Text (Actual_Source, Actual, Parse_Error),
      "Setup: parse Actual cycle anchors");
   Assert
     (ALedger.Journal.Parse_Journal_Text (Plan_Source, Plans, Parse_Error),
      "Setup: parse role-neutral Plan journal");

   Assert
     (ALedger.Plan_Observation.Admit_Plan_Identities
        (Plans, Plan_Source, Known_Plans, Plan_Diag),
      "Admit stable Plan identity universe from exact Plan source evidence");
   Assert
     (Natural (Known_Plans.Length) = 4,
      "Stable Plan identity universe retains all lifecycle-independent PlanIds");

   Assert
     (ALedger.Plan_Observation.Observe_Open_Plans
        (Plans, Plan_Source, Actual, Actual_Source,
         "2026-08-15", Open_Plans, Plan_Diag),
      "Observe open role-neutral Plans");

   Assert
     (ALedger.Cycle_Observation.Resolve_Current
        ("2026-08-15", Actual, Open_Plans, Registry, Income_Acc,
         Window, Cycle_Status),
      "Resolve current income-anchor cycle");
   Assert
     (To_String (Window.Start_Date) = "2026-08-14"
        and then To_String (Window.End_Exclusive) = "2026-10-15",
      "Current cycle excludes next income anchor day");

   Env_Names.Append ("savings");
   Assert
     (ALedger.Envelope.Admit_Registry
        (Env_Names, Env_Registry, Env_Diag),
      "Admit stable Envelope registry");
   Assert
     (ALedger.Envelope.Lookup (Env_Registry, "savings", Savings_Env),
      "Lookup savings Envelope");

   declare
      Save_ID : constant ALedger.Plan.Plan_Id := ALedger.Plan.Make_Plan_Id ("plan-save");
      Debt_ID : constant ALedger.Plan.Plan_Id := ALedger.Plan.Make_Plan_Id ("plan-debt");
   begin
      Decisions.Append
        (ALedger.Fulfillment_Routing.Fulfillment_Routing_Decision'
           (Effective_From => To_Unbounded_String ("2026-08-01"),
            Plan_ID        => Save_ID,
            Route          => ALedger.Fulfillment_Routing.Fulfills (Savings_Env),
            Note           => To_Unbounded_String ("initial savings intent")));
      Decisions.Append
        (ALedger.Fulfillment_Routing.Fulfillment_Routing_Decision'
           (Effective_From => To_Unbounded_String ("2026-09-01"),
            Plan_ID        => Save_ID,
            Route          => ALedger.Fulfillment_Routing.Not_Target,
            Note           => To_Unbounded_String ("prospective intent retirement")));
      Decisions.Append
        (ALedger.Fulfillment_Routing.Fulfillment_Routing_Decision'
           (Effective_From => To_Unbounded_String ("2026-08-01"),
            Plan_ID        => Debt_ID,
            Route          => ALedger.Fulfillment_Routing.Not_Target,
            Note           => To_Unbounded_String ("debt Plan is explicit non-target")));
   end;

   Assert
     (ALedger.Fulfillment_Routing.Admit
        (Decisions, Known_Plans, Env_Registry, History, Route_Status),
      "Admit PlanId/day Fulfillment routing against stable references");
   Assert
     (ALedger.Fulfillment_Routing.Length (History) = 3,
      "Fulfillment routing history keeps source decisions");

   declare
      Save_ID : constant ALedger.Plan.Plan_Id := ALedger.Plan.Make_Plan_Id ("plan-save");
      Before  : constant ALedger.Fulfillment_Routing.Fulfillment_Route :=
        ALedger.Fulfillment_Routing.Resolve (History, Save_ID, "2026-08-15");
      After   : constant ALedger.Fulfillment_Routing.Fulfillment_Route :=
        ALedger.Fulfillment_Routing.Resolve (History, Save_ID, "2026-09-01");
   begin
      Assert
        (not ALedger.Fulfillment_Routing.Has_Routing_At
           (History, Save_ID, "2026-07-31"),
         "Future Fulfillment decision does not rewrite earlier observation");
      Assert
        (Before.Kind = ALedger.Fulfillment_Routing.Fulfills_Envelope
         and then Before.Target = Savings_Env,
         "Latest applicable fulfills decision resolves at observation day");
      Assert
        (After.Kind = ALedger.Fulfillment_Routing.Not_Fulfillment_Target,
         "Later not-target decision changes intent prospectively");
   end;

   Assert
     (ALedger.Envelope_Commitment.Observe
        (Open_Plans,
         Registry,
         ALedger.Envelope_Routing.Empty_History,
         History,
         Window,
         "2026-08-15",
         Commitment,
         Commit_Diag),
      "Observe non-Expense Envelope commitment through PlanId routing");
   Assert
     (ALedger.Money.Lookup_Balance
        (ALedger.Envelope_Commitment.Commitment_For (Commitment, Savings_Env), JPY)
        = 500.0,
      "Only explicitly routed savings Plan claims Envelope headroom");
   Assert
     (ALedger.Money.Lookup_Balance
        (ALedger.Envelope_Commitment.Commitment_For (Commitment, Savings_Env), JPY)
        /= 800.0,
      "Unrelated Plan using same destination Account inherits no Envelope meaning");

   declare
      Bad : ALedger.Fulfillment_Routing.Decision_Vectors.Vector;
      Rejected : ALedger.Fulfillment_Routing.Fulfillment_Routing_History;
   begin
      Bad.Append
        (ALedger.Fulfillment_Routing.Fulfillment_Routing_Decision'
           (Effective_From => To_Unbounded_String ("2026-08-01"),
            Plan_ID        => ALedger.Plan.Make_Plan_Id ("plan-missing"),
            Route          => ALedger.Fulfillment_Routing.Not_Target,
            Note           => To_Unbounded_String ("dangling Plan reference")));
      Assert
        (not ALedger.Fulfillment_Routing.Admit
           (Bad, Known_Plans, Env_Registry, Rejected, Route_Status)
         and then Route_Status = ALedger.Fulfillment_Routing.Unknown_Plan_Reference,
         "Reject Fulfillment routing that references unknown stable PlanId");
   end;

   declare
      Bad : ALedger.Fulfillment_Routing.Decision_Vectors.Vector;
      Rejected : ALedger.Fulfillment_Routing.Fulfillment_Routing_History;
      Ghost : constant ALedger.Envelope.Envelope_Id :=
        ALedger.Envelope.Make_Envelope_Id ("ghost");
   begin
      Bad.Append
        (ALedger.Fulfillment_Routing.Fulfillment_Routing_Decision'
           (Effective_From => To_Unbounded_String ("2026-08-01"),
            Plan_ID        => ALedger.Plan.Make_Plan_Id ("plan-save"),
            Route          => ALedger.Fulfillment_Routing.Fulfills (Ghost),
            Note           => To_Unbounded_String ("dangling Envelope reference")));
      Assert
        (not ALedger.Fulfillment_Routing.Admit
           (Bad, Known_Plans, Env_Registry, Rejected, Route_Status)
         and then Route_Status = ALedger.Fulfillment_Routing.Unknown_Envelope_Reference,
         "Reject Fulfillment routing that references unknown EnvelopeId");
   end;

   declare
      Bad : ALedger.Fulfillment_Routing.Decision_Vectors.Vector;
      Rejected : ALedger.Fulfillment_Routing.Fulfillment_Routing_History;
      Save_ID : constant ALedger.Plan.Plan_Id := ALedger.Plan.Make_Plan_Id ("plan-save");
      Decision : constant ALedger.Fulfillment_Routing.Fulfillment_Routing_Decision :=
        (Effective_From => To_Unbounded_String ("2026-08-01"),
         Plan_ID        => Save_ID,
         Route          => ALedger.Fulfillment_Routing.Fulfills (Savings_Env),
         Note           => To_Unbounded_String ("duplicate coordinate"));
   begin
      Bad.Append (Decision);
      Bad.Append (Decision);
      Assert
        (not ALedger.Fulfillment_Routing.Admit
           (Bad, Known_Plans, Env_Registry, Rejected, Route_Status)
         and then Route_Status =
           ALedger.Fulfillment_Routing.Duplicate_Plan_Date_Coordinate,
         "Reject duplicate PlanId/day Fulfillment routing coordinate");
   end;

   Put_Line
     (Natural'Image (Passed_Count) & " passed, " &
      Natural'Image (Failed_Count) & " failed");

   if Failed_Count > 0 then
      raise Program_Error with "Fulfillment routing tests failed";
   end if;
end Test_Fulfillment_Routing;
