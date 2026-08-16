with Ada.Text_IO; use Ada.Text_IO;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with ALedger.Budget_Config;
with ALedger.Config_Support;
with ALedger.Dates;
with ALedger.Envelope; use ALedger.Envelope;
with ALedger.Envelope_Commitment;
with ALedger.Envelope_Consumption;
with ALedger.Envelope_Entitlement;
with ALedger.Envelope_Fulfillment;
with ALedger.Envelope_Position; use ALedger.Envelope_Position;
with ALedger.Money; use ALedger.Money;

procedure Test_Envelope_Position is
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
      Result : ALedger.Dates.Date;
      Status : ALedger.Dates.Date_Status;
   begin
      if not ALedger.Dates.Parse (S, Result, Status) then
         raise Program_Error with "invalid test date: " & S;
      end if;
      return Result;
   end D;

   JPY : constant Commodity := Make_Commodity ("JPY");
   USD : constant Commodity := Make_Commodity ("USD");

begin
   Put_Line ("--- Testing ALedger.Envelope_Position ---");

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

      Policy_Config : ALedger.Budget_Config.Budget_Policy;
      Config_Diag   : ALedger.Config_Support.Config_Diagnostic;
      Ids           : ALedger.Config_Support.String_Vectors.Vector;
      Env_Registry  : Envelope_Registry;
      Reg_Diag      : ALedger.Config_Support.Config_Diagnostic;
      Food_Env      : Envelope_Id;

      Entitlement   : ALedger.Envelope_Entitlement.Entitlement_Observation :=
        ALedger.Envelope_Entitlement.Empty_Observation;
      Consumption   : ALedger.Envelope_Consumption.Envelope_Consumption :=
        ALedger.Envelope_Consumption.Empty_Consumption;
      Fulfillment   : ALedger.Envelope_Fulfillment.Envelope_Fulfillment :=
        ALedger.Envelope_Fulfillment.Empty_Fulfillment (D ("2026-08-15"));
      Commitment    : ALedger.Envelope_Commitment.Commitment_Observation :=
        ALedger.Envelope_Commitment.Empty_Observation
          (D ("2026-08-15"), D ("2026-08-15"));

      Obs           : Observation;
      Diag          : Observe_Diagnostic;
      Pos           : Position;
   begin
      Assert
        (ALedger.Budget_Config.Parse_Budget_Policy
           (Budget_TOML, Policy_Config, Config_Diag),
         "Setup: parse budget policy for Law A");
      Ids.Append ("food");
      Assert
        (Admit_Registry (Ids, Env_Registry, Reg_Diag),
         "Setup: admit registry for Law A");
      Assert (Lookup (Env_Registry, "food", Food_Env), "Lookup Food_Env");

      Entitlement := ALedger.Envelope_Entitlement.Fold_Movement
        (Entitlement,
         (Kind    => ALedger.Envelope_Entitlement.Grant_From_Unallocated,
          Tx_Date => D ("2026-08-01"),
          Amt     => Make_Amount (JPY, 1000.0),
          Target  => Food_Env));

      Consumption.Managed.Insert
        ("food",
         ALedger.Envelope_Consumption.Make_Amounts
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
      Policy_Config : ALedger.Budget_Config.Budget_Policy;
      Config_Diag   : ALedger.Config_Support.Config_Diagnostic;
      Ids           : ALedger.Config_Support.String_Vectors.Vector;
      Env_Registry  : Envelope_Registry;
      Reg_Diag      : ALedger.Config_Support.Config_Diagnostic;
      Food_Env      : Envelope_Id;

      Entitlement   : ALedger.Envelope_Entitlement.Entitlement_Observation :=
        ALedger.Envelope_Entitlement.Empty_Observation;
      Consumption   : ALedger.Envelope_Consumption.Envelope_Consumption :=
        ALedger.Envelope_Consumption.Empty_Consumption;
      Fulfillment   : ALedger.Envelope_Fulfillment.Envelope_Fulfillment :=
        ALedger.Envelope_Fulfillment.Empty_Fulfillment (D ("2026-08-15"));
      Commitment    : ALedger.Envelope_Commitment.Commitment_Observation :=
        ALedger.Envelope_Commitment.Empty_Observation
          (D ("2026-08-15"), D ("2026-08-15"));

      Obs           : Observation;
      Diag          : Observe_Diagnostic;
      Pos           : Position;
   begin
      Assert
        (ALedger.Budget_Config.Parse_Budget_Policy
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

      Entitlement := ALedger.Envelope_Entitlement.Fold_Movement
        (Entitlement,
         (Kind    => ALedger.Envelope_Entitlement.Grant_From_Unallocated,
          Tx_Date => D ("2026-08-01"),
          Amt     => Make_Amount (JPY, 100.0),
          Target  => Food_Env));

      Consumption.Managed.Insert
        ("food",
         ALedger.Envelope_Consumption.Make_Amounts
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
      Policy_Config : ALedger.Budget_Config.Budget_Policy;
      Config_Diag   : ALedger.Config_Support.Config_Diagnostic;
      Ids           : ALedger.Config_Support.String_Vectors.Vector;
      Env_Registry  : Envelope_Registry;
      Reg_Diag      : ALedger.Config_Support.Config_Diagnostic;
      Food_Env      : Envelope_Id;

      Entitlement   : ALedger.Envelope_Entitlement.Entitlement_Observation :=
        ALedger.Envelope_Entitlement.Empty_Observation;
      Consumption   : ALedger.Envelope_Consumption.Envelope_Consumption :=
        ALedger.Envelope_Consumption.Empty_Consumption;
      Fulfillment   : ALedger.Envelope_Fulfillment.Envelope_Fulfillment :=
        ALedger.Envelope_Fulfillment.Empty_Fulfillment (D ("2026-08-15"));
      Commitment    : ALedger.Envelope_Commitment.Commitment_Observation :=
        ALedger.Envelope_Commitment.Empty_Observation
          (D ("2026-08-15"), D ("2026-08-15"));

      Obs           : Observation;
      Diag          : Observe_Diagnostic;
      Pos           : Position;
   begin
      Assert
        (ALedger.Budget_Config.Parse_Budget_Policy
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

      Entitlement := ALedger.Envelope_Entitlement.Fold_Movement
        (Entitlement,
         (Kind    => ALedger.Envelope_Entitlement.Grant_From_Unallocated,
          Tx_Date => D ("2026-08-01"),
          Amt     => Make_Amount (JPY, 1000.0),
          Target  => Food_Env));

      -- Net Consumption = Charges (100) - Refunds (300) = -200
      Consumption.Managed.Insert
        ("food",
         ALedger.Envelope_Consumption.Make_Amounts
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
      Policy_Config : ALedger.Budget_Config.Budget_Policy;
      Config_Diag   : ALedger.Config_Support.Config_Diagnostic;
      Ids           : ALedger.Config_Support.String_Vectors.Vector;
      Env_Registry  : Envelope_Registry;
      Reg_Diag      : ALedger.Config_Support.Config_Diagnostic;
      Food_Env      : Envelope_Id;

      Entitlement   : ALedger.Envelope_Entitlement.Entitlement_Observation :=
        ALedger.Envelope_Entitlement.Empty_Observation;
      Consumption   : ALedger.Envelope_Consumption.Envelope_Consumption :=
        ALedger.Envelope_Consumption.Empty_Consumption;
      Fulfillment   : ALedger.Envelope_Fulfillment.Envelope_Fulfillment :=
        ALedger.Envelope_Fulfillment.Empty_Fulfillment (D ("2026-08-15"));
      Commitment    : ALedger.Envelope_Commitment.Commitment_Observation :=
        ALedger.Envelope_Commitment.Empty_Observation
          (D ("2026-08-15"), D ("2026-08-15"));

      Obs           : Observation;
      Diag          : Observe_Diagnostic;
      Pos           : Position;
      Cons_Bal      : Balance := Empty_Balance;
      Ful_Bal       : Balance := Empty_Balance;
      Plan_Bal      : Balance := Empty_Balance;
   begin
      Assert
        (ALedger.Budget_Config.Parse_Budget_Policy
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

      Entitlement := ALedger.Envelope_Entitlement.Fold_Movement
        (Entitlement,
         (Kind    => ALedger.Envelope_Entitlement.Grant_From_Unallocated,
          Tx_Date => D ("2026-08-01"),
          Amt     => Make_Amount (JPY, 1000.0),
          Target  => Food_Env));
      Entitlement := ALedger.Envelope_Entitlement.Fold_Movement
        (Entitlement,
         (Kind    => ALedger.Envelope_Entitlement.Grant_From_Unallocated,
          Tx_Date => D ("2026-08-01"),
          Amt     => Make_Amount (USD, 50.0),
          Target  => Food_Env));

      Cons_Bal := Add_Balance
        (Singleton_Balance (Make_Amount (JPY, 300.0)),
         Singleton_Balance (Make_Amount (USD, 10.0)));
      Consumption.Managed.Insert
        ("food",
         ALedger.Envelope_Consumption.Make_Amounts
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
      Policy_Config : ALedger.Budget_Config.Budget_Policy;
      Config_Diag   : ALedger.Config_Support.Config_Diagnostic;
      Ids           : ALedger.Config_Support.String_Vectors.Vector;
      Env_Registry  : Envelope_Registry;
      Reg_Diag      : ALedger.Config_Support.Config_Diagnostic;
      Food_Env      : Envelope_Id;

      Entitlement   : ALedger.Envelope_Entitlement.Entitlement_Observation :=
        ALedger.Envelope_Entitlement.Empty_Observation;
      Consumption   : ALedger.Envelope_Consumption.Envelope_Consumption :=
        ALedger.Envelope_Consumption.Empty_Consumption;
      Fulfillment   : constant ALedger.Envelope_Fulfillment.Envelope_Fulfillment :=
        ALedger.Envelope_Fulfillment.Empty_Fulfillment (D ("2026-08-15"));
      Commitment    : ALedger.Envelope_Commitment.Commitment_Observation :=
        ALedger.Envelope_Commitment.Empty_Observation
          (D ("2026-08-15"), D ("2026-08-15"));

      Obs           : Observation;
      Diag          : Observe_Diagnostic;
      Pos           : Position;
   begin
      Assert
        (ALedger.Budget_Config.Parse_Budget_Policy
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
      Entitlement := ALedger.Envelope_Entitlement.Fold_Movement
        (Entitlement,
         (Kind    => ALedger.Envelope_Entitlement.Grant_From_Unallocated,
          Tx_Date => D ("2026-08-01"),
          Amt     => Make_Amount (JPY, 500.0),
          Target  => Food_Env));

      Consumption.Managed.Insert
        ("food",
         ALedger.Envelope_Consumption.Make_Amounts
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
      Policy_Config : ALedger.Budget_Config.Budget_Policy;
      Config_Diag   : ALedger.Config_Support.Config_Diagnostic;
      Ids           : ALedger.Config_Support.String_Vectors.Vector;
      Env_Registry  : Envelope_Registry;
      Reg_Diag      : ALedger.Config_Support.Config_Diagnostic;
      Food_Env      : Envelope_Id;

      Entitlement   : ALedger.Envelope_Entitlement.Entitlement_Observation :=
        ALedger.Envelope_Entitlement.Empty_Observation;
      Consumption   : constant ALedger.Envelope_Consumption.Envelope_Consumption :=
        ALedger.Envelope_Consumption.Empty_Consumption;
      Fulfillment   : constant ALedger.Envelope_Fulfillment.Envelope_Fulfillment :=
        ALedger.Envelope_Fulfillment.Empty_Fulfillment (D ("2026-08-15"));
      Commitment    : constant ALedger.Envelope_Commitment.Commitment_Observation :=
        ALedger.Envelope_Commitment.Empty_Observation
          (D ("2026-08-15"), D ("2026-08-15"));

      Obs           : Observation;
      Diag          : Observe_Diagnostic;
      Pos           : Position;
   begin
      Assert
        (ALedger.Budget_Config.Parse_Budget_Policy
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
      Entitlement := ALedger.Envelope_Entitlement.Fold_Movement
        (Entitlement,
         (Kind    => ALedger.Envelope_Entitlement.Grant_From_Unallocated,
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
      Policy_Config : ALedger.Budget_Config.Budget_Policy;
      Config_Diag   : ALedger.Config_Support.Config_Diagnostic;
      Ids           : ALedger.Config_Support.String_Vectors.Vector;
      Env_Registry  : Envelope_Registry;
      Reg_Diag      : ALedger.Config_Support.Config_Diagnostic;
      Food_Env      : Envelope_Id;

      Entitlement   : constant ALedger.Envelope_Entitlement.Entitlement_Observation :=
        ALedger.Envelope_Entitlement.Empty_Observation;
      Consumption   : constant ALedger.Envelope_Consumption.Envelope_Consumption :=
        ALedger.Envelope_Consumption.Empty_Consumption;
      Fulfillment   : constant ALedger.Envelope_Fulfillment.Envelope_Fulfillment :=
        ALedger.Envelope_Fulfillment.Empty_Fulfillment (D ("2026-08-15"));
      Commitment    : ALedger.Envelope_Commitment.Commitment_Observation :=
        ALedger.Envelope_Commitment.Empty_Observation
          (D ("2026-08-15"), D ("2026-08-15"));

      Obs           : Observation;
      Diag          : Observe_Diagnostic;
   begin
      Assert
        (ALedger.Budget_Config.Parse_Budget_Policy
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
      Policy_Config : ALedger.Budget_Config.Budget_Policy;
      Config_Diag   : ALedger.Config_Support.Config_Diagnostic;
      Ids           : ALedger.Config_Support.String_Vectors.Vector;
      Env_Registry  : Envelope_Registry;
      Reg_Diag      : ALedger.Config_Support.Config_Diagnostic;
      Food_Env      : Envelope_Id;

      Entitlement   : ALedger.Envelope_Entitlement.Entitlement_Observation :=
        ALedger.Envelope_Entitlement.Empty_Observation;
      Consumption   : constant ALedger.Envelope_Consumption.Envelope_Consumption :=
        ALedger.Envelope_Consumption.Empty_Consumption;
      Fulfillment   : constant ALedger.Envelope_Fulfillment.Envelope_Fulfillment :=
        ALedger.Envelope_Fulfillment.Empty_Fulfillment (D ("2026-08-15"));
      Commitment    : constant ALedger.Envelope_Commitment.Commitment_Observation :=
        ALedger.Envelope_Commitment.Empty_Observation
          (D ("2026-08-15"), D ("2026-08-15"));

      Obs           : Observation;
      Diag          : Observe_Diagnostic;
      Huge_Q        : Quantity;
   begin
      Assert
        (ALedger.Budget_Config.Parse_Budget_Policy
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

      Entitlement := ALedger.Envelope_Entitlement.Fold_Movement
        (Entitlement,
         (Kind    => ALedger.Envelope_Entitlement.Grant_From_Unallocated,
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
      Policy_Config : ALedger.Budget_Config.Budget_Policy;
      Config_Diag   : ALedger.Config_Support.Config_Diagnostic;
      Ids           : ALedger.Config_Support.String_Vectors.Vector;
      Env_Registry  : Envelope_Registry;
      Reg_Diag      : ALedger.Config_Support.Config_Diagnostic;
      Food_Env      : Envelope_Id;
      Retired_Env   : Envelope_Id;

      Entitlement   : ALedger.Envelope_Entitlement.Entitlement_Observation :=
        ALedger.Envelope_Entitlement.Empty_Observation;
      Consumption   : constant ALedger.Envelope_Consumption.Envelope_Consumption :=
        ALedger.Envelope_Consumption.Empty_Consumption;
      Fulfillment   : constant ALedger.Envelope_Fulfillment.Envelope_Fulfillment :=
        ALedger.Envelope_Fulfillment.Empty_Fulfillment (D ("2026-08-15"));
      Commitment    : constant ALedger.Envelope_Commitment.Commitment_Observation :=
        ALedger.Envelope_Commitment.Empty_Observation
          (D ("2026-08-15"), D ("2026-08-15"));

      Obs           : Observation;
      Diag          : Observe_Diagnostic;
   begin
      -- Budget policy defines ONLY "food"
      Assert
        (ALedger.Budget_Config.Parse_Budget_Policy
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

      Entitlement := ALedger.Envelope_Entitlement.Fold_Movement
        (Entitlement,
         (Kind    => ALedger.Envelope_Entitlement.Grant_From_Unallocated,
          Tx_Date => D ("2026-08-01"),
          Amt     => Make_Amount (JPY, 1000.0),
          Target  => Food_Env));

      -- Historical entitlement also exists on retired envelope
      Entitlement := ALedger.Envelope_Entitlement.Fold_Movement
        (Entitlement,
         (Kind    => ALedger.Envelope_Entitlement.Grant_From_Unallocated,
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
      Policy_Config : ALedger.Budget_Config.Budget_Policy;
      Config_Diag   : ALedger.Config_Support.Config_Diagnostic;
      Ids           : ALedger.Config_Support.String_Vectors.Vector;
      Env_Registry  : Envelope_Registry;
      Reg_Diag      : ALedger.Config_Support.Config_Diagnostic;

      Entitlement   : constant ALedger.Envelope_Entitlement.Entitlement_Observation :=
        ALedger.Envelope_Entitlement.Empty_Observation;
      Consumption   : constant ALedger.Envelope_Consumption.Envelope_Consumption :=
        ALedger.Envelope_Consumption.Empty_Consumption;
      Fulfillment   : constant ALedger.Envelope_Fulfillment.Envelope_Fulfillment :=
        ALedger.Envelope_Fulfillment.Empty_Fulfillment (D ("2026-08-15"));
      Commitment    : constant ALedger.Envelope_Commitment.Commitment_Observation :=
        ALedger.Envelope_Commitment.Empty_Observation
          (D ("2026-08-15"), D ("2026-08-15"));

      Obs           : Observation;
      Diag          : Observe_Diagnostic;
   begin
      -- Budget policy references "unknown_envelope"
      Assert
        (ALedger.Budget_Config.Parse_Budget_Policy
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
      Policy_Config : ALedger.Budget_Config.Budget_Policy;
      Config_Diag   : ALedger.Config_Support.Config_Diagnostic;
      Ids           : ALedger.Config_Support.String_Vectors.Vector;
      Env_Registry  : Envelope_Registry;
      Reg_Diag      : ALedger.Config_Support.Config_Diagnostic;
      Food_Env      : Envelope_Id;

      Entitlement   : ALedger.Envelope_Entitlement.Entitlement_Observation :=
        ALedger.Envelope_Entitlement.Empty_Observation;
      Consumption   : ALedger.Envelope_Consumption.Envelope_Consumption :=
        ALedger.Envelope_Consumption.Empty_Consumption;

      Obs           : Observation;
      Diag          : Observe_Diagnostic;
      Pos           : Position;
   begin
      Assert
        (ALedger.Budget_Config.Parse_Budget_Policy
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

      Entitlement := ALedger.Envelope_Entitlement.Fold_Movement
        (Entitlement,
         (Kind    => ALedger.Envelope_Entitlement.Grant_From_Unallocated,
          Tx_Date => D ("2026-08-01"),
          Amt     => Make_Amount (JPY, 1000.0),
          Target  => Food_Env));

      Consumption.Managed.Insert
        ("food",
         ALedger.Envelope_Consumption.Make_Amounts
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

   Put_Line
     (Natural'Image (Passed_Count) & " passed, " &
      Natural'Image (Failed_Count) & " failed");

   if Failed_Count > 0 then
      raise Program_Error with "Envelope position tests failed";
   end if;
end Test_Envelope_Position;
