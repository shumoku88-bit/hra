with Ada.Text_IO; use Ada.Text_IO;
with ALedger.Budget_Config;
with ALedger.Config_Support;
with ALedger.Dates;
with ALedger.Envelope; use ALedger.Envelope;
with ALedger.Envelope_Commitment;
with ALedger.Envelope_Consumption;
with ALedger.Envelope_Entitlement;
with ALedger.Envelope_Fulfillment;
with ALedger.Envelope_Position;
with ALedger.Household_Envelope_Change;
with ALedger.Money; use ALedger.Money;

procedure Test_Envelope_Change is
   use type ALedger.Dates.Date;
   use type ALedger.Envelope_Position.Observe_Status;
   use type ALedger.Household_Envelope_Change.Snapshot_Status;
   use type ALedger.Household_Envelope_Change.Change_Status;

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
      Value  : ALedger.Dates.Date;
      Status : ALedger.Dates.Date_Status;
   begin
      if not ALedger.Dates.Parse (S, Value, Status) then
         raise Program_Error with "invalid test date: " & S;
      end if;
      return Value;
   end D;

   function Window
     (First_Day, Limit_Day : String) return ALedger.Dates.Half_Open_Period
   is
      Result : ALedger.Dates.Half_Open_Period;
   begin
      if not ALedger.Dates.Make_Half_Open_Period
        (D (First_Day), D (Limit_Day), Result)
      then
         raise Program_Error with
           "invalid test window: " & First_Day & ".." & Limit_Day;
      end if;
      return Result;
   end Window;

   JPY : constant Commodity := Make_Commodity ("JPY");

   Policy_Text : constant String :=
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

   Reordered_Policy_Text : constant String :=
     "[[backing-pools]]" & ASCII.LF &
     "id = ""liquid""" & ASCII.LF &
     "asset-accounts = [""assets:cash""]" & ASCII.LF &
     "[[envelopes]]" & ASCII.LF &
     "id = ""daily""" & ASCII.LF &
     "label = ""Daily""" & ASCII.LF &
     "pacing = ""daily""" & ASCII.LF &
     "backing-pool = ""liquid""" & ASCII.LF &
     "[[envelopes]]" & ASCII.LF &
     "id = ""food""" & ASCII.LF &
     "label = ""Food""" & ASCII.LF &
     "pacing = ""daily""" & ASCII.LF &
     "backing-pool = ""liquid""" & ASCII.LF;

   Policy           : ALedger.Budget_Config.Budget_Policy;
   Reordered_Policy : ALedger.Budget_Config.Budget_Policy;
   Config_Diag      : ALedger.Config_Support.Config_Diagnostic;
   Ids              : ALedger.Config_Support.String_Vectors.Vector;
   Registry         : Envelope_Registry;
   Reg_Diag         : ALedger.Config_Support.Config_Diagnostic;
   Food             : Envelope_Id;

   Earlier_Entitlement : ALedger.Envelope_Entitlement.Entitlement_Observation :=
     ALedger.Envelope_Entitlement.Empty_Observation;
   Later_Entitlement : ALedger.Envelope_Entitlement.Entitlement_Observation :=
     ALedger.Envelope_Entitlement.Empty_Observation;
   Earlier_Consumption : ALedger.Envelope_Consumption.Envelope_Consumption :=
     ALedger.Envelope_Consumption.Empty_Consumption;
   Later_Consumption : ALedger.Envelope_Consumption.Envelope_Consumption :=
     ALedger.Envelope_Consumption.Empty_Consumption;
   Earlier_Fulfillment : ALedger.Envelope_Fulfillment.Envelope_Fulfillment :=
     ALedger.Envelope_Fulfillment.Empty_Fulfillment (D ("2026-08-10"));
   Later_Fulfillment : ALedger.Envelope_Fulfillment.Envelope_Fulfillment :=
     ALedger.Envelope_Fulfillment.Empty_Fulfillment (D ("2026-08-15"));
   Earlier_Commitment : ALedger.Envelope_Commitment.Commitment_Observation :=
     ALedger.Envelope_Commitment.Empty_Observation
       (D ("2026-08-10"), D ("2026-09-01"));
   Later_Commitment : ALedger.Envelope_Commitment.Commitment_Observation :=
     ALedger.Envelope_Commitment.Empty_Observation
       (D ("2026-08-15"), D ("2026-09-01"));

   Earlier_Positions : ALedger.Envelope_Position.Observation;
   Later_Positions   : ALedger.Envelope_Position.Observation;
   Position_Diag     : ALedger.Envelope_Position.Observe_Diagnostic;

   August : constant ALedger.Dates.Half_Open_Period :=
     Window ("2026-08-01", "2026-09-01");
   September : constant ALedger.Dates.Half_Open_Period :=
     Window ("2026-09-01", "2026-10-01");

   Earlier_Snapshot : ALedger.Household_Envelope_Change.Explanation_Snapshot;
   Later_Snapshot   : ALedger.Household_Envelope_Change.Explanation_Snapshot;
   Reordered_Snapshot : ALedger.Household_Envelope_Change.Explanation_Snapshot;
   September_Snapshot : ALedger.Household_Envelope_Change.Explanation_Snapshot;
   Snapshot_Diag : ALedger.Household_Envelope_Change.Snapshot_Diagnostic;

begin
   Put_Line ("--- Testing typed Envelope Change ---");

   Assert
     (ALedger.Budget_Config.Parse_Budget_Policy
        (Policy_Text, Policy, Config_Diag),
      "Setup: parse food/daily policy");
   Assert
     (ALedger.Budget_Config.Parse_Budget_Policy
        (Reordered_Policy_Text, Reordered_Policy, Config_Diag),
      "Setup: parse reordered policy");

   Ids.Append ("food");
   Ids.Append ("daily");
   Assert
     (Admit_Registry (Ids, Registry, Reg_Diag),
      "Setup: admit stable Envelope registry");
   Assert (Lookup (Registry, "food", Food), "Setup: resolve food Envelope");

   Earlier_Entitlement := ALedger.Envelope_Entitlement.Fold_Movement
     (Earlier_Entitlement,
      (Kind    => ALedger.Envelope_Entitlement.Grant_From_Unallocated,
       Tx_Date => D ("2026-08-01"),
       Amt     => Make_Amount (JPY, 1000.0),
       Target  => Food));
   Later_Entitlement := ALedger.Envelope_Entitlement.Fold_Movement
     (Later_Entitlement,
      (Kind    => ALedger.Envelope_Entitlement.Grant_From_Unallocated,
       Tx_Date => D ("2026-08-01"),
       Amt     => Make_Amount (JPY, 1050.0),
       Target  => Food));

   Earlier_Consumption.Managed.Insert
     ("food",
      ALedger.Envelope_Consumption.Make_Amounts
        (Charges => Singleton_Balance (Make_Amount (JPY, 100.0)),
         Refunds => Empty_Balance));
   Later_Consumption.Managed.Insert
     ("food",
      ALedger.Envelope_Consumption.Make_Amounts
        (Charges => Singleton_Balance (Make_Amount (JPY, 150.0)),
         Refunds => Singleton_Balance (Make_Amount (JPY, 20.0))));

   Later_Fulfillment.Managed.Insert
     ("food",
      (Applied  => Singleton_Balance (Make_Amount (JPY, 30.0)),
       Reversed => Singleton_Balance (Make_Amount (JPY, 10.0))));

   Earlier_Commitment.Managed.Insert
     ("food", Singleton_Balance (Make_Amount (JPY, 200.0)));
   Later_Commitment.Managed.Insert
     ("food", Singleton_Balance (Make_Amount (JPY, 150.0)));

   Assert
     (ALedger.Envelope_Position.Observe
        (Policy,
         Registry,
         Earlier_Entitlement,
         Earlier_Consumption,
         Earlier_Fulfillment,
         Earlier_Commitment,
         Earlier_Positions,
         Position_Diag)
        and then Position_Diag.Status = ALedger.Envelope_Position.Success,
      "Setup: observe earlier proof-backed positions");
   Assert
     (ALedger.Envelope_Position.Observe
        (Policy,
         Registry,
         Later_Entitlement,
         Later_Consumption,
         Later_Fulfillment,
         Later_Commitment,
         Later_Positions,
         Position_Diag)
        and then Position_Diag.Status = ALedger.Envelope_Position.Success,
      "Setup: observe later proof-backed positions");

   Assert
     (ALedger.Household_Envelope_Change.Capture
        (Policy,
         Registry,
         August,
         D ("2026-08-10"),
         Earlier_Positions,
         Earlier_Snapshot,
         Snapshot_Diag)
        and then Snapshot_Diag.Status =
          ALedger.Household_Envelope_Change.Success,
      "Capture earlier typed explanation snapshot");
   Assert
     (ALedger.Household_Envelope_Change.Capture
        (Policy,
         Registry,
         August,
         D ("2026-08-15"),
         Later_Positions,
         Later_Snapshot,
         Snapshot_Diag)
        and then Snapshot_Diag.Status =
          ALedger.Household_Envelope_Change.Success,
      "Capture later typed explanation snapshot");

   declare
      Change : ALedger.Household_Envelope_Change.Change_Observation;
      Diag   : ALedger.Household_Envelope_Change.Change_Diagnostic;
   begin
      Assert
        (ALedger.Household_Envelope_Change.Observe_Change
           (Earlier_Snapshot, Later_Snapshot, Change, Diag)
           and then Diag.Status = ALedger.Household_Envelope_Change.Success,
         "Same-cycle typed Change succeeds");
      Assert
        (Change.From_Date = D ("2026-08-10")
           and then Change.Through_Date = D ("2026-08-15"),
         "Change retains explicit observation interval");
      Assert
        (Natural (Change.Lines.Length) = 2,
         "Change retains current Envelope coordinate count and order");

      declare
         Food_Change : constant ALedger.Household_Envelope_Change.Change_Line :=
           Change.Lines.Element (1);
      begin
         Assert
           (Image (Food_Change.Env_Id) = "food",
            "First Change coordinate follows current policy order");
         Assert
           (Lookup_Balance (Food_Change.Entitlement, JPY) = 50.0,
            "Change Entitlement = later - earlier");
         Assert
           (Lookup_Balance (Food_Change.Consumption_Charges, JPY) = 50.0
              and then
            Lookup_Balance (Food_Change.Consumption_Refunds, JPY) = 20.0,
            "Change retains gross Consumption deltas");
         Assert
           (Lookup_Balance (Food_Change.Net_Consumption, JPY) = 30.0,
            "Change keeps Net Consumption delta beside gross activity");
         Assert
           (Lookup_Balance (Food_Change.Fulfillment_Applied, JPY) = 30.0
              and then
            Lookup_Balance (Food_Change.Fulfillment_Reversed, JPY) = 10.0,
            "Change retains gross Fulfillment deltas");
         Assert
           (Lookup_Balance (Food_Change.Net_Fulfillment, JPY) = 20.0,
            "Change keeps Net Fulfillment delta beside gross activity");
         Assert
           (Lookup_Balance (Food_Change.Remaining, JPY) = Zero_Quantity,
            "Change can expose unchanged Remaining across internal activity");
         Assert
           (Lookup_Balance (Food_Change.Plan_Commitment, JPY) = -50.0,
            "Change observes released Plan commitment");
         Assert
           (Lookup_Balance (Food_Change.Headroom, JPY) = 50.0,
            "Change observes resulting Headroom movement");
      end;

      Assert
        (not ALedger.Household_Envelope_Change.Observe_Change
           (Later_Snapshot, Earlier_Snapshot, Change, Diag)
           and then Diag.Status =
             ALedger.Household_Envelope_Change.Observation_Order_Invalid,
         "Change rejects reversed observation time");
   end;

   Assert
     (not ALedger.Household_Envelope_Change.Capture
        (Policy,
         Registry,
         August,
         D ("2026-09-01"),
         Later_Positions,
         Reordered_Snapshot,
         Snapshot_Diag)
        and then Snapshot_Diag.Status =
          ALedger.Household_Envelope_Change.Observation_Outside_Window,
      "Snapshot fails closed outside its cycle window");

   Assert
     (ALedger.Household_Envelope_Change.Capture
        (Reordered_Policy,
         Registry,
         August,
         D ("2026-08-15"),
         Later_Positions,
         Reordered_Snapshot,
         Snapshot_Diag),
      "Capture same Envelope set in a different current order");

   declare
      Change : ALedger.Household_Envelope_Change.Change_Observation;
      Diag   : ALedger.Household_Envelope_Change.Change_Diagnostic;
   begin
      Assert
        (not ALedger.Household_Envelope_Change.Observe_Change
           (Earlier_Snapshot, Reordered_Snapshot, Change, Diag)
           and then Diag.Status =
             ALedger.Household_Envelope_Change.Envelope_Order_Mismatch
           and then Diag.Mismatch_Index = 1,
         "Change rejects a different current Envelope order");
   end;

   Assert
     (ALedger.Household_Envelope_Change.Capture
        (Policy,
         Registry,
         September,
         D ("2026-09-15"),
         Later_Positions,
         September_Snapshot,
         Snapshot_Diag),
      "Capture a typed snapshot in another cycle window");

   declare
      Change : ALedger.Household_Envelope_Change.Change_Observation;
      Diag   : ALedger.Household_Envelope_Change.Change_Diagnostic;
   begin
      Assert
        (not ALedger.Household_Envelope_Change.Observe_Change
           (Earlier_Snapshot, September_Snapshot, Change, Diag)
           and then Diag.Status =
             ALedger.Household_Envelope_Change.Window_Mismatch,
         "Same-cycle Change rejects cross-window comparison");
   end;

   Put_Line
     (Natural'Image (Passed_Count) & " passed, " &
      Natural'Image (Failed_Count) & " failed");

   if Failed_Count > 0 then
      raise Program_Error with "Envelope Change tests failed";
   end if;
end Test_Envelope_Change;
