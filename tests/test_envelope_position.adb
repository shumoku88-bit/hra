with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO; use Ada.Text_IO;
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
with HRA.Ledger;
with HRA.Money; use HRA.Money;

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

   function Policy_For (Envelope_Text : String) return HRA.Budget_Config.Budget_Policy is
      Result : HRA.Budget_Config.Budget_Policy;
      Diag   : HRA.Config_Support.Config_Diagnostic;
      Text   : constant String :=
        "[[backing-pools]]" & ASCII.LF &
        "id = ""liquid""" & ASCII.LF &
        "asset-accounts = [""assets:cash""]" & ASCII.LF &
        Envelope_Text;
   begin
      if not HRA.Budget_Config.Parse_Budget_Policy (Text, Result, Diag) then
         raise Program_Error with "invalid synthetic envelope policy";
      end if;
      return Result;
   end Policy_For;

   Food_Policy : constant HRA.Budget_Config.Budget_Policy :=
     Policy_For
       ("[[envelopes]]" & ASCII.LF &
        "id = ""food""" & ASCII.LF &
        "label = ""Food""" & ASCII.LF &
        "pacing = ""daily""" & ASCII.LF &
        "backing-pool = ""liquid""" & ASCII.LF);

   Food_Daily_Policy : constant HRA.Budget_Config.Budget_Policy :=
     Policy_For
       ("[[envelopes]]" & ASCII.LF &
        "id = ""food""" & ASCII.LF &
        "label = ""Food""" & ASCII.LF &
        "pacing = ""daily""" & ASCII.LF &
        "backing-pool = ""liquid""" & ASCII.LF &
        "[[envelopes]]" & ASCII.LF &
        "id = ""daily""" & ASCII.LF &
        "label = ""Daily""" & ASCII.LF &
        "pacing = ""daily""" & ASCII.LF &
        "backing-pool = ""liquid""" & ASCII.LF);

   function Registry_For
     (Include_Daily   : Boolean := False;
      Include_Retired : Boolean := False) return Envelope_Registry
   is
      IDs    : HRA.Config_Support.String_Vectors.Vector;
      Result : Envelope_Registry;
      Diag   : HRA.Config_Support.Config_Diagnostic;
   begin
      IDs.Append ("food");
      if Include_Daily then
         IDs.Append ("daily");
      end if;
      if Include_Retired then
         IDs.Append ("vacation_2025");
      end if;
      if not Admit_Registry (IDs, Result, Diag) then
         raise Program_Error with "invalid synthetic Envelope registry";
      end if;
      return Result;
   end Registry_For;

   function E (Registry : Envelope_Registry; Name : String) return Envelope_Id is
      Result : Envelope_Id;
   begin
      if not Lookup (Registry, Name, Result) then
         raise Program_Error with "missing synthetic Envelope: " & Name;
      end if;
      return Result;
   end E;

   JPY : constant Commodity := Make_Commodity ("JPY");
   USD : constant Commodity := Make_Commodity ("USD");

begin
   Put_Line ("--- Testing HRA.Envelope_Position focused laws ---");

   -- Standard equation: Remaining = Entitlement - Consumption - Fulfillment;
   -- Headroom = Remaining - Commitment.
   declare
      Registry    : constant Envelope_Registry := Registry_For;
      Food        : constant Envelope_Id := E (Registry, "food");
      Entitlement : HRA.Envelope_Entitlement.Entitlement_Observation :=
        HRA.Envelope_Entitlement.Empty_Observation;
      Consumption : HRA.Envelope_Consumption.Envelope_Consumption :=
        HRA.Envelope_Consumption.Empty_Consumption;
      Fulfillment : HRA.Envelope_Fulfillment.Envelope_Fulfillment :=
        HRA.Envelope_Fulfillment.Empty_Fulfillment (D ("2026-08-15"));
      Commitment  : HRA.Envelope_Commitment.Commitment_Observation :=
        HRA.Envelope_Commitment.Empty_Observation
          (D ("2026-08-15"), D ("2026-08-31"));
      Obs          : Observation;
      Diag         : Observe_Diagnostic;
   begin
      Entitlement := HRA.Envelope_Entitlement.Fold_Movement
        (Entitlement,
         (Kind    => HRA.Envelope_Entitlement.Grant_From_Unallocated,
          Tx_Date => D ("2026-08-01"),
          Amt     => Make_Amount (JPY, 1000.0),
          Target  => Food));
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
           (Food_Policy, Registry, Entitlement, Consumption, Fulfillment,
            Commitment, Obs, Diag),
         "standard Position observation succeeds");
      Assert
        (Lookup_Balance (Position_For (Obs, Food).Remaining, JPY) = 600.0,
         "Remaining = 1000 - 300 - 100 = 600 JPY");
      Assert
        (Lookup_Balance (Position_For (Obs, Food).Headroom, JPY) = 400.0,
         "Headroom = 600 - 200 = 400 JPY");
   end;

   -- Negative results remain valid observations and are never clamped.
   declare
      Registry    : constant Envelope_Registry := Registry_For;
      Food        : constant Envelope_Id := E (Registry, "food");
      Entitlement : HRA.Envelope_Entitlement.Entitlement_Observation :=
        HRA.Envelope_Entitlement.Empty_Observation;
      Consumption : HRA.Envelope_Consumption.Envelope_Consumption :=
        HRA.Envelope_Consumption.Empty_Consumption;
      Fulfillment : HRA.Envelope_Fulfillment.Envelope_Fulfillment :=
        HRA.Envelope_Fulfillment.Empty_Fulfillment (D ("2026-08-15"));
      Commitment  : HRA.Envelope_Commitment.Commitment_Observation :=
        HRA.Envelope_Commitment.Empty_Observation
          (D ("2026-08-15"), D ("2026-08-31"));
      Obs          : Observation;
      Diag         : Observe_Diagnostic;
   begin
      Entitlement := HRA.Envelope_Entitlement.Fold_Movement
        (Entitlement,
         (Kind    => HRA.Envelope_Entitlement.Grant_From_Unallocated,
          Tx_Date => D ("2026-08-01"),
          Amt     => Make_Amount (JPY, 100.0),
          Target  => Food));
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
           (Food_Policy, Registry, Entitlement, Consumption, Fulfillment,
            Commitment, Obs, Diag),
         "negative Position observation succeeds");
      Assert
        (Lookup_Balance (Position_For (Obs, Food).Remaining, JPY) = -300.0
         and then Lookup_Balance (Position_For (Obs, Food).Headroom, JPY) = -500.0,
         "negative Remaining and Headroom are preserved");
   end;

   -- Signed refunds and reversals increase available stock exactly.
   declare
      Registry    : constant Envelope_Registry := Registry_For;
      Food        : constant Envelope_Id := E (Registry, "food");
      Entitlement : HRA.Envelope_Entitlement.Entitlement_Observation :=
        HRA.Envelope_Entitlement.Empty_Observation;
      Consumption : HRA.Envelope_Consumption.Envelope_Consumption :=
        HRA.Envelope_Consumption.Empty_Consumption;
      Fulfillment : HRA.Envelope_Fulfillment.Envelope_Fulfillment :=
        HRA.Envelope_Fulfillment.Empty_Fulfillment (D ("2026-08-15"));
      Commitment  : HRA.Envelope_Commitment.Commitment_Observation :=
        HRA.Envelope_Commitment.Empty_Observation
          (D ("2026-08-15"), D ("2026-08-31"));
      Obs          : Observation;
      Diag         : Observe_Diagnostic;
   begin
      Entitlement := HRA.Envelope_Entitlement.Fold_Movement
        (Entitlement,
         (Kind    => HRA.Envelope_Entitlement.Grant_From_Unallocated,
          Tx_Date => D ("2026-08-01"),
          Amt     => Make_Amount (JPY, 1000.0),
          Target  => Food));
      Consumption.Managed.Insert
        ("food",
         HRA.Envelope_Consumption.Make_Amounts
           (Charges => Singleton_Balance (Make_Amount (JPY, 100.0)),
            Refunds => Singleton_Balance (Make_Amount (JPY, 300.0))));
      Fulfillment.Managed.Insert
        ("food",
         (Applied  => Singleton_Balance (Make_Amount (JPY, 50.0)),
          Reversed => Singleton_Balance (Make_Amount (JPY, 100.0))));
      Commitment.Managed.Insert
        ("food", Singleton_Balance (Make_Amount (JPY, 100.0)));

      Assert
        (Observe
           (Food_Policy, Registry, Entitlement, Consumption, Fulfillment,
            Commitment, Obs, Diag),
         "signed refund/reversal observation succeeds");
      Assert
        (Lookup_Balance (Position_For (Obs, Food).Remaining, JPY) = 1250.0
         and then Lookup_Balance (Position_For (Obs, Food).Headroom, JPY) = 1150.0,
         "signed evidence remains exact in Remaining and Headroom");
   end;

   -- Commodity coordinates are evaluated independently, including coordinates
   -- present only in commitment evidence.
   declare
      Registry    : constant Envelope_Registry := Registry_For;
      Food        : constant Envelope_Id := E (Registry, "food");
      Entitlement : HRA.Envelope_Entitlement.Entitlement_Observation :=
        HRA.Envelope_Entitlement.Empty_Observation;
      Consumption : HRA.Envelope_Consumption.Envelope_Consumption :=
        HRA.Envelope_Consumption.Empty_Consumption;
      Fulfillment : constant HRA.Envelope_Fulfillment.Envelope_Fulfillment :=
        HRA.Envelope_Fulfillment.Empty_Fulfillment (D ("2026-08-15"));
      Commitment  : HRA.Envelope_Commitment.Commitment_Observation :=
        HRA.Envelope_Commitment.Empty_Observation
          (D ("2026-08-15"), D ("2026-08-31"));
      Obs          : Observation;
      Diag         : Observe_Diagnostic;
   begin
      Entitlement := HRA.Envelope_Entitlement.Fold_Movement
        (Entitlement,
         (Kind    => HRA.Envelope_Entitlement.Grant_From_Unallocated,
          Tx_Date => D ("2026-08-01"),
          Amt     => Make_Amount (JPY, 500.0),
          Target  => Food));
      Consumption.Managed.Insert
        ("food",
         HRA.Envelope_Consumption.Make_Amounts
           (Charges => Singleton_Balance (Make_Amount (JPY, 500.0)),
            Refunds => Empty_Balance));
      Commitment.Managed.Insert
        ("food", Singleton_Balance (Make_Amount (USD, 100.0)));

      Assert
        (Observe
           (Food_Policy, Registry, Entitlement, Consumption, Fulfillment,
            Commitment, Obs, Diag),
         "coordinate-union observation succeeds");
      Assert
        (Lookup_Balance (Position_For (Obs, Food).Remaining, JPY) = Zero_Quantity
         and then Lookup_Balance (Position_For (Obs, Food).Headroom, JPY) = Zero_Quantity,
         "exact JPY cancellation remains canonical zero");
      Assert
        (Lookup_Balance (Position_For (Obs, Food).Remaining, USD) = Zero_Quantity
         and then Lookup_Balance (Position_For (Obs, Food).Headroom, USD) = -100.0,
         "commitment-only USD coordinate is evaluated without cross-currency cancellation");
   end;

   -- Negative Plan commitment is invalid evidence, not a negative position.
   declare
      Registry    : constant Envelope_Registry := Registry_For;
      Food        : constant Envelope_Id := E (Registry, "food");
      Entitlement : constant HRA.Envelope_Entitlement.Entitlement_Observation :=
        HRA.Envelope_Entitlement.Empty_Observation;
      Consumption : constant HRA.Envelope_Consumption.Envelope_Consumption :=
        HRA.Envelope_Consumption.Empty_Consumption;
      Fulfillment : constant HRA.Envelope_Fulfillment.Envelope_Fulfillment :=
        HRA.Envelope_Fulfillment.Empty_Fulfillment (D ("2026-08-15"));
      Commitment  : HRA.Envelope_Commitment.Commitment_Observation :=
        HRA.Envelope_Commitment.Empty_Observation
          (D ("2026-08-15"), D ("2026-08-31"));
      Obs          : Observation;
      Diag         : Observe_Diagnostic;
   begin
      Commitment.Managed.Insert
        ("food", Singleton_Balance (Make_Amount (JPY, -100.0)));
      Assert
        (not Observe
           (Food_Policy, Registry, Entitlement, Consumption, Fulfillment,
            Commitment, Obs, Diag)
         and then Diag.Status = Negative_Plan_Commitment
         and then To_String (Diag.Envelope_Id_Text) = "food"
         and then To_String (Diag.Commodity_Code) = "JPY",
         "negative Plan commitment fails closed with coordinate diagnostic");
   end;

   -- Current policy selects the projection. Stable historical identity may
   -- remain in the registry and Entitlement history without leaking into the
   -- current position set.
   declare
      Registry    : constant Envelope_Registry :=
        Registry_For (Include_Retired => True);
      Food        : constant Envelope_Id := E (Registry, "food");
      Retired     : constant Envelope_Id := E (Registry, "vacation_2025");
      Entitlement : HRA.Envelope_Entitlement.Entitlement_Observation :=
        HRA.Envelope_Entitlement.Empty_Observation;
      Consumption : constant HRA.Envelope_Consumption.Envelope_Consumption :=
        HRA.Envelope_Consumption.Empty_Consumption;
      Fulfillment : constant HRA.Envelope_Fulfillment.Envelope_Fulfillment :=
        HRA.Envelope_Fulfillment.Empty_Fulfillment (D ("2026-08-15"));
      Commitment  : constant HRA.Envelope_Commitment.Commitment_Observation :=
        HRA.Envelope_Commitment.Empty_Observation
          (D ("2026-08-15"), D ("2026-08-31"));
      Obs          : Observation;
      Diag         : Observe_Diagnostic;
   begin
      Entitlement := HRA.Envelope_Entitlement.Fold_Movement
        (Entitlement,
         (Kind    => HRA.Envelope_Entitlement.Grant_From_Unallocated,
          Tx_Date => D ("2026-08-01"),
          Amt     => Make_Amount (JPY, 1000.0),
          Target  => Food));
      Entitlement := HRA.Envelope_Entitlement.Fold_Movement
        (Entitlement,
         (Kind    => HRA.Envelope_Entitlement.Grant_From_Unallocated,
          Tx_Date => D ("2026-08-01"),
          Amt     => Make_Amount (JPY, 500.0),
          Target  => Retired));

      Assert
        (Observe
           (Food_Policy, Registry, Entitlement, Consumption, Fulfillment,
            Commitment, Obs, Diag),
         "current membership observation succeeds beside retired history");
      Assert
        (Has_Position (Obs, Food)
         and then not Has_Position (Obs, Retired)
         and then Natural (Obs.Positions.Length) = 1,
         "retired Envelope history does not leak into current positions");
   end;

   -- Current policy must not introduce an Envelope that is absent from the
   -- stable identity registry.
   declare
      Unknown_Policy : constant HRA.Budget_Config.Budget_Policy :=
        Policy_For
          ("[[envelopes]]" & ASCII.LF &
           "id = ""unknown""" & ASCII.LF &
           "label = ""Unknown""" & ASCII.LF &
           "pacing = ""daily""" & ASCII.LF &
           "backing-pool = ""liquid""" & ASCII.LF);
      Registry    : constant Envelope_Registry := Registry_For;
      Entitlement : constant HRA.Envelope_Entitlement.Entitlement_Observation :=
        HRA.Envelope_Entitlement.Empty_Observation;
      Consumption : constant HRA.Envelope_Consumption.Envelope_Consumption :=
        HRA.Envelope_Consumption.Empty_Consumption;
      Fulfillment : constant HRA.Envelope_Fulfillment.Envelope_Fulfillment :=
        HRA.Envelope_Fulfillment.Empty_Fulfillment (D ("2026-08-15"));
      Commitment  : constant HRA.Envelope_Commitment.Commitment_Observation :=
        HRA.Envelope_Commitment.Empty_Observation
          (D ("2026-08-15"), D ("2026-08-31"));
      Obs          : Observation;
      Diag         : Observe_Diagnostic;
   begin
      Assert
        (not Observe
           (Unknown_Policy, Registry, Entitlement, Consumption, Fulfillment,
            Commitment, Obs, Diag)
         and then Diag.Status = Unknown_Current_Envelope
         and then To_String (Diag.Envelope_Id_Text) = "unknown",
         "unknown current Envelope fails closed");
   end;

   -- Base view excludes fulfillment and commitment by construction.
   declare
      Registry    : constant Envelope_Registry := Registry_For;
      Food        : constant Envelope_Id := E (Registry, "food");
      Entitlement : HRA.Envelope_Entitlement.Entitlement_Observation :=
        HRA.Envelope_Entitlement.Empty_Observation;
      Consumption : HRA.Envelope_Consumption.Envelope_Consumption :=
        HRA.Envelope_Consumption.Empty_Consumption;
      Obs          : Observation;
      Diag         : Observe_Diagnostic;
   begin
      Entitlement := HRA.Envelope_Entitlement.Fold_Movement
        (Entitlement,
         (Kind    => HRA.Envelope_Entitlement.Grant_From_Unallocated,
          Tx_Date => D ("2026-08-01"),
          Amt     => Make_Amount (JPY, 1000.0),
          Target  => Food));
      Consumption.Managed.Insert
        ("food",
         HRA.Envelope_Consumption.Make_Amounts
           (Charges => Singleton_Balance (Make_Amount (JPY, 300.0)),
            Refunds => Empty_Balance));
      Assert
        (Observe_Base
           (Food_Policy, Registry, Entitlement, Consumption, Obs, Diag),
         "base Position observation succeeds");
      Assert
        (Lookup_Balance (Position_For (Obs, Food).Remaining, JPY) = 700.0
         and then Lookup_Balance (Position_For (Obs, Food).Headroom, JPY) = 700.0,
         "base view has Remaining = Headroom = 700 JPY");
   end;

   -- Backing must fail loudly if a policy-required current Envelope position is
   -- missing; silent under-accounting is forbidden.
   declare
      Registry     : constant Envelope_Registry := Registry_For (Include_Daily => True);
      Food         : constant Envelope_Id := E (Registry, "food");
      Backing_Spec : HRA.Backing_Policy.Backing_Policy;
      Backing_Stat : HRA.Backing_Policy.Policy_Status;
      Partial      : Observation := Empty_Observation;
      Result       : HRA.Backing_Policy.Backing_Observation;
      pragma Unreferenced (Result);
      Failed_Loud  : Boolean := False;
   begin
      Assert
        (HRA.Backing_Policy.Admit_Backing_Policy
           (Food_Daily_Policy, Registry, Backing_Spec, Backing_Stat)
         and then Backing_Stat = HRA.Backing_Policy.Success,
         "backing policy setup succeeds");
      Partial.Positions.Insert
        ("food",
         (Env_Id    => Food,
          Remaining => Singleton_Balance (Make_Amount (JPY, 500.0)),
          Headroom  => Singleton_Balance (Make_Amount (JPY, 500.0))));
      begin
         Result := HRA.Backing_Policy.Observe_Backing
           (Backing_Spec, HRA.Ledger.Empty_Ledger, Partial);
      exception
         when Program_Error =>
            Failed_Loud := True;
      end;
      Assert
        (Failed_Loud,
         "backing fails loud when a required current Envelope position is missing");
   end;

   Put_Line
     (Natural'Image (Passed_Count) & " passed, " &
      Natural'Image (Failed_Count) & " failed");

   if Failed_Count > 0 then
      raise Program_Error with "Envelope position tests failed";
   end if;
end Test_Envelope_Position;