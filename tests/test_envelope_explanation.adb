with Ada.Text_IO; use Ada.Text_IO;
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

procedure Test_Envelope_Explanation is
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

   JPY : constant Commodity := Make_Commodity ("JPY");

   Budget_TOML : constant String :=
     "[[backing-pools]]" & ASCII.LF &
     "id = ""liquid""" & ASCII.LF &
     "asset-accounts = [""assets:cash""]" & ASCII.LF &
     "[[envelopes]]" & ASCII.LF &
     "id = ""food""" & ASCII.LF &
     "label = ""Food""" & ASCII.LF &
     "pacing = ""daily""" & ASCII.LF &
     "backing-pool = ""liquid""" & ASCII.LF;

   Policy      : ALedger.Budget_Config.Budget_Policy;
   Config_Diag : ALedger.Config_Support.Config_Diagnostic;
   Ids         : ALedger.Config_Support.String_Vectors.Vector;
   Registry    : Envelope_Registry;
   Reg_Diag    : ALedger.Config_Support.Config_Diagnostic;
   Food        : Envelope_Id;

   Entitlement : ALedger.Envelope_Entitlement.Entitlement_Observation :=
     ALedger.Envelope_Entitlement.Empty_Observation;
   Consumption : ALedger.Envelope_Consumption.Envelope_Consumption :=
     ALedger.Envelope_Consumption.Empty_Consumption;
   Fulfillment : ALedger.Envelope_Fulfillment.Envelope_Fulfillment :=
     ALedger.Envelope_Fulfillment.Empty_Fulfillment (D ("2026-08-15"));
   Commitment  : ALedger.Envelope_Commitment.Commitment_Observation :=
     ALedger.Envelope_Commitment.Empty_Observation
       (D ("2026-08-15"), D ("2026-08-16"));

   Obs  : Observation;
   Diag : Observe_Diagnostic;

begin
   Put_Line ("--- Testing Envelope arithmetic explanation ---");

   Assert
     (ALedger.Budget_Config.Parse_Budget_Policy
        (Budget_TOML, Policy, Config_Diag),
      "Setup: parse current Envelope policy");

   Ids.Append ("food");
   Assert
     (Admit_Registry (Ids, Registry, Reg_Diag),
      "Setup: admit stable Envelope registry");
   Assert (Lookup (Registry, "food", Food), "Setup: resolve food Envelope");

   Entitlement := ALedger.Envelope_Entitlement.Fold_Movement
     (Entitlement,
      (Kind    => ALedger.Envelope_Entitlement.Grant_From_Unallocated,
       Tx_Date => D ("2026-08-01"),
       Amt     => Make_Amount (JPY, 1000.0),
       Target  => Food));

   --  Gross activity cancels to zero, but the explanation must retain both
   --  sides instead of presenting the Envelope as if nothing happened.
   Consumption.Managed.Insert
     ("food",
      ALedger.Envelope_Consumption.Make_Amounts
        (Charges => Singleton_Balance (Make_Amount (JPY, 300.0)),
         Refunds => Singleton_Balance (Make_Amount (JPY, 300.0))));

   Fulfillment.Managed.Insert
     ("food",
      (Applied  => Singleton_Balance (Make_Amount (JPY, 100.0)),
       Reversed => Singleton_Balance (Make_Amount (JPY, 100.0))));

   Commitment.Managed.Insert
     ("food", Singleton_Balance (Make_Amount (JPY, 150.0)));

   Assert
     (Observe
        (Policy,
         Registry,
         Entitlement,
         Consumption,
         Fulfillment,
         Commitment,
         Obs,
         Diag)
        and then Diag.Status = Success,
      "Observe proof-backed Position with canceling activity");

   Assert
     (Has_Explanation (Obs, Food),
      "Successful Position retains an arithmetic explanation");

   declare
      Why : constant Explanation := Explain (Obs, Food);
   begin
      Assert
        (Lookup_Balance (Why.Evidence.Entitlement, JPY) = 1000.0,
         "Explanation retains Entitlement proof input");
      Assert
        (Lookup_Balance (Why.Evidence.Consumption_Charges, JPY) = 300.0
           and then
         Lookup_Balance (Why.Evidence.Consumption_Refunds, JPY) = 300.0,
         "Explanation retains gross charges and refunds");
      Assert
        (Lookup_Balance (Why.Evidence.Net_Consumption, JPY) = Zero_Quantity,
         "Canceling consumption projects to exact zero net");
      Assert
        (Lookup_Balance (Why.Evidence.Fulfillment_Applied, JPY) = 100.0
           and then
         Lookup_Balance (Why.Evidence.Fulfillment_Reversed, JPY) = 100.0,
         "Explanation retains gross fulfillment and reversal");
      Assert
        (Lookup_Balance (Why.Evidence.Net_Fulfillment, JPY) = Zero_Quantity,
         "Canceling fulfillment projects to exact zero net");
      Assert
        (Lookup_Balance (Why.Evidence.Plan_Commitment, JPY) = 150.0,
         "Explanation retains Plan commitment proof input");
      Assert
        (Lookup_Balance (Why.Observed_Position.Remaining, JPY) = 1000.0,
         "Proof-backed Remaining closes over retained net evidence");
      Assert
        (Lookup_Balance (Why.Observed_Position.Headroom, JPY) = 850.0,
         "Proof-backed Headroom closes over retained commitment");
      Assert
        (Why.Observed_Position = Position_For (Obs, Food),
         "Explanation returns the same Position already owned by observation");
   end;

   Put_Line
     (Natural'Image (Passed_Count) & " passed, " &
      Natural'Image (Failed_Count) & " failed");

   if Failed_Count > 0 then
      raise Program_Error with "Envelope explanation tests failed";
   end if;
end Test_Envelope_Explanation;
