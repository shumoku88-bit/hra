with Ada.Text_IO; use Ada.Text_IO;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA.Account;
with HRA.Backing_Policy;
with HRA.Budget_Config;
with HRA.Config_Support;
with HRA.Dates;
with HRA.Envelope; use HRA.Envelope;
with HRA.Envelope_Commitment;
with HRA.Envelope_Consumption;
with HRA.Envelope_Entitlement;
with HRA.Envelope_Fulfillment;
with HRA.Envelope_Position; use HRA.Envelope_Position;
with HRA.Envelope_Report_Render;
with HRA.Household;
with HRA.Household_Config;
with HRA.Household_Report_Observation;
with HRA.Journal;
with HRA.Journal_Evidence;
with HRA.Ledger;
with HRA.Money; use HRA.Money;
with HRA.Report_Config;

procedure Test_Envelope_Position is
   use type HRA.Backing_Policy.Policy_Status;

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
      Result : HRA.Dates.Date;
      Status : HRA.Dates.Date_Status;
   begin
      if not HRA.Dates.Parse (S, Result, Status) then
         raise Program_Error with "invalid test date: " & S;
      end if;
      return Result;
   end D;

   JPY : constant Commodity := Make_Commodity ("JPY");
   USD : constant Commodity := Make_Commodity ("USD");

begin
   Put_Line ("--- Testing HRA.Envelope_Position ---");

   --  ========================================================================
   --  Law A: Standard Position
   --  Entitlement 1000, Net Consumption 300, Net Fulfillment 100,
   --  Plan Commitment 200 => Remaining 600, Headroom 400
   --  ========================================================================
   declare
      Budget_TOML : constant String :=
        "[[backing-pools]]" & ASCII.LF &
        "id = ""liquid""" & ASCII.LF &
        "asset-accounts = [""assets:cash""]" & ASCII.LF &
        "[[envelopes]]" & ASCII.LF &
        "id = ""food""" & ASCII.LF &
        "label = ""Food""" & ASCII.LF &
        "pacing = ""daily""" & ASCII.LF &
        "backing-pool = ""liquid""" & ASCII.LF;

      Policy_Config : HRA.Budget_Config.Budget_Policy;
      Config_Diag   : HRA.Config_Support.Config_Diagnostic;
      Ids           : HRA.Config_Support.String_Vectors.Vector;
      Env_Registry  : Envelope_Registry;
      Reg_Diag      : HRA.Config_Support.Config_Diagnostic;
      Food_Env      : Envelope_Id;

      Entitlement   : HRA.Envelope_Entitlement.Entitlement_Observation :=
        HRA.Envelope_Entitlement.Empty_Observation;
      Consumption   : HRA.Envelope_Consumption.Envelope_Consumption :=
        HRA.Envelope_Consumption.Empty_Consumption;
      Fulfillment   : HRA.Envelope_Fulfillment.Envelope_Fulfillment :=
        HRA.Envelope_Fulfillment.Empty_Fulfillment (D ("2026-08-15"));
      Commitment    : HRA.Envelope_Commitment.Commitment_Observation :=
        HRA.Envelope_Commitment.Empty_Observation
          (D ("2026-08-15"), D ("2026-08-15"));

      Obs           : Observation;
      Diag          : Observe_Diagnostic;
      Pos           : Position;
   begin
      Assert
        (HRA.Budget_Config.Parse_Budget_Policy
           (Budget_TOML, Policy_Config, Config_Diag),
         "Setup: parse budget policy for Law A");
      Ids.Append ("food");
      Assert
        (Admit_Registry (Ids, Env_Registry, Reg_Diag),
         "Setup: admit registry for Law A");
      Assert (Lookup (Env_Registry, "food", Food_Env), "Lookup Food_Env");

      Entitlement := HRA.Envelope_Entitlement.Fold_Movement
        (Entitlement,
         (Kind    => HRA.Envelope_Entitlement.Grant_From_Unallocated,
          Tx_Date => D ("2026-08-01"),
          Amt     => Make_Amount (JPY, 1000.0),
          Target  => Food_Env));

      Consumption.Managed.Insert
        ("food",
         HRA.Envelope_Consumption.Make_Amounts
           (Charges => Singleton_Balance (Make_Amount (JPY, 300.0)),
            Refunds => Empty_Balance));

      Fulfillment.Managed.Insert
        ("food",
         (Applied  => Singleton_Balance (Make_Amount (JPY, 100.0)),
          Reversed => Empty_Balance));

      Commitment.Managed.Insert
        ("food", Singleton_Balance (Make_Amount (JPY, 200.0)));

      Assert
        (Observe
           (Policy_Config,
            Env_Registry,
            Entitlement,
            Consumption,
            Fulfillment,
            Commitment,
            Obs,
            Diag)
           and then Diag.Status = Success,
         "Law A: Observe standard envelope position");

      Assert (Has_Position (Obs, Food_Env), "Law A: Has_Position food");
      Pos := Position_For (Obs, Food_Env);
      Assert
        (Lookup_Balance (Pos.Remaining, JPY) = 600.0,
         "Law A: Remaining = 1000 - 300 - 100 = 600 JPY");
      Assert
        (Lookup_Balance (Pos.Headroom, JPY) = 400.0,
         "Law A: Headroom = 600 - 200 = 400 JPY");
   end;

   --  ========================================================================
   --  Law B: Negative Remaining / Headroom
   --  Preserved without clamping or rejecting
   --  ========================================================================
   declare
      Policy_Config : HRA.Budget_Config.Budget_Policy;
      Config_Diag   : HRA.Config_Support.Config_Diagnostic;
      Ids           : HRA.Config_Support.String_Vectors.Vector;
      Env_Registry  : Envelope_Registry;
      Reg_Diag      : HRA.Config_Support.Config_Diagnostic;
      Food_Env      : Envelope_Id;

      Entitlement   : HRA.Envelope_Entitlement.Entitlement_Observation :=
        HRA.Envelope_Entitlement.Empty_Observation;
      Consumption   : HRA.Envelope_Consumption.Envelope_Consumption :=
        HRA.Envelope_Consumption.Empty_Consumption;
      Fulfillment   : HRA.Envelope_Fulfillment.Envelope_Fulfillment :=
        HRA.Envelope_Fulfillment.Empty_Fulfillment (D ("2026-08-15"));
      Commitment    : HRA.Envelope_Commitment.Commitment_Observation :=
        HRA.Envelope_Commitment.Empty_Observation
          (D ("2026-08-15"), D ("2026-08-15"));

      Obs           : Observation;
      Diag          : Observe_Diagnostic;
      Pos           : Position;
   begin
      Assert
        (HRA.Budget_Config.Parse_Budget_Policy
           ("[[backing-pools]]" & ASCII.LF &
            "id = ""liquid""" & ASCII.LF &
            "asset-accounts = [""assets:cash""]" & ASCII.LF &
            "[[envelopes]]" & ASCII.LF &
            "id = ""food""" & ASCII.LF &
            "label = ""Food""" & ASCII.LF &
            "pacing = ""daily""" & ASCII.LF &
            "backing-pool = ""liquid""" & ASCII.LF,
            Policy_Config,
            Config_Diag),
         "Setup: parse budget policy for Law B");
      Ids.Append ("food");
      Assert (Admit_Registry (Ids, Env_Registry, Reg_Diag), "Setup Law B");
      Assert (Lookup (Env_Registry, "food", Food_Env), "Lookup Food_Env");

      Entitlement := HRA.Envelope_Entitlement.Fold_Movement
        (Entitlement,
         (Kind    => HRA.Envelope_Entitlement.Grant_From_Unallocated,
          Tx_Date => D ("2026-08-01"),
          Amt     => Make_Amount (JPY, 100.0),
          Target  => Food_Env));

      Consumption.Managed.Insert
        ("food",
         HRA.Envelope_Consumption.Make_Amounts
           (Charges => Singleton_Balance (Make_Amount (JPY, 300.0)),
            Refunds => Empty_Balance));

      Fulfillment.Managed.Insert
        ("food",
         (Applied  => Singleton_Balance (Make_Amount (JPY, 100.0)),
          Reversed => Empty_Balance));

      Commitment.Managed.Insert
        ("food", Singleton_Balance (Make_Amount (JPY, 200.0)));

      Assert
        (Observe
           (Policy_Config,
            Env_Registry,
            Entitlement,
            Consumption,
            Fulfillment,
            Commitment,
            Obs,
            Diag)
           and then Diag.Status = Success,
         "Law B: Observe negative Remaining / Headroom successfully");

      Pos := Position_For (Obs, Food_Env);
      Assert
        (Lookup_Balance (Pos.Remaining, JPY) = -300.0,
         "Law B: Negative Remaining = 100 - 300 - 100 = -300 JPY preserved");
      Assert
        (Lookup_Balance (Pos.Headroom, JPY) = -500.0,
         "Law B: Negative Headroom = -300 - 200 = -500 JPY preserved");
   end;

   --  ========================================================================
   --  Law C: Signed Refund / Reversal
   --  Negative Net Consumption (refunds > charges) and negative Net Fulfillment
   --  ========================================================================
   declare
      Policy_Config : HRA.Budget_Config.Budget_Policy;
      Config_Diag   : HRA.Config_Support.Config_Diagnostic;
      Ids           : HRA.Config_Support.String_Vectors.Vector;
      Env_Registry  : Envelope_Registry;
      Reg_Diag      : HRA.Config_Support.Config_Diagnostic;
      Food_Env      : Envelope_Id;

      Entitlement   : HRA.Envelope_Entitlement.Entitlement_Observation :=
        HRA.Envelope_Entitlement.Empty_Observation;
      Consumption   : HRA.Envelope_Consumption.Envelope_Consumption :=
        HRA.Envelope_Consumption.Empty_Consumption;
      Fulfillment   : HRA.Envelope_Fulfillment.Envelope_Fulfillment :=
        HRA.Envelope_Fulfillment.Empty_Fulfillment (D ("2026-08-15"));
      Commitment    : HRA.Envelope_Commitment.Commitment_Observation :=
        HRA.Envelope_Commitment.Empty_Observation
          (D ("2026-08-15"), D ("2026-08-15"));

      Obs           : Observation;
      Diag          : Observe_Diagnostic;
      Pos           : Position;
   begin
      Assert
        (HRA.Budget_Config.Parse_Budget_Policy
           ("[[backing-pools]]" & ASCII.LF &
            "id = ""liquid""" & ASCII.LF &
            "asset-accounts = [""assets:cash""]" & ASCII.LF &
            "[[envelopes]]" & ASCII.LF &
            "id = ""food""" & ASCII.LF &
            "label = ""Food""" & ASCII.LF &
            "pacing = ""daily""" & ASCII.LF &
            "backing-pool = ""liquid""" & ASCII.LF,
            Policy_Config,
            Config_Diag),
         "Setup: parse budget policy for Law C");
      Ids.Append ("food");
      Assert (Admit_Registry (Ids, Env_Registry, Reg_Diag), "Setup Law C");
      Assert (Lookup (Env_Registry, "food", Food_Env), "Lookup Food_Env");

      Entitlement := HRA.Envelope_Entitlement.Fold_Movement
        (Entitlement,
         (Kind    => HRA.Envelope_Entitlement.Grant_From_Unallocated,
          Tx_Date => D ("2026-08-01"),
          Amt     => Make_Amount (JPY, 1000.0),
          Target  => Food_Env));

      -- Net Consumption = Charges (100) - Refunds (300) = -200
      Consumption.Managed.Insert
        ("food",
         HRA.Envelope_Consumption.Make_Amounts
           (Charges => Singleton_Balance (Make_Amount (JPY, 100.0)),
            Refunds => Singleton_Balance (Make_Amount (JPY, 300.0))));

      -- Net Fulfillment = Applied (50) - Reversed (100) = -50
      Fulfillment.Managed.Insert
        ("food",
         (Applied  => Singleton_Balance (Make_Amount (JPY, 50.0)),
          Reversed => Singleton_Balance (Make_Amount (JPY, 100.0))));

      Commitment.Managed.Insert
        ("food", Singleton_Balance (Make_Amount (JPY, 100.0)));

      Assert
        (Observe
           (Policy_Config,
            Env_Registry,
            Entitlement,
            Consumption,
            Fulfillment,
            Commitment,
            Obs,
            Diag)
           and then Diag.Status = Success,
         "Law C: Observe with negative net consumption and fulfillment");

      Pos := Position_For (Obs, Food_Env);
      -- Remaining = 1000 - (-200) - (-50) = 1250
      Assert
        (Lookup_Balance (Pos.Remaining, JPY) = 1250.0,
         "Law C: Remaining = 1000 - (-200) - (-50) = 1,250 JPY");
      -- Headroom = 1250 - 100 = 1150
      Assert
        (Lookup_Balance (Pos.Headroom, JPY) = 1150.0,
         "Law C: Headroom = 1250 - 100 = 1,150 JPY");
   end;

   --  ========================================================================
   --  Law D: Multi-Commodity
   --  Independent evaluation for JPY and USD without cross-currency cancellation
   --  ========================================================================
   declare
      Policy_Config : HRA.Budget_Config.Budget_Policy;
      Config_Diag   : HRA.Config_Support.Config_Diagnostic;
      Ids           : HRA.Config_Support.String_Vectors.Vector;
      Env_Registry  : Envelope_Registry;
      Reg_Diag      : HRA.Config_Support.Config_Diagnostic;
      Food_Env      : Envelope_Id;

      Entitlement   : HRA.Envelope_Entitlement.Entitlement_Observation :=
        HRA.Envelope_Entitlement.Empty_Observation;
      Consumption   : HRA.Envelope_Consumption.Envelope_Consumption :=
        HRA.Envelope_Consumption.Empty_Consumption;
      Fulfillment   : HRA.Envelope_Fulfillment.Envelope_Fulfillment :=
        HRA.Envelope_Fulfillment.Empty_Fulfillment (D ("2026-08-15"));
      Commitment    : HRA.Envelope_Commitment.Commitment_Observation :=
        HRA.Envelope_Commitment.Empty_Observation
          (D ("2026-08-15"), D ("2026-08-15"));

      Obs           : Observation;
      Diag          : Observe_Diagnostic;
      Pos           : Position;
      Cons_Bal      : Balance := Empty_Balance;
      Ful_Bal       : Balance := Empty_Balance;
      Plan_Bal      : Balance := Empty_Balance;
   begin
      Assert
        (HRA.Budget_Config.Parse_Budget_Policy
           ("[[backing-pools]]" & ASCII.LF &
            "id = ""liquid""" & ASCII.LF &
            "asset-accounts = [""assets:cash""]" & ASCII.LF &
            "[[envelopes]]" & ASCII.LF &
            "id = ""food""" & ASCII.LF &
            "label = ""Food""" & ASCII.LF &
            "pacing = ""daily""" & ASCII.LF &
            "backing-pool = ""liquid""" & ASCII.LF,
            Policy_Config,
            Config_Diag),
         "Setup: parse budget policy for Law D");
      Ids.Append ("food");
      Assert (Admit_Registry (Ids, Env_Registry, Reg_Diag), "Setup Law D");
      Assert (Lookup (Env_Registry, "food", Food_Env), "Lookup Food_Env");

      Entitlement := HRA.Envelope_Entitlement.Fold_Movement
        (Entitlement,
         (Kind    => HRA.Envelope_Entitlement.Grant_From_Unallocated,
          Tx_Date => D ("2026-08-01"),
          Amt     => Make_Amount (JPY, 1000.0),
          Target  => Food_Env));
      Entitlement := HRA.Envelope_Entitlement.Fold_Movement
        (Entitlement,
         (Kind    => HRA.Envelope_Entitlement.Grant_From_Unallocated,
          Tx_Date => D ("2026-08-01"),
          Amt     => Make_Amount (USD, 50.0),
          Target  => Food_Env));

      Cons_Bal := Add_Balance
        (Singleton_Balance (Make_Amount (JPY, 300.0)),
         Singleton_Balance (Make_Amount (USD, 10.0)));
      Consumption.Managed.Insert
        ("food",
         HRA.Envelope_Consumption.Make_Amounts
           (Charges => Cons_Bal, Refunds => Empty_Balance));

      Ful_Bal := Add_Balance
        (Singleton_Balance (Make_Amount (JPY, 100.0)),
         Singleton_Balance (Make_Amount (USD, 5.0)));
      Fulfillment.Managed.Insert
        ("food",
         (Applied  => Ful_Bal,
          Reversed => Empty_Balance));

      Plan_Bal := Add_Balance
        (Singleton_Balance (Make_Amount (JPY, 200.0)),
         Singleton_Balance (Make_Amount (USD, 10.0)));
      Commitment.Managed.Insert ("food", Plan_Bal);

      Assert
        (Observe
           (Policy_Config,
            Env_Registry,
            Entitlement,
            Consumption,
            Fulfillment,
            Commitment,
            Obs,
            Diag)
           and then Diag.Status = Success,
         "Law D: Multi-Commodity observation");

      Pos := Position_For (Obs, Food_Env);
      -- JPY: 1000 - 300 - 100 = 600, Headroom = 600 - 200 = 400
      Assert
        (Lookup_Balance (Pos.Remaining, JPY) = 600.0,
         "Law D: JPY Remaining = 600");
      Assert
        (Lookup_Balance (Pos.Headroom, JPY) = 400.0,
         "Law D: JPY Headroom = 400");

      -- USD: 50 - 10 - 5 = 35, Headroom = 35 - 10 = 25
      Assert
        (Lookup_Balance (Pos.Remaining, USD) = 35.0,
         "Law D: USD Remaining = 35");
      Assert
        (Lookup_Balance (Pos.Headroom, USD) = 25.0,
         "Law D: USD Headroom = 25");
   end;

   --  ========================================================================
   --  Law E: Coordinate Union Cancellation Law
   --  Commodity present in Entitlement and Consumption cancels to zero,
   --  yet evaluated from coordinate union.
   --  Another Commodity present ONLY in Plan Commitment produces 0 Remaining
   --  and negative Headroom.
   --  ========================================================================
   declare
      Policy_Config : HRA.Budget_Config.Budget_Policy;
      Config_Diag   : HRA.Config_Support.Config_Diagnostic;
      Ids           : HRA.Config_Support.String_Vectors.Vector;
      Env_Registry  : Envelope_Registry;
      Reg_Diag      : HRA.Config_Support.Config_Diagnostic;
      Food_Env      : Envelope_Id;

      Entitlement   : HRA.Envelope_Entitlement.Entitlement_Observation :=
        HRA.Envelope_Entitlement.Empty_Observation;
      Consumption   : HRA.Envelope_Consumption.Envelope_Consumption :=
        HRA.Envelope_Consumption.Empty_Consumption;
      Fulfillment   : constant HRA.Envelope_Fulfillment.Envelope_Fulfillment :=
        HRA.Envelope_Fulfillment.Empty_Fulfillment (D ("2026-08-15"));
      Commitment    : HRA.Envelope_Commitment.Commitment_Observation :=
        HRA.Envelope_Commitment.Empty_Observation
          (D ("2026-08-15"), D ("2026-08-15"));

      Obs           : Observation;
      Diag          : Observe_Diagnostic;
      Pos           : Position;
   begin
      Assert
        (HRA.Budget_Config.Parse_Budget_Policy
           ("[[backing-pools]]" & ASCII.LF &
            "id = ""liquid""" & ASCII.LF &
            "asset-accounts = [""assets:cash""]" & ASCII.LF &
            "[[envelopes]]" & ASCII.LF &
            "id = ""food""" & ASCII.LF &
            "label = ""Food""" & ASCII.LF &
            "pacing = ""daily""" & ASCII.LF &
            "backing-pool = ""liquid""" & ASCII.LF,
            Policy_Config,
            Config_Diag),
         "Setup: parse budget policy for Law E");
      Ids.Append ("food");
      Assert (Admit_Registry (Ids, Env_Registry, Reg_Diag), "Setup Law E");
      Assert (Lookup (Env_Registry, "food", Food_Env), "Lookup Food_Env");

      -- JPY: Entitlement 500, Consumption 500 => Remaining = 0, Headroom = 0
      Entitlement := HRA.Envelope_Entitlement.Fold_Movement
        (Entitlement,
         (Kind    => HRA.Envelope_Entitlement.Grant_From_Unallocated,
          Tx_Date => D ("2026-08-01"),
          Amt     => Make_Amount (JPY, 500.0),
          Target  => Food_Env));

      Consumption.Managed.Insert
        ("food",
         HRA.Envelope_Consumption.Make_Amounts
           (Charges => Singleton_Balance (Make_Amount (JPY, 500.0)),
            Refunds => Empty_Balance));

      -- USD: Only in Plan Commitment (100 USD)
      Commitment.Managed.Insert
        ("food", Singleton_Balance (Make_Amount (USD, 100.0)));

      Assert
        (Observe
           (Policy_Config,
            Env_Registry,
            Entitlement,
            Consumption,
            Fulfillment,
            Commitment,
            Obs,
            Diag)
           and then Diag.Status = Success,
         "Law E: Coordinate union with cancellation and plan-only coordinate");

      Pos := Position_For (Obs, Food_Env);
      -- JPY cancels to zero
      Assert
        (Lookup_Balance (Pos.Remaining, JPY) = Zero_Quantity,
         "Law E: JPY Remaining is 0 after exact cancellation");
      Assert
        (Lookup_Balance (Pos.Headroom, JPY) = Zero_Quantity,
         "Law E: JPY Headroom is 0 after exact cancellation");

      -- USD evaluated from coordinate union: Remaining = 0, Headroom = -100
      Assert
        (Lookup_Balance (Pos.Remaining, USD) = Zero_Quantity,
         "Law E: USD Remaining is 0 when only present in Plan");
      Assert
        (Lookup_Balance (Pos.Headroom, USD) = -100.0,
         "Law E: USD Headroom is -100 when only present in Plan");
   end;

   --  ========================================================================
   --  Law F: Missing Coordinate Treated as Zero
   --  Single input coordinate has missing inputs admitted as 0 quanta
   --  ========================================================================
   declare
      Policy_Config : HRA.Budget_Config.Budget_Policy;
      Config_Diag   : HRA.Config_Support.Config_Diagnostic;
      Ids           : HRA.Config_Support.String_Vectors.Vector;
      Env_Registry  : Envelope_Registry;
      Reg_Diag      : HRA.Config_Support.Config_Diagnostic;
      Food_Env      : Envelope_Id;

      Entitlement   : HRA.Envelope_Entitlement.Entitlement_Observation :=
        HRA.Envelope_Entitlement.Empty_Observation;
      Consumption   : constant HRA.Envelope_Consumption.Envelope_Consumption :=
        HRA.Envelope_Consumption.Empty_Consumption;
      Fulfillment   : constant HRA.Envelope_Fulfillment.Envelope_Fulfillment :=
        HRA.Envelope_Fulfillment.Empty_Fulfillment (D ("2026-08-15"));
      Commitment    : constant HRA.Envelope_Commitment.Commitment_Observation :=
        HRA.Envelope_Commitment.Empty_Observation
          (D ("2026-08-15"), D ("2026-08-15"));

      Obs           : Observation;
      Diag          : Observe_Diagnostic;
      Pos           : Position;
   begin
      Assert
        (HRA.Budget_Config.Parse_Budget_Policy
           ("[[backing-pools]]" & ASCII.LF &
            "id = ""liquid""" & ASCII.LF &
            "asset-accounts = [""assets:cash""]" & ASCII.LF &
            "[[envelopes]]" & ASCII.LF &
            "id = ""food""" & ASCII.LF &
            "label = ""Food""" & ASCII.LF &
            "pacing = ""daily""" & ASCII.LF &
            "backing-pool = ""liquid""" & ASCII.LF,
            Policy_Config,
            Config_Diag),
         "Setup: parse budget policy for Law F");
      Ids.Append ("food");
      Assert (Admit_Registry (Ids, Env_Registry, Reg_Diag), "Setup Law F");
      Assert (Lookup (Env_Registry, "food", Food_Env), "Lookup Food_Env");

      -- Only Entitlement exists: 1000 JPY
      Entitlement := HRA.Envelope_Entitlement.Fold_Movement
        (Entitlement,
         (Kind    => HRA.Envelope_Entitlement.Grant_From_Unallocated,
          Tx_Date => D ("2026-08-01"),
          Amt     => Make_Amount (JPY, 1000.0),
          Target  => Food_Env));

      Assert
        (Observe
           (Policy_Config,
            Env_Registry,
            Entitlement,
            Consumption,
            Fulfillment,
            Commitment,
            Obs,
            Diag)
           and then Diag.Status = Success,
         "Law F: Missing coordinates treated as zero");

      Pos := Position_For (Obs, Food_Env);
      Assert
        (Lookup_Balance (Pos.Remaining, JPY) = 1000.0,
         "Law F: Remaining = 1000 - 0 - 0 = 1,000 JPY");
      Assert
        (Lookup_Balance (Pos.Headroom, JPY) = 1000.0,
         "Law F: Headroom = 1000 - 0 = 1,000 JPY");
   end;

   --  ========================================================================
   --  Law G: Negative Plan Commitment Failure
   --  Negative Plan Commitment is an explicit Observe failure
   --  ========================================================================
   declare
      Policy_Config : HRA.Budget_Config.Budget_Policy;
      Config_Diag   : HRA.Config_Support.Config_Diagnostic;
      Ids           : HRA.Config_Support.String_Vectors.Vector;
      Env_Registry  : Envelope_Registry;
      Reg_Diag      : HRA.Config_Support.Config_Diagnostic;
      Food_Env      : Envelope_Id;

      Entitlement   : constant HRA.Envelope_Entitlement.Entitlement_Observation :=
        HRA.Envelope_Entitlement.Empty_Observation;
      Consumption   : constant HRA.Envelope_Consumption.Envelope_Consumption :=
        HRA.Envelope_Consumption.Empty_Consumption;
      Fulfillment   : constant HRA.Envelope_Fulfillment.Envelope_Fulfillment :=
        HRA.Envelope_Fulfillment.Empty_Fulfillment (D ("2026-08-15"));
      Commitment    : HRA.Envelope_Commitment.Commitment_Observation :=
        HRA.Envelope_Commitment.Empty_Observation
          (D ("2026-08-15"), D ("2026-08-15"));

      Obs           : Observation;
      Diag          : Observe_Diagnostic;
   begin
      Assert
        (HRA.Budget_Config.Parse_Budget_Policy
           ("[[backing-pools]]" & ASCII.LF &
            "id = ""liquid""" & ASCII.LF &
            "asset-accounts = [""assets:cash""]" & ASCII.LF &
            "[[envelopes]]" & ASCII.LF &
            "id = ""food""" & ASCII.LF &
            "label = ""Food""" & ASCII.LF &
            "pacing = ""daily""" & ASCII.LF &
            "backing-pool = ""liquid""" & ASCII.LF,
            Policy_Config,
            Config_Diag),
         "Setup: parse budget policy for Law G");
      Ids.Append ("food");
      Assert (Admit_Registry (Ids, Env_Registry, Reg_Diag), "Setup Law G");
      Assert (Lookup (Env_Registry, "food", Food_Env), "Lookup Food_Env");

      -- Illegal negative Plan commitment: -100 JPY
      Commitment.Managed.Insert
        ("food", Singleton_Balance (Make_Amount (JPY, -100.0)));

      Assert
        (not Observe
           (Policy_Config,
            Env_Registry,
            Entitlement,
            Consumption,
            Fulfillment,
            Commitment,
            Obs,
            Diag),
         "Law G: Observe fails on negative Plan Commitment");

      Assert
        (Diag.Status = Negative_Plan_Commitment,
         "Law G: Diag.Status is Negative_Plan_Commitment");
      Assert
        (To_String (Diag.Envelope_Id_Text) = "food",
         "Law G: Diag captures Envelope ID 'food'");
      Assert
        (To_String (Diag.Commodity_Code) = "JPY",
         "Law G: Diag captures Commodity 'JPY'");
      Assert
        (Diag.Role = Plan_Commitment_Value,
         "Law G: Diag captures Role Plan_Commitment_Value");
   end;

   --  ========================================================================
   --  Law H: Proof Input Range Failure
   --  Quantity within Money.Quantity range but outside Atomic_Quanta range
   --  ========================================================================
   declare
      Policy_Config : HRA.Budget_Config.Budget_Policy;
      Config_Diag   : HRA.Config_Support.Config_Diagnostic;
      Ids           : HRA.Config_Support.String_Vectors.Vector;
      Env_Registry  : Envelope_Registry;
      Reg_Diag      : HRA.Config_Support.Config_Diagnostic;
      Food_Env      : Envelope_Id;

      Entitlement   : HRA.Envelope_Entitlement.Entitlement_Observation :=
        HRA.Envelope_Entitlement.Empty_Observation;
      Consumption   : constant HRA.Envelope_Consumption.Envelope_Consumption :=
        HRA.Envelope_Consumption.Empty_Consumption;
      Fulfillment   : constant HRA.Envelope_Fulfillment.Envelope_Fulfillment :=
        HRA.Envelope_Fulfillment.Empty_Fulfillment (D ("2026-08-15"));
      Commitment    : constant HRA.Envelope_Commitment.Commitment_Observation :=
        HRA.Envelope_Commitment.Empty_Observation
          (D ("2026-08-15"), D ("2026-08-15"));

      Obs           : Observation;
      Diag          : Observe_Diagnostic;
      Huge_Q        : Quantity;
   begin
      Assert
        (HRA.Budget_Config.Parse_Budget_Policy
           ("[[backing-pools]]" & ASCII.LF &
            "id = ""liquid""" & ASCII.LF &
            "asset-accounts = [""assets:cash""]" & ASCII.LF &
            "[[envelopes]]" & ASCII.LF &
            "id = ""food""" & ASCII.LF &
            "label = ""Food""" & ASCII.LF &
            "pacing = ""daily""" & ASCII.LF &
            "backing-pool = ""liquid""" & ASCII.LF,
            Policy_Config,
            Config_Diag),
         "Setup: parse budget policy for Law H");
      Ids.Append ("food");
      Assert (Admit_Registry (Ids, Env_Registry, Reg_Diag), "Setup Law H");
      Assert (Lookup (Env_Registry, "food", Food_Env), "Lookup Food_Env");

      -- Parse 100,000,000.0 which exceeds Atomic_Quanta range (~45M)
      Assert
        (Parse_Quantity ("100000000.00000000", Huge_Q),
         "Setup: parse out-of-atomic-range Quantity");

      Entitlement := HRA.Envelope_Entitlement.Fold_Movement
        (Entitlement,
         (Kind    => HRA.Envelope_Entitlement.Grant_From_Unallocated,
          Tx_Date => D ("2026-08-01"),
          Amt     => Make_Amount (JPY, Huge_Q),
          Target  => Food_Env));

      Assert
        (not Observe
           (Policy_Config,
            Env_Registry,
            Entitlement,
            Consumption,
            Fulfillment,
            Commitment,
            Obs,
            Diag),
         "Law H: Observe fails on proof input out of range");

      Assert
        (Diag.Status = Proof_Input_Out_Of_Range,
         "Law H: Diag.Status is Proof_Input_Out_Of_Range");
      Assert
        (To_String (Diag.Envelope_Id_Text) = "food",
         "Law H: Diag captures Envelope ID 'food'");
      Assert
        (To_String (Diag.Commodity_Code) = "JPY",
         "Law H: Diag captures Commodity 'JPY'");
      Assert
        (Diag.Role = Entitlement_Value,
         "Law H: Diag captures Role Entitlement_Value");
   end;

   --  ========================================================================
   --  Law I: Current vs Retired Identity
   --  Registry has current + retired envelopes; Budget_Policy has only current.
   --  Observation.Positions includes only current envelope.
   --  ========================================================================
   declare
      Policy_Config : HRA.Budget_Config.Budget_Policy;
      Config_Diag   : HRA.Config_Support.Config_Diagnostic;
      Ids           : HRA.Config_Support.String_Vectors.Vector;
      Env_Registry  : Envelope_Registry;
      Reg_Diag      : HRA.Config_Support.Config_Diagnostic;
      Food_Env      : Envelope_Id;
      Retired_Env   : Envelope_Id;

      Entitlement   : HRA.Envelope_Entitlement.Entitlement_Observation :=
        HRA.Envelope_Entitlement.Empty_Observation;
      Consumption   : constant HRA.Envelope_Consumption.Envelope_Consumption :=
        HRA.Envelope_Consumption.Empty_Consumption;
      Fulfillment   : constant HRA.Envelope_Fulfillment.Envelope_Fulfillment :=
        HRA.Envelope_Fulfillment.Empty_Fulfillment (D ("2026-08-15"));
      Commitment    : constant HRA.Envelope_Commitment.Commitment_Observation :=
        HRA.Envelope_Commitment.Empty_Observation
          (D ("2026-08-15"), D ("2026-08-15"));

      Obs           : Observation;
      Diag          : Observe_Diagnostic;
   begin
      -- Budget policy defines ONLY "food"
      Assert
        (HRA.Budget_Config.Parse_Budget_Policy
           ("[[backing-pools]]" & ASCII.LF &
            "id = ""liquid""" & ASCII.LF &
            "asset-accounts = [""assets:cash""]" & ASCII.LF &
            "[[envelopes]]" & ASCII.LF &
            "id = ""food""" & ASCII.LF &
            "label = ""Food""" & ASCII.LF &
            "pacing = ""daily""" & ASCII.LF &
            "backing-pool = ""liquid""" & ASCII.LF,
            Policy_Config,
            Config_Diag),
         "Setup: parse current-only budget policy for Law I");

      -- Registry admits BOTH "food" (current) and "vacation_2025" (retired)
      Ids.Append ("food");
      Ids.Append ("vacation_2025");
      Assert (Admit_Registry (Ids, Env_Registry, Reg_Diag), "Setup Law I");
      Assert (Lookup (Env_Registry, "food", Food_Env), "Lookup Food_Env");
      Assert
        (Lookup (Env_Registry, "vacation_2025", Retired_Env),
         "Lookup Retired_Env");

      Entitlement := HRA.Envelope_Entitlement.Fold_Movement
        (Entitlement,
         (Kind    => HRA.Envelope_Entitlement.Grant_From_Unallocated,
          Tx_Date => D ("2026-08-01"),
          Amt     => Make_Amount (JPY, 1000.0),
          Target  => Food_Env));

      -- Historical entitlement also exists on retired envelope
      Entitlement := HRA.Envelope_Entitlement.Fold_Movement
        (Entitlement,
         (Kind    => HRA.Envelope_Entitlement.Grant_From_Unallocated,
          Tx_Date => D ("2026-08-01"),
          Amt     => Make_Amount (JPY, 500.0),
          Target  => Retired_Env));

      Assert
        (Observe
           (Policy_Config,
            Env_Registry,
            Entitlement,
            Consumption,
            Fulfillment,
            Commitment,
            Obs,
            Diag)
           and then Diag.Status = Success,
         "Law I: Observe with current and retired envelopes in registry");

      -- Current envelope is present
      Assert
        (Has_Position (Obs, Food_Env),
         "Law I: Current envelope 'food' is in observed positions");
      Assert
        (Lookup_Balance (Position_For (Obs, Food_Env).Remaining, JPY) = 1000.0,
         "Law I: Current envelope position evaluates correctly");

      -- Retired envelope is NOT present in current observation
      Assert
        (not Has_Position (Obs, Retired_Env),
         "Law I: Retired envelope 'vacation_2025' is NOT in observed positions");
      Assert
        (Natural (Obs.Positions.Length) = 1,
         "Law I: Exactly 1 position observed (no retired leakage)");
   end;

   --  ========================================================================
   --  Law J: Unknown Current Envelope Fails Closed
   --  Budget policy references an envelope not admitted in Envelope_Registry
   --  ========================================================================
   declare
      Policy_Config : HRA.Budget_Config.Budget_Policy;
      Config_Diag   : HRA.Config_Support.Config_Diagnostic;
      Ids           : HRA.Config_Support.String_Vectors.Vector;
      Env_Registry  : Envelope_Registry;
      Reg_Diag      : HRA.Config_Support.Config_Diagnostic;

      Entitlement   : constant HRA.Envelope_Entitlement.Entitlement_Observation :=
        HRA.Envelope_Entitlement.Empty_Observation;
      Consumption   : constant HRA.Envelope_Consumption.Envelope_Consumption :=
        HRA.Envelope_Consumption.Empty_Consumption;
      Fulfillment   : constant HRA.Envelope_Fulfillment.Envelope_Fulfillment :=
        HRA.Envelope_Fulfillment.Empty_Fulfillment (D ("2026-08-15"));
      Commitment    : constant HRA.Envelope_Commitment.Commitment_Observation :=
        HRA.Envelope_Commitment.Empty_Observation
          (D ("2026-08-15"), D ("2026-08-15"));

      Obs           : Observation;
      Diag          : Observe_Diagnostic;
   begin
      -- Budget policy references "unknown_envelope"
      Assert
        (HRA.Budget_Config.Parse_Budget_Policy
           ("[[backing-pools]]" & ASCII.LF &
            "id = ""liquid""" & ASCII.LF &
            "asset-accounts = [""assets:cash""]" & ASCII.LF &
            "[[envelopes]]" & ASCII.LF &
            "id = ""unknown_envelope""" & ASCII.LF &
            "label = ""Unknown""" & ASCII.LF &
            "pacing = ""daily""" & ASCII.LF &
            "backing-pool = ""liquid""" & ASCII.LF,
            Policy_Config,
            Config_Diag),
         "Setup: parse budget policy with unknown envelope for Law J");

      -- Registry admits only "food"
      Ids.Append ("food");
      Assert (Admit_Registry (Ids, Env_Registry, Reg_Diag), "Setup Law J");

      Assert
        (not Observe
           (Policy_Config,
            Env_Registry,
            Entitlement,
            Consumption,
            Fulfillment,
            Commitment,
            Obs,
            Diag),
         "Law J: Observe fails closed on unknown current envelope");

      Assert
        (Diag.Status = Unknown_Current_Envelope,
         "Law J: Diag.Status is Unknown_Current_Envelope");
      Assert
        (To_String (Diag.Envelope_Id_Text) = "unknown_envelope",
         "Law J: Diag captures unknown Envelope ID");
   end;

   --  ========================================================================
   --  Base Observation View Check (Observe_Base)
   --  Base view calculates Remaining from Entitlement and stock Consumption
   --  without fulfillment or commitment
   --  ========================================================================
   declare
      Policy_Config : HRA.Budget_Config.Budget_Policy;
      Config_Diag   : HRA.Config_Support.Config_Diagnostic;
      Ids           : HRA.Config_Support.String_Vectors.Vector;
      Env_Registry  : Envelope_Registry;
      Reg_Diag      : HRA.Config_Support.Config_Diagnostic;
      Food_Env      : Envelope_Id;

      Entitlement   : HRA.Envelope_Entitlement.Entitlement_Observation :=
        HRA.Envelope_Entitlement.Empty_Observation;
      Consumption   : HRA.Envelope_Consumption.Envelope_Consumption :=
        HRA.Envelope_Consumption.Empty_Consumption;

      Obs           : Observation;
      Diag          : Observe_Diagnostic;
      Pos           : Position;
   begin
      Assert
        (HRA.Budget_Config.Parse_Budget_Policy
           ("[[backing-pools]]" & ASCII.LF &
            "id = ""liquid""" & ASCII.LF &
            "asset-accounts = [""assets:cash""]" & ASCII.LF &
            "[[envelopes]]" & ASCII.LF &
            "id = ""food""" & ASCII.LF &
            "label = ""Food""" & ASCII.LF &
            "pacing = ""daily""" & ASCII.LF &
            "backing-pool = ""liquid""" & ASCII.LF,
            Policy_Config,
            Config_Diag),
         "Setup: parse budget policy for Observe_Base");
      Ids.Append ("food");
      Assert (Admit_Registry (Ids, Env_Registry, Reg_Diag), "Setup Observe_Base");
      Assert (Lookup (Env_Registry, "food", Food_Env), "Lookup Food_Env");

      Entitlement := HRA.Envelope_Entitlement.Fold_Movement
        (Entitlement,
         (Kind    => HRA.Envelope_Entitlement.Grant_From_Unallocated,
          Tx_Date => D ("2026-08-01"),
          Amt     => Make_Amount (JPY, 1000.0),
          Target  => Food_Env));

      Consumption.Managed.Insert
        ("food",
         HRA.Envelope_Consumption.Make_Amounts
           (Charges => Singleton_Balance (Make_Amount (JPY, 300.0)),
            Refunds => Empty_Balance));

      Assert
        (Observe_Base
           (Policy_Config,
            Env_Registry,
            Entitlement,
            Consumption,
            Obs,
            Diag)
           and then Diag.Status = Success,
         "Observe_Base evaluates base positions");

      Pos := Position_For (Obs, Food_Env);
      Assert
        (Lookup_Balance (Pos.Remaining, JPY) = 700.0,
         "Observe_Base: Remaining = 1000 - 300 = 700 JPY");
      Assert
        (Lookup_Balance (Pos.Headroom, JPY) = 700.0,
         "Observe_Base: Headroom = 700 - 0 = 700 JPY");
   end;

   --  ========================================================================
   --  Law K: Backing Policy Fail-Loud on Missing Position
   --  If Backing Policy references an envelope whose position is missing
   --  from Observation, Calculate_Backing must fail loud (raises Program_Error)
   --  and never silently under-account required backing.
   --  ========================================================================
   declare
      Policy_TOML : constant String :=
        "[[backing-pools]]" & ASCII.LF &
        "id = ""liquid""" & ASCII.LF &
        "asset-accounts = [""assets:cash""]" & ASCII.LF &
        "[[envelopes]]" & ASCII.LF &
        "id = ""food""" & ASCII.LF &
        "label = ""Food""" & ASCII.LF &
        "pacing = ""daily""" & ASCII.LF &
        "backing-pool = ""liquid""" & ASCII.LF &
        "[[envelopes]]" & ASCII.LF &
        "id = ""daily""" & ASCII.LF &
        "label = ""Daily""" & ASCII.LF &
        "pacing = ""daily""" & ASCII.LF &
        "backing-pool = ""liquid""" & ASCII.LF;

      Policy_Config : HRA.Budget_Config.Budget_Policy;
      Config_Diag   : HRA.Config_Support.Config_Diagnostic;
      Backing_Spec  : HRA.Backing_Policy.Backing_Policy;
      Backing_Stat  : HRA.Backing_Policy.Policy_Status;
      Ids           : HRA.Config_Support.String_Vectors.Vector;
      Env_Registry  : Envelope_Registry;
      Reg_Diag      : HRA.Config_Support.Config_Diagnostic;
      Ledger_Inst   : constant HRA.Ledger.Ledger := HRA.Ledger.Empty_Ledger;
      Partial_Obs   : Observation := Empty_Observation;
      Food_Env      : Envelope_Id;
      Backing_Obs   : HRA.Backing_Policy.Backing_Observation;
      pragma Unreferenced (Backing_Obs);
      Failed_Loud   : Boolean := False;
   begin
      Assert
        (HRA.Budget_Config.Parse_Budget_Policy
           (Policy_TOML, Policy_Config, Config_Diag),
         "Setup: parse budget policy for Law K");
      Ids.Append ("food");
      Ids.Append ("daily");
      Assert (Admit_Registry (Ids, Env_Registry, Reg_Diag), "Setup Law K");
      Assert (Lookup (Env_Registry, "food", Food_Env), "Lookup Food_Env");
      Assert
        (HRA.Backing_Policy.Admit_Backing_Policy
           (Policy_Config, Env_Registry, Backing_Spec, Backing_Stat)
         and then Backing_Stat = HRA.Backing_Policy.Success,
         "Setup: admit backing policy for Law K");

      -- Insert only "food" into Partial_Obs, leaving "daily" missing
      Partial_Obs.Positions.Insert
        ("food",
         (Env_Id    => Food_Env,
          Remaining => Singleton_Balance (Make_Amount (JPY, 500.0)),
          Headroom  => Singleton_Balance (Make_Amount (JPY, 500.0))));

      begin
         Backing_Obs := HRA.Backing_Policy.Observe_Backing
           (Backing_Spec,
            Ledger_Inst,
            Partial_Obs);
      exception
         when Program_Error =>
            Failed_Loud := True;
      end;

      Assert
        (Failed_Loud,
         "Law K: Backing Policy fails loud on missing required envelope position");
   end;

   --  ========================================================================
   --  Law L: Temporal Entitlement Dated Observation & Rendering
   --  Day 1: Grant 100 JPY to Food
   --  Day 10: Grant 50 JPY to Food, Transfer 20 JPY from Food to Daily
   --  Observed_Through = Day 5:
   --    dated Entitlement: Food = 100, Daily = 0
   --    Remaining: Food = 100
   --    Render output: Food = 100 JPY (future +50 / -20 not visible)
   --  Observed_Through = Day 10:
   --    dated Entitlement: Food = 130, Daily = 20
   --    Remaining: Food = 130, Daily = 20
   --    Render output: Food = 130 JPY, Daily = 20 JPY
   --  ========================================================================
   declare
      Budget_TOML : constant String :=
        "[[backing-pools]]" & ASCII.LF &
        "id = ""liquid""" & ASCII.LF &
        "asset-accounts = [""assets:cash""]" & ASCII.LF &
        "[[envelopes]]" & ASCII.LF &
        "id = ""food""" & ASCII.LF &
        "label = ""Food""" & ASCII.LF &
        "pacing = ""daily""" & ASCII.LF &
        "backing-pool = ""liquid""" & ASCII.LF &
        "[[envelopes]]" & ASCII.LF &
        "id = ""daily""" & ASCII.LF &
        "label = ""Daily""" & ASCII.LF &
        "pacing = ""daily""" & ASCII.LF &
        "backing-pool = ""liquid""" & ASCII.LF;

      Household_TOML : constant String :=
        "[cycle]" & ASCII.LF &
        "mode = ""income-anchor""" & ASCII.LF &
        "income-account = ""income:salary""" & ASCII.LF &
        "[money]" & ASCII.LF &
        "primary-commodity = ""JPY""" & ASCII.LF &
        "[budget]" & ASCII.LF &
        "opening-accounts = [""budget:opening""]" & ASCII.LF &
        "unassigned-accounts = [""budget:unassigned""]" & ASCII.LF &
        "[[budget.envelopes]]" & ASCII.LF &
        "id = ""food""" & ASCII.LF &
        "allocation-account = ""budget:food""" & ASCII.LF &
        "[[budget.envelopes]]" & ASCII.LF &
        "id = ""daily""" & ASCII.LF &
        "allocation-account = ""budget:daily""" & ASCII.LF &
        "[envelope-history]" & ASCII.LF &
        "identities = [""food"", ""daily""]" & ASCII.LF &
        "expense-routing = []" & ASCII.LF &
        "fulfillment-routing = []" & ASCII.LF;

      Report_TOML : constant String :=
        "[reports.trial-balance]" & ASCII.LF &
        "as-of = ""latest""" & ASCII.LF &
        "[reports.balance-sheet]" & ASCII.LF &
        "as-of = ""latest""" & ASCII.LF &
        "[reports.profit-and-loss]" & ASCII.LF &
        "from = ""beginning""" & ASCII.LF &
        "through = ""latest""" & ASCII.LF &
        "[reports.daily-flow]" & ASCII.LF &
        "from = ""beginning""" & ASCII.LF &
        "through = ""latest""" & ASCII.LF &
        "max-date-columns = 14" & ASCII.LF &
        "[reports.monthly-accounts]" & ASCII.LF &
        "from = ""beginning""" & ASCII.LF &
        "through = ""latest""" & ASCII.LF &
        "[reports.recent-transactions]" & ASCII.LF &
        "through = ""latest""" & ASCII.LF &
        "count = 10" & ASCII.LF;

      Budget_Journal_Text : constant String :=
        "2026-08-01 Budget grant to food" & ASCII.LF &
        "    budget:unassigned      -100 JPY" & ASCII.LF &
        "    budget:food             100 JPY" & ASCII.LF &
        "" & ASCII.LF &
        "2026-08-10 Future grant to food" & ASCII.LF &
        "    budget:unassigned       -50 JPY" & ASCII.LF &
        "    budget:food              50 JPY" & ASCII.LF &
        "" & ASCII.LF &
        "2026-08-10 Future transfer to daily" & ASCII.LF &
        "    budget:food             -20 JPY" & ASCII.LF &
        "    budget:daily             20 JPY" & ASCII.LF;

      Actual_Journal_Text : constant String :=
        "2026-07-01 Previous Salary" & ASCII.LF &
        "    assets:cash            200000 JPY" & ASCII.LF &
        "    income:salary         -200000 JPY" & ASCII.LF &
        "" & ASCII.LF &
        "2026-08-01 Monthly Salary" & ASCII.LF &
        "    assets:cash            200000 JPY" & ASCII.LF &
        "    income:salary         -200000 JPY" & ASCII.LF;

      Plan_Journal_Text : constant String :=
        "2026-09-01 Next Month Salary" & ASCII.LF &
        "    ; plan-id: plan-next-salary" & ASCII.LF &
        "    assets:cash            200000 JPY" & ASCII.LF &
        "    income:salary         -200000 JPY" & ASCII.LF;

      State         : HRA.Household.Household_State :=
        HRA.Household.Empty_Household_State;
      Config_Diag   : HRA.Config_Support.Config_Diagnostic;
      Backing_Stat  : HRA.Backing_Policy.Policy_Status;
      Ids           : HRA.Config_Support.String_Vectors.Vector;
      Reg_Diag      : HRA.Config_Support.Config_Diagnostic;
      Journal_Diag  : HRA.Journal.Parse_Diagnostic;
      Food_Env      : Envelope_Id;
      Daily_Env     : Envelope_Id;

      procedure Reg_Acc
        (Reg  : in out HRA.Account.Account_Registry;
         Name : String;
         Cat  : HRA.Account.Account_Type)
      is
         Acc  : constant HRA.Account.Account :=
           HRA.Account.Make_Account (Name);
         Decl : constant HRA.Account.Account_Declaration :=
           HRA.Account.Declare_Account (Acc, Cat);
         Stat : HRA.Account.Registry_Status;
      begin
         if not HRA.Account.Register_Account (Reg, Decl, Stat) then
            raise Program_Error with "failed to register account: " & Name;
         end if;
      end Reg_Acc;

      Obs_Day5      : HRA.Household_Report_Observation.Report_Observation;
      Obs_Day10     : HRA.Household_Report_Observation.Report_Observation;
      Error_Msg     : Unbounded_String;
      Render_D5     : Unbounded_String;
      Render_D10    : Unbounded_String;
      Evidence_Diag : HRA.Journal_Evidence.Evidence_Diagnostic;
   begin
      Reg_Acc (State.Registry, "assets:cash", HRA.Account.Asset);
      Reg_Acc (State.Registry, "income:salary", HRA.Account.Income);
      Reg_Acc (State.Registry, "budget:opening", HRA.Account.Budget);
      Reg_Acc (State.Registry, "budget:unassigned", HRA.Account.Budget);
      Reg_Acc (State.Registry, "budget:food", HRA.Account.Budget);
      Reg_Acc (State.Registry, "budget:daily", HRA.Account.Budget);

      Assert
        (HRA.Budget_Config.Parse_Budget_Policy
           (Budget_TOML, State.Budget_Policy, Config_Diag),
         "Setup: parse budget policy for Law L");

      Ids.Append ("food");
      Ids.Append ("daily");
      Assert
        (Admit_Registry (Ids, State.Envelope_Registry, Reg_Diag),
         "Setup: admit envelope registry for Law L");
      Assert
        (Lookup (State.Envelope_Registry, "food", Food_Env),
         "Lookup Food_Env for Law L");
      Assert
        (Lookup (State.Envelope_Registry, "daily", Daily_Env),
         "Lookup Daily_Env for Law L");

      Assert
        (HRA.Backing_Policy.Admit_Backing_Policy
           (State.Budget_Policy, State.Envelope_Registry, State.Backing_Policy_Spec, Backing_Stat)
         and then Backing_Stat = HRA.Backing_Policy.Success,
         "Setup: admit backing policy for Law L");
      Assert
        (HRA.Household_Config.Parse_Household_Configuration
           (Household_TOML, State.Budget_Policy, State.Household_Policy, Config_Diag),
         "Setup: parse household config for Law L");
      Assert
        (HRA.Report_Config.Parse_Report_Configuration
           (Report_TOML, State.Report_Policy, Config_Diag),
         "Setup: parse report config for Law L");

      Assert
        (HRA.Journal.Parse_Journal_Text
           (Actual_Journal_Text, "actual.journal", State.Actual_Ledger, Journal_Diag),
         "Setup: parse actual journal for Law L");
      Assert
        (HRA.Journal_Evidence.Extract
           (Actual_Journal_Text, State.Actual_Ledger, State.Actual_Evidence, Evidence_Diag),
         "Setup: extract actual journal evidence for Law L");

      Assert
        (HRA.Journal.Parse_Journal_Text
           (Plan_Journal_Text, "plan.journal", State.Plan_Ledger, Journal_Diag),
         "Setup: parse plan journal for Law L");
      Assert
        (HRA.Journal_Evidence.Extract
           (Plan_Journal_Text, State.Plan_Ledger, State.Plan_Evidence, Evidence_Diag),
         "Setup: extract plan journal evidence for Law L");

      Assert
        (HRA.Journal.Parse_Journal_Text
           (Budget_Journal_Text, "budget.journal", State.Budget_Ledger, Journal_Diag),
         "Setup: parse budget journal for Law L");

      -- Test Day 5: 2026-08-05
      declare
         Ok_D5 : constant Boolean :=
           HRA.Household_Report_Observation.Observe
             (D ("2026-08-05"), State, Obs_Day5, Error_Msg);
      begin
         Assert (Ok_D5, "Law L: Observe Report on Day 5");
      end;

      Assert
        (Lookup_Balance
           (HRA.Envelope_Entitlement.Entitlement_For
              (Obs_Day5.Entitlement, Food_Env), JPY) = 100.0,
         "Law L: Day 5 Food Entitlement is 100 JPY");
      Assert
        (Lookup_Balance
           (HRA.Envelope_Entitlement.Entitlement_For
              (Obs_Day5.Entitlement, Daily_Env), JPY) = Zero_Quantity,
         "Law L: Day 5 Daily Entitlement is 0 JPY");
      Assert
        (Lookup_Balance
           (Position_For (Obs_Day5.Envelope_Positions, Food_Env).Remaining, JPY) = 100.0,
         "Law L: Day 5 Food Remaining is 100 JPY");
      Assert
        (Lookup_Balance
           (Position_For (Obs_Day5.Envelope_Positions, Daily_Env).Remaining, JPY) = Zero_Quantity,
         "Law L: Day 5 Daily Remaining is 0 JPY");

      Render_D5 := To_Unbounded_String
        (HRA.Envelope_Report_Render.Render (Obs_Day5.Envelope_Report));
      Assert
        (Ada.Strings.Fixed.Index (To_String (Render_D5), "food | 100 JPY") > 0,
         "Law L: Day 5 render contains 'food | 100 JPY'");
      Assert
        (Ada.Strings.Fixed.Index (To_String (Render_D5), "daily | 0") > 0,
         "Law L: Day 5 render contains 'daily | 0'");
      Assert
        (Ada.Strings.Fixed.Index (To_String (Render_D5), "130 JPY") = 0,
         "Law L: Day 5 render excludes future 130 JPY");
      Assert
        (Ada.Strings.Fixed.Index (To_String (Render_D5), "150 JPY") = 0,
         "Law L: Day 5 render excludes future 150 JPY");

      -- Test Day 10: 2026-08-10
      Assert
        (HRA.Household_Report_Observation.Observe
           (D ("2026-08-10"), State, Obs_Day10, Error_Msg),
         "Law L: Observe Report on Day 10");

      Assert
        (Lookup_Balance
           (HRA.Envelope_Entitlement.Entitlement_For
              (Obs_Day10.Entitlement, Food_Env), JPY) = 130.0,
         "Law L: Day 10 Food Entitlement is 130 JPY (100 + 50 - 20)");
      Assert
        (Lookup_Balance
           (HRA.Envelope_Entitlement.Entitlement_For
              (Obs_Day10.Entitlement, Daily_Env), JPY) = 20.0,
         "Law L: Day 10 Daily Entitlement is 20 JPY");
      Assert
        (Lookup_Balance
           (Position_For (Obs_Day10.Envelope_Positions, Food_Env).Remaining, JPY) = 130.0,
         "Law L: Day 10 Food Remaining is 130 JPY");
      Assert
        (Lookup_Balance
           (Position_For (Obs_Day10.Envelope_Positions, Daily_Env).Remaining, JPY) = 20.0,
         "Law L: Day 10 Daily Remaining is 20 JPY");

      Render_D10 := To_Unbounded_String
        (HRA.Envelope_Report_Render.Render (Obs_Day10.Envelope_Report));
      Assert
        (Ada.Strings.Fixed.Index (To_String (Render_D10), "food | 130 JPY") > 0,
         "Law L: Day 10 render contains 'food | 130 JPY'");
      Assert
        (Ada.Strings.Fixed.Index (To_String (Render_D10), "daily | 20 JPY") > 0,
         "Law L: Day 10 render contains 'daily | 20 JPY'");
      Assert
        (Ada.Strings.Fixed.Index
           (To_String (Render_D10), "Signed envelope total | 150 JPY") > 0,
         "Law L: Day 10 render signed envelope total is 150 JPY");
   end;

   Put_Line
     (Natural'Image (Passed_Count) & " passed, " &
      Natural'Image (Failed_Count) & " failed");

   if Failed_Count > 0 then
      raise Program_Error with "Envelope position tests failed";
   end if;
end Test_Envelope_Position;
