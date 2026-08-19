with Ada.Text_IO; use Ada.Text_IO;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA.Account;
with HRA.Budget_Config;
with HRA.Config_Support;
with HRA.Cycle_Observation;
with HRA.Dates;
with HRA.Envelope;
with HRA.Envelope_Commitment;
with HRA.Envelope_Routing;
with HRA.Fulfillment_Routing;
with HRA.Household_Config;
with HRA.Journal;
with HRA.Ledger;
with HRA.Money;
with HRA.Plan;
with HRA.Plan_Observation;

procedure Test_Fulfillment_Routing is
   use type HRA.Envelope.Envelope_Id;
   use type HRA.Fulfillment_Routing.Admission_Status;
   use type HRA.Fulfillment_Routing.Fulfillment_Route_Kind;
   use type HRA.Household_Config.Fulfillment_Route_Kind;
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

   Budget_TOML : constant String :=
     "[[backing-pools]]" & ASCII.LF &
     "id = ""liquid""" & ASCII.LF &
     "asset-accounts = [""assets:cash""]" & ASCII.LF &
     "[[envelopes]]" & ASCII.LF &
     "id = ""savings""" & ASCII.LF &
     "label = ""Savings""" & ASCII.LF &
     "pacing = ""daily""" & ASCII.LF &
     "backing-pool = ""liquid""" & ASCII.LF;

   Household_TOML : constant String :=
     "[cycle]" & ASCII.LF &
     "mode = ""income-anchor""" & ASCII.LF &
     "income-account = ""income:pension""" & ASCII.LF &
     "[budget]" & ASCII.LF &
     "opening-accounts = [""budget:opening""]" & ASCII.LF &
     "unassigned-accounts = [""budget:unassigned""]" & ASCII.LF &
     "[[budget.envelopes]]" & ASCII.LF &
     "id = ""savings""" & ASCII.LF &
     "allocation-account = ""budget:savings""" & ASCII.LF &
     "[envelope-history]" & ASCII.LF &
     "identities = [""savings""]" & ASCII.LF &
     "expense-routing = []" & ASCII.LF &
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

   Registry     : HRA.Account.Account_Registry := HRA.Account.Empty_Registry;
   Actual       : HRA.Ledger.Ledger;
   Plans        : HRA.Ledger.Ledger;
   Parse_Error  : Unbounded_String;
   Known_Plans  : HRA.Plan.Plan_Id_Universe;
   Plan_Diag    : HRA.Plan_Observation.Admission_Diagnostic;
   Open_Plans   : HRA.Plan_Observation.Open_Plan_Vectors.Vector;
   Window       : HRA.Cycle_Observation.Cycle_Window;
   Cycle_Status : HRA.Cycle_Observation.Resolve_Status;
   Income_Acc   : constant HRA.Account.Account :=
     HRA.Account.Make_Account ("income:pension");
   Env_Names    : HRA.Config_Support.String_Vectors.Vector;
   Env_Registry : HRA.Envelope.Envelope_Registry;
   Env_Diag     : HRA.Config_Support.Config_Diagnostic;
   Savings_Env  : HRA.Envelope.Envelope_Id;
   Decisions    : HRA.Fulfillment_Routing.Decision_Vectors.Vector;
   History      : HRA.Fulfillment_Routing.Fulfillment_Routing_History;
   Route_Status : HRA.Fulfillment_Routing.Admission_Status;
   Commitment   : HRA.Envelope_Commitment.Commitment_Observation;
   Commit_Diag  : HRA.Envelope_Commitment.Observe_Diagnostic;
   JPY          : constant HRA.Money.Commodity := HRA.Money.Make_Commodity ("JPY");

begin
   Put_Line ("--- Testing HRA.Fulfillment_Routing ---");

   declare
      Budget_Policy : HRA.Budget_Config.Budget_Policy;
      Budget_Diag   : HRA.Config_Support.Config_Diagnostic;
      Household     : HRA.Household_Config.Household_Configuration;
      Household_Diag : HRA.Config_Support.Config_Diagnostic;
   begin
      Assert
        (HRA.Budget_Config.Parse_Budget_Policy
           (Budget_TOML, Budget_Policy, Budget_Diag),
         "Setup: parse Budget policy for Fulfillment routing source shape");
      Assert
        (HRA.Household_Config.Parse_Household_Configuration
           (Household_TOML, Budget_Policy, Household, Household_Diag),
         "Admit fulfillment-routing from household.toml");
      Assert
        (Natural (Household.Envelope_History.Fulfillment_Routing.Length) = 2,
         "Typed source retains two Fulfillment routing decisions");
      Assert
        (Household.Envelope_History.Fulfillment_Routing.Element (1).Route.Kind =
           HRA.Household_Config.Fulfills
         and then To_String
           (Household.Envelope_History.Fulfillment_Routing.Element (1).Route.Target) =
             "savings",
         "fulfills source decision requires and preserves Envelope target");
      Assert
        (Household.Envelope_History.Fulfillment_Routing.Element (2).Route.Kind =
           HRA.Household_Config.Not_Target,
         "not-target source decision is admitted without target");
   end;

   Register (Registry, "income:pension", HRA.Account.Income);
   Register (Registry, "assets:cash", HRA.Account.Asset);
   Register (Registry, "assets:savings", HRA.Account.Asset);
   Register (Registry, "liabilities:loan", HRA.Account.Liability);

   Assert
     (HRA.Journal.Parse_Journal_Text (Actual_Source, Actual, Parse_Error),
      "Setup: parse Actual cycle anchors");
   Assert
     (HRA.Journal.Parse_Journal_Text (Plan_Source, Plans, Parse_Error),
      "Setup: parse role-neutral Plan journal");

   Assert
     (HRA.Plan_Observation.Admit_Plan_Identities
        (Plans, Plan_Source, Known_Plans, Plan_Diag),
      "Admit stable Plan identity universe from exact Plan source evidence");
   Assert
     (HRA.Plan.Length (Known_Plans) = 4,
      "Stable Plan identity universe retains all lifecycle-independent PlanIds");

   Assert
     (HRA.Plan_Observation.Observe_Open_Plans
        (Plans, Plan_Source, Actual, Actual_Source,
         D ("2026-08-15"), Open_Plans, Plan_Diag),
      "Observe open role-neutral Plans");

   Assert
     (HRA.Cycle_Observation.Resolve_Current
        (D ("2026-08-15"), Actual, Open_Plans, Registry, Income_Acc,
         Window, Cycle_Status),
      "Resolve current income-anchor cycle");
   Assert
     (HRA.Dates.Image (HRA.Cycle_Observation.Start_Date (Window)) = "2026-08-14"
        and then HRA.Dates.Image (HRA.Cycle_Observation.End_Exclusive (Window)) = "2026-10-15",
      "Current cycle excludes next income anchor day");

   Env_Names.Append ("savings");
   Assert
     (HRA.Envelope.Admit_Registry
        (Env_Names, Env_Registry, Env_Diag),
      "Admit stable Envelope registry");
   Assert
     (HRA.Envelope.Lookup (Env_Registry, "savings", Savings_Env),
      "Lookup savings Envelope");

   declare
      Save_ID : constant HRA.Plan.Plan_Id := HRA.Plan.Make_Plan_Id ("plan-save");
      Debt_ID : constant HRA.Plan.Plan_Id := HRA.Plan.Make_Plan_Id ("plan-debt");
   begin
      Decisions.Append
        (HRA.Fulfillment_Routing.Fulfillment_Routing_Decision'
           (Effective_From => D ("2026-08-01"),
            Plan_ID        => Save_ID,
            Route          => HRA.Fulfillment_Routing.Fulfills (Savings_Env),
            Note           => To_Unbounded_String ("initial savings intent")));
      Decisions.Append
        (HRA.Fulfillment_Routing.Fulfillment_Routing_Decision'
           (Effective_From => D ("2026-09-01"),
            Plan_ID        => Save_ID,
            Route          => HRA.Fulfillment_Routing.Not_Target,
            Note           => To_Unbounded_String ("prospective intent retirement")));
      Decisions.Append
        (HRA.Fulfillment_Routing.Fulfillment_Routing_Decision'
           (Effective_From => D ("2026-08-01"),
            Plan_ID        => Debt_ID,
            Route          => HRA.Fulfillment_Routing.Not_Target,
            Note           => To_Unbounded_String ("debt Plan is explicit non-target")));
   end;

   Assert
     (HRA.Fulfillment_Routing.Admit
        (Decisions, Known_Plans, Env_Registry, History, Route_Status),
      "Admit PlanId/day Fulfillment routing against stable references");
   Assert
     (HRA.Fulfillment_Routing.Length (History) = 3,
      "Fulfillment routing history keeps source decisions");

   declare
      Save_ID : constant HRA.Plan.Plan_Id := HRA.Plan.Make_Plan_Id ("plan-save");
      Before  : constant HRA.Fulfillment_Routing.Fulfillment_Route :=
        HRA.Fulfillment_Routing.Resolve (History, Save_ID, D ("2026-08-15"));
      After   : constant HRA.Fulfillment_Routing.Fulfillment_Route :=
        HRA.Fulfillment_Routing.Resolve (History, Save_ID, D ("2026-09-01"));
   begin
      Assert
        (not HRA.Fulfillment_Routing.Has_Routing_At
           (History, Save_ID, D ("2026-07-31")),
         "Future Fulfillment decision does not rewrite earlier observation");
      Assert
        (Before.Kind = HRA.Fulfillment_Routing.Fulfills_Envelope
         and then Before.Target = Savings_Env,
         "Latest applicable fulfills decision resolves at observation day");
      Assert
        (After.Kind = HRA.Fulfillment_Routing.Not_Fulfillment_Target,
         "Later not-target decision changes intent prospectively");
   end;

   Assert
     (HRA.Envelope_Commitment.Observe
        (Open_Plans,
         Registry,
         HRA.Envelope_Routing.Empty_History,
         History,
         Window,
         D ("2026-08-15"),
         Commitment,
         Commit_Diag),
      "Observe non-Expense Envelope commitment through PlanId routing");
   Assert
     (HRA.Money.Lookup_Balance
        (HRA.Envelope_Commitment.Commitment_For (Commitment, Savings_Env), JPY)
        = 500.0,
      "Only explicitly routed savings Plan claims Envelope headroom");
   Assert
     (HRA.Money.Lookup_Balance
        (HRA.Envelope_Commitment.Commitment_For (Commitment, Savings_Env), JPY)
        /= 800.0,
      "Unrelated Plan using same destination Account inherits no Envelope meaning");

   declare
      Bad : HRA.Fulfillment_Routing.Decision_Vectors.Vector;
      Rejected : HRA.Fulfillment_Routing.Fulfillment_Routing_History;
   begin
      Bad.Append
        (HRA.Fulfillment_Routing.Fulfillment_Routing_Decision'
           (Effective_From => D ("2026-08-01"),
            Plan_ID        => HRA.Plan.Make_Plan_Id ("plan-missing"),
            Route          => HRA.Fulfillment_Routing.Not_Target,
            Note           => To_Unbounded_String ("dangling Plan reference")));
      Assert
        (not HRA.Fulfillment_Routing.Admit
           (Bad, Known_Plans, Env_Registry, Rejected, Route_Status)
         and then Route_Status = HRA.Fulfillment_Routing.Unknown_Plan_Reference,
         "Reject Fulfillment routing that references unknown stable PlanId");
   end;

   declare
      Bad : HRA.Fulfillment_Routing.Decision_Vectors.Vector;
      Rejected : HRA.Fulfillment_Routing.Fulfillment_Routing_History;
      Ghost : constant HRA.Envelope.Envelope_Id :=
        HRA.Envelope.Make_Envelope_Id ("ghost");
   begin
      Bad.Append
        (HRA.Fulfillment_Routing.Fulfillment_Routing_Decision'
           (Effective_From => D ("2026-08-01"),
            Plan_ID        => HRA.Plan.Make_Plan_Id ("plan-save"),
            Route          => HRA.Fulfillment_Routing.Fulfills (Ghost),
            Note           => To_Unbounded_String ("dangling Envelope reference")));
      Assert
        (not HRA.Fulfillment_Routing.Admit
           (Bad, Known_Plans, Env_Registry, Rejected, Route_Status)
         and then Route_Status = HRA.Fulfillment_Routing.Unknown_Envelope_Reference,
         "Reject Fulfillment routing that references unknown EnvelopeId");
   end;

   declare
      Bad : HRA.Fulfillment_Routing.Decision_Vectors.Vector;
      Rejected : HRA.Fulfillment_Routing.Fulfillment_Routing_History;
      Save_ID : constant HRA.Plan.Plan_Id := HRA.Plan.Make_Plan_Id ("plan-save");
      Decision : constant HRA.Fulfillment_Routing.Fulfillment_Routing_Decision :=
        (Effective_From => D ("2026-08-01"),
         Plan_ID        => Save_ID,
         Route          => HRA.Fulfillment_Routing.Fulfills (Savings_Env),
         Note           => To_Unbounded_String ("duplicate coordinate"));
   begin
      Bad.Append (Decision);
      Bad.Append (Decision);
      Assert
        (not HRA.Fulfillment_Routing.Admit
           (Bad, Known_Plans, Env_Registry, Rejected, Route_Status)
         and then Route_Status =
           HRA.Fulfillment_Routing.Duplicate_Plan_Date_Coordinate,
         "Reject duplicate PlanId/day Fulfillment routing coordinate");
   end;

   Put_Line
     (Natural'Image (Passed_Count) & " passed, " &
      Natural'Image (Failed_Count) & " failed");

   if Failed_Count > 0 then
      raise Program_Error with "Fulfillment routing tests failed";
   end if;
end Test_Fulfillment_Routing;
