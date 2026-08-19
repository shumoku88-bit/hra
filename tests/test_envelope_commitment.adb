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

procedure Test_Envelope_Commitment is
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

   Actual_Source : constant String :=
     "2026-06-15 Pension" & ASCII.LF &
     "    assets:cash        1000 JPY" & ASCII.LF &
     "    income:pension    -1000 JPY" & ASCII.LF & ASCII.LF &
     "2026-08-14 Pension" & ASCII.LF &
     "    assets:cash        1000 JPY" & ASCII.LF &
     "    income:pension    -1000 JPY" & ASCII.LF & ASCII.LF &
     "2026-08-14 Completed purchase" & ASCII.LF &
     "    ; plan-id: plan-completed" & ASCII.LF &
     "    expenses:food         50 JPY" & ASCII.LF &
     "    assets:cash          -50 JPY" & ASCII.LF;

   Plan_Source : constant String :=
     "2026-08-10 Overdue food" & ASCII.LF &
     "    ; plan-id: plan-overdue" & ASCII.LF &
     "    expenses:food        100 JPY" & ASCII.LF &
     "    assets:cash         -100 JPY" & ASCII.LF & ASCII.LF &
     "2026-08-20 Food" & ASCII.LF &
     "    ; plan-id: plan-food" & ASCII.LF &
     "    expenses:food        200 JPY" & ASCII.LF &
     "    assets:cash         -200 JPY" & ASCII.LF & ASCII.LF &
     "2026-08-25 Rent" & ASCII.LF &
     "    ; plan-id: plan-rent" & ASCII.LF &
     "    expenses:rent        300 JPY" & ASCII.LF &
     "    assets:cash         -300 JPY" & ASCII.LF & ASCII.LF &
     "2026-08-21 Completed purchase" & ASCII.LF &
     "    ; plan-id: plan-completed" & ASCII.LF &
     "    expenses:food         50 JPY" & ASCII.LF &
     "    assets:cash          -50 JPY" & ASCII.LF & ASCII.LF &
     "2026-10-15 Next pension" & ASCII.LF &
     "    ; plan-id: plan-next-pension" & ASCII.LF &
     "    assets:cash        1000 JPY" & ASCII.LF &
     "    income:pension    -1000 JPY" & ASCII.LF & ASCII.LF &
     "2026-10-15 Next-cycle food" & ASCII.LF &
     "    ; plan-id: plan-next-food" & ASCII.LF &
     "    expenses:food        999 JPY" & ASCII.LF &
     "    assets:cash         -999 JPY" & ASCII.LF;

   Budget_TOML : constant String :=
     "[[backing-pools]]" & ASCII.LF &
     "id = ""liquid""" & ASCII.LF &
     "asset-accounts = [""assets:cash""]" & ASCII.LF &
     "[[envelopes]]" & ASCII.LF &
     "id = ""food""" & ASCII.LF &
     "label = ""Food""" & ASCII.LF &
     "pacing = ""daily""" & ASCII.LF &
     "backing-pool = ""liquid""" & ASCII.LF;

   Registry      : HRA.Account.Account_Registry := HRA.Account.Empty_Registry;
   Actual        : HRA.Ledger.Ledger;
   Plans         : HRA.Ledger.Ledger;
   Parse_Error   : Unbounded_String;
   Open_Plans    : HRA.Plan_Observation.Open_Plan_Vectors.Vector;
   Plan_Diag     : HRA.Plan_Observation.Admission_Diagnostic;
   Window        : HRA.Cycle_Observation.Cycle_Window;
   Cycle_Status  : HRA.Cycle_Observation.Resolve_Status;
   Income_Acc    : constant HRA.Account.Account := HRA.Account.Make_Account ("income:pension");
   Env_Registry  : HRA.Envelope.Envelope_Registry;
   Env_Diag      : HRA.Config_Support.Config_Diagnostic;
   Env_Names     : HRA.Config_Support.String_Vectors.Vector;
   Food_Env      : HRA.Envelope.Envelope_Id;
   Route_Entries : HRA.Envelope_Routing.Routing_Entry_Vectors.Vector;
   Routing       : HRA.Envelope_Routing.Routing_History;
   Route_Status    : HRA.Envelope_Routing.History_Status;
   Fulfill_History : HRA.Fulfillment_Routing.Fulfillment_Routing_History;
   Fulfill_Status  : HRA.Fulfillment_Routing.Admission_Status;
   Commitment      : HRA.Envelope_Commitment.Commitment_Observation;
   Commit_Diag   : HRA.Envelope_Commitment.Observe_Diagnostic;
   JPY           : constant HRA.Money.Commodity := HRA.Money.Make_Commodity ("JPY");

begin
   Put_Line ("--- Testing HRA.Envelope_Commitment ---");

   Register (Registry, "income:pension", HRA.Account.Income);
   Register (Registry, "assets:cash", HRA.Account.Asset);
   Register (Registry, "expenses:food", HRA.Account.Expense);
   Register (Registry, "expenses:rent", HRA.Account.Expense);

   Assert
     (HRA.Journal.Parse_Journal_Text (Actual_Source, Actual, Parse_Error),
      "Setup: parse Actual anchors and completion evidence");
   Assert
     (HRA.Journal.Parse_Journal_Text (Plan_Source, Plans, Parse_Error),
      "Setup: parse current and next-cycle Plans");

   Assert
     (HRA.Plan_Observation.Observe_Open_Plans
        (Plans, Plan_Source, Actual, Actual_Source,
         D ("2026-08-15"), Open_Plans, Plan_Diag),
      "Observe role-neutral open Plans once");
   Assert
     (Natural (Open_Plans.Length) = 5,
      "Explicit Actual completion removes one Plan without date matching");

   Assert
     (HRA.Cycle_Observation.Resolve_Current
        (D ("2026-08-15"), Actual, Open_Plans, Registry, Income_Acc,
         Window, Cycle_Status),
      "Resolve income-anchor current cycle");
   Assert
     (HRA.Dates.Image (HRA.Cycle_Observation.Start_Date (Window)) = "2026-08-14"
        and then HRA.Dates.Image (HRA.Cycle_Observation.End_Exclusive (Window)) = "2026-10-15",
      "Cycle uses latest Actual anchor and first future Plan anchor");

   Env_Names.Append ("food");
   Assert
     (HRA.Envelope.Admit_Registry (Env_Names, Env_Registry, Env_Diag),
      "Admit Envelope registry");
   Assert
     (HRA.Envelope.Lookup (Env_Registry, "food", Food_Env),
      "Lookup food Envelope");

   Assert
     (HRA.Fulfillment_Routing.Admit
        (HRA.Fulfillment_Routing.Decision_Vectors.Empty_Vector,
         HRA.Plan.Empty_Plan_Id_Universe,
         Env_Registry,
         Fulfill_History,
         Fulfill_Status)
      and then Fulfill_Status = HRA.Fulfillment_Routing.Success,
      "Setup: admit empty Fulfillment routing history");

   Route_Entries.Append
     (HRA.Envelope_Routing.Routing_Entry'
        (Effective => HRA.Envelope_Routing.Initial_Effective_Date,
         Expense   => HRA.Account.Make_Account ("expenses:food"),
         Route     => HRA.Envelope_Routing.Managed_Route (Food_Env),
         Note      => Null_Unbounded_String));
   Route_Entries.Append
     (HRA.Envelope_Routing.Routing_Entry'
        (Effective => HRA.Envelope_Routing.Dated_Effective (D ("2026-09-01")),
         Expense   => HRA.Account.Make_Account ("expenses:rent"),
         Route     => HRA.Envelope_Routing.Managed_Route (Food_Env),
         Note      => To_Unbounded_String ("future route must not rewrite August")));
   Assert
     (HRA.Envelope_Routing.Admit
        (Route_Entries, Env_Registry, Routing, Route_Status),
      "Admit historical Expense routing");
   Assert
     (HRA.Envelope_Routing.Has_Routing
        (Routing, HRA.Account.Make_Account ("expenses:rent"))
        and then not HRA.Envelope_Routing.Has_Routing_At
          (Routing, HRA.Account.Make_Account ("expenses:rent"), D ("2026-08-15")),
      "Future-only route is not applicable to an earlier observation");

   Assert
     (HRA.Envelope_Commitment.Observe
        (Open_Plans, Registry, Routing, Fulfill_History, Window, D ("2026-08-15"),
         Commitment, Commit_Diag),
      "Observe current-cycle Envelope commitments");
   Assert
     (HRA.Money.Lookup_Balance
        (HRA.Envelope_Commitment.Commitment_For (Commitment, Food_Env), JPY)
        = 300.0,
      "Managed commitment includes overdue plus upcoming current-cycle Plans");
   Assert
     (Commitment.Unrouted.Contains ("expenses:rent")
        and then HRA.Money.Lookup_Balance
          (Commitment.Unrouted.Element ("expenses:rent"), JPY) = 300.0,
      "Future-only Expense route remains unrouted before activation");
   Assert
     (HRA.Money.Lookup_Balance
        (HRA.Envelope_Commitment.Commitment_For (Commitment, Food_Env), JPY)
        = 300.0,
      "Next-cycle Plan is excluded at the end-exclusive boundary");

   declare
      Policy_Config : HRA.Budget_Config.Budget_Policy;
      Config_Diag   : HRA.Config_Support.Config_Diagnostic;
      Policy        : HRA.Backing_Policy.Backing_Policy;
      Policy_Status : HRA.Backing_Policy.Policy_Status;
      Entitlement   : HRA.Envelope_Entitlement.Entitlement_Observation :=
        HRA.Envelope_Entitlement.Empty_Observation;
      Consumption   : constant HRA.Envelope_Consumption.Envelope_Consumption :=
        HRA.Envelope_Consumption.Empty_Consumption;
      Funding       : HRA.Backing_Policy.Funding_Commitment_Observation;
      Backing       : HRA.Backing_Policy.Backing_Observation;
      Positions     : HRA.Envelope_Position.Observation;
      Pos_Diag      : HRA.Envelope_Position.Observe_Diagnostic;
      Claim         : HRA.Envelope_Position.Position;
      Position      : HRA.Backing_Policy.Backing_Pool_Position;
   begin
      Assert
        (HRA.Budget_Config.Parse_Budget_Policy
           (Budget_TOML, Policy_Config, Config_Diag),
         "Setup: parse backing policy for commitment headroom");
      Assert
        (HRA.Backing_Policy.Admit_Backing_Policy
           (Policy_Config, Env_Registry, Policy, Policy_Status)
           and then Policy_Status = HRA.Backing_Policy.Success,
         "Setup: admit backing policy for commitment headroom");

      Entitlement := HRA.Envelope_Entitlement.Fold_Movement
        (Entitlement,
         (Kind    => HRA.Envelope_Entitlement.Grant_From_Unallocated,
          Tx_Date => D ("2026-08-14"),
          Amt     => HRA.Money.Make_Amount (JPY, 1000.0),
          Target  => Food_Env));

      Assert
        (HRA.Envelope_Position.Observe
           (Policy_Config,
            Env_Registry,
            Entitlement,
            Consumption,
            HRA.Envelope_Fulfillment.Empty_Fulfillment (D ("2026-08-15")),
            Commitment,
            Positions,
            Pos_Diag),
         "Observe Envelope positions for commitment");

      Claim := HRA.Envelope_Position.Position_For (Positions, Food_Env);

      Funding := HRA.Backing_Policy.Observe_Funding_Commitment
        (Policy, Open_Plans, Window);
      Backing := HRA.Backing_Policy.Observe_Backing
        (Policy,
         Actual,
         D ("2026-08-15"),
         Positions,
         Funding);
      Position := HRA.Backing_Policy.Position_For (Backing, "liquid");

      Assert
        (HRA.Money.Lookup_Balance (Claim.Remaining, JPY) = 1000.0,
         "Envelope position keeps pre-Plan Remaining at 1,000 JPY");
      Assert
        (HRA.Money.Lookup_Balance (Claim.Headroom, JPY) = 700.0,
         "Envelope position deducts 300 JPY Envelope Plan reserve from Headroom");
      Assert
        (HRA.Money.Lookup_Balance (Position.Funding_Balance, JPY) = 1950.0,
         "Backing sees 1,950 JPY observed Asset funding");
      Assert
        (HRA.Money.Lookup_Balance (Position.Funding_Commitment, JPY) = 600.0,
         "Backing reserves 600 JPY from current-cycle negative Asset Plans");
      Assert
        (HRA.Money.Lookup_Balance
           (HRA.Backing_Policy.Available_Surplus (Position), JPY) = 650.0,
         "Available surplus reconciles funding commitment and Plan headroom");

      declare
         Future_Ledger : HRA.Ledger.Ledger := Actual;
         Future_Only   : HRA.Ledger.Ledger;
         Future_Text   : constant String :=
           "2026-08-16 Future funding" & ASCII.LF &
           "    assets:cash         500 JPY" & ASCII.LF &
           "    income:pension     -500 JPY" & ASCII.LF;
      begin
         Assert
           (HRA.Journal.Parse_Journal_Text
              (Future_Text, Future_Only, Parse_Error),
            "Setup: parse future Actual funding");
         Future_Ledger.Transactions.Append
           (Future_Only.Transactions.Element (1));

         Backing := HRA.Backing_Policy.Observe_Backing
           (Policy,
            Future_Ledger,
            D ("2026-08-15"),
            Positions,
            Funding);
         Position := HRA.Backing_Policy.Position_For (Backing, "liquid");
         Assert
           (HRA.Money.Lookup_Balance (Position.Funding_Balance, JPY) = 1950.0,
            "Future Actual funding does not leak into past Backing observation");

         Backing := HRA.Backing_Policy.Observe_Backing
           (Policy,
            Future_Ledger,
            D ("2026-08-16"),
            Positions,
            Funding);
         Position := HRA.Backing_Policy.Position_For (Backing, "liquid");
         Assert
           (HRA.Money.Lookup_Balance (Position.Funding_Balance, JPY) = 2450.0,
            "Funding becomes visible on its own observation day");
      end;
   end;

   Put_Line
     (Natural'Image (Passed_Count) & " passed, " &
      Natural'Image (Failed_Count) & " failed");

   if Failed_Count > 0 then
      raise Program_Error with "Envelope commitment tests failed";
   end if;
end Test_Envelope_Commitment;
