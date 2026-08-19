with Ada.Text_IO; use Ada.Text_IO;
with HRA.Account;
with HRA.Account_Reconciliation;
with HRA.Actual_Admission;
with HRA.Dates;
with HRA.Ledger;
with HRA.Money;

procedure Test_Account_Reconciliation is
   use type HRA.Account.Account;
   use type HRA.Dates.Date;
   use type HRA.Money.Quantity;

   package Reconciliation renames HRA.Account_Reconciliation;

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
      Value  : HRA.Dates.Date;
      Status : HRA.Dates.Date_Status;
   begin
      if not HRA.Dates.Parse (S, Value, Status) then
         raise Program_Error with "invalid test date: " & S;
      end if;
      return Value;
   end D;

   JPY : constant HRA.Money.Commodity := HRA.Money.Make_Commodity ("JPY");
   USD : constant HRA.Money.Commodity := HRA.Money.Make_Commodity ("USD");

   Bank   : constant HRA.Account.Account := HRA.Account.Make_Account ("assets:bank");
   Equity : constant HRA.Account.Account := HRA.Account.Make_Account ("equity:opening");

   function Balance_2
     (JPY_Value : HRA.Money.Quantity;
      USD_Value : HRA.Money.Quantity) return HRA.Money.Balance
   is
   begin
      return HRA.Money.Add_Balance
        (HRA.Money.Singleton_Balance (HRA.Money.Make_Amount (JPY, JPY_Value)),
         HRA.Money.Singleton_Balance (HRA.Money.Make_Amount (USD, USD_Value)));
   end Balance_2;

   procedure Add_Balanced_Account_Movement
     (L         : in out HRA.Ledger.Ledger;
      On_Date   : HRA.Dates.Date;
      Commodity : HRA.Money.Commodity;
      Value     : HRA.Money.Quantity;
      Label     : String)
   is
      Postings : HRA.Ledger.Posting_Vectors.Vector;
      Tx       : HRA.Ledger.Transaction;
      Status   : HRA.Ledger.Transaction_Error;
   begin
      Postings.Append
        (HRA.Ledger.Make_Posting
           (Bank, HRA.Money.Make_Amount (Commodity, Value)));
      Postings.Append
        (HRA.Ledger.Make_Posting
           (Equity, HRA.Money.Make_Amount (Commodity, -Value)));

      if not HRA.Ledger.Create_Transaction
        (On_Date, Label, Postings, Tx, Status)
      then
         raise Program_Error with
           "failed to create reconciliation fixture transaction: " &
           HRA.Ledger.Transaction_Error'Image (Status);
      end if;

      if not HRA.Ledger.Add_Transaction (L, Tx, Status) then
         raise Program_Error with
           "failed to add reconciliation fixture transaction: " &
           HRA.Ledger.Transaction_Error'Image (Status);
      end if;
   end Add_Balanced_Account_Movement;

   Actual_Ledger : HRA.Ledger.Ledger := HRA.Ledger.Empty_Ledger;
   Actual : HRA.Actual_Admission.Actual_Observation :=
     HRA.Actual_Admission.Empty_Observation;

begin
   Put_Line ("--- Testing external Account balance reconciliation ---");

   Add_Balanced_Account_Movement
     (Actual_Ledger, D ("2026-08-01"), JPY, 100.0, "Opening JPY");
   Add_Balanced_Account_Movement
     (Actual_Ledger, D ("2026-08-05"), USD, 20.0, "Opening USD");
   Add_Balanced_Account_Movement
     (Actual_Ledger, D ("2026-08-20"), JPY, 50.0, "Future JPY");

   Actual.Value := Actual_Ledger;

   declare
      External : constant Reconciliation.External_Balance_Observation :=
        Reconciliation.Observe_External_Balance
          (Bank, D ("2026-08-10"), Balance_2 (100.0, 20.0));
      Result : constant Reconciliation.Reconciliation :=
        Reconciliation.Reconcile (Actual, External);
   begin
      Assert
        (Reconciliation.Account_Of
           (Reconciliation.External_Observation (Result)) = Bank
           and then Reconciliation.Observed_On
             (Reconciliation.External_Observation (Result)) = D ("2026-08-10"),
         "Reconciliation retains external Account and observation day");
      Assert
        (HRA.Money.Lookup_Balance
           (Reconciliation.Ledger_Balance (Result), JPY) = 100.0
           and then HRA.Money.Lookup_Balance
             (Reconciliation.Ledger_Balance (Result), USD) = 20.0,
         "Canonical Actual side is observed through the same inclusive day");
      Assert
        (Reconciliation.Matches (Result)
           and then HRA.Money.Is_Zero_Balance
             (Reconciliation.Difference (Result)),
         "Exact multi-Commodity equality reconciles as matched");
   end;

   declare
      External : constant Reconciliation.External_Balance_Observation :=
        Reconciliation.Observe_External_Balance
          (Bank, D ("2026-08-10"), Balance_2 (105.0, 20.0));
      Result : constant Reconciliation.Reconciliation :=
        Reconciliation.Reconcile (Actual, External);
   begin
      Assert
        (HRA.Money.Lookup_Balance
           (Reconciliation.Difference (Result), JPY) = 5.0
           and then HRA.Money.Lookup_Balance
             (Reconciliation.Difference (Result), USD) = 0.0,
         "Positive difference means external balance exceeds canonical Actual");
      Assert
        (not Reconciliation.Matches (Result),
         "Any non-zero Commodity coordinate is a reconciliation difference");
   end;

   declare
      External : constant Reconciliation.External_Balance_Observation :=
        Reconciliation.Observe_External_Balance
          (Bank, D ("2026-08-10"), Balance_2 (95.0, 25.0));
      Result : constant Reconciliation.Reconciliation :=
        Reconciliation.Reconcile (Actual, External);
   begin
      Assert
        (HRA.Money.Lookup_Balance
           (Reconciliation.Difference (Result), JPY) = -5.0
           and then HRA.Money.Lookup_Balance
             (Reconciliation.Difference (Result), USD) = 5.0,
         "Difference preserves independent Commodity coordinates and signs");
      Assert
        (HRA.Money.Lookup_Balance
           (Reconciliation.Value_Of
              (Reconciliation.External_Observation (Result)), JPY) = 95.0
           and then HRA.Money.Lookup_Balance
             (Reconciliation.Value_Of
                (Reconciliation.External_Observation (Result)), USD) = 25.0,
         "Reconciliation retains the exact supplied external evidence");
   end;

   declare
      Full_After : constant HRA.Money.Balance :=
        HRA.Ledger.Compute_Account_Balance (Actual.Value, Bank);
      Through_After : constant HRA.Money.Balance :=
        HRA.Ledger.Compute_Account_Balance_Through
          (Actual.Value, Bank, D ("2026-08-10"));
   begin
      Assert
        (HRA.Money.Lookup_Balance (Full_After, JPY) = 150.0
           and then HRA.Money.Lookup_Balance (Full_After, USD) = 20.0
           and then HRA.Money.Lookup_Balance (Through_After, JPY) = 100.0,
         "External reconciliation does not mutate typed canonical Actual");
   end;

   Put_Line
     (Natural'Image (Passed_Count) & " passed, " &
      Natural'Image (Failed_Count) & " failed");

   if Failed_Count > 0 then
      raise Program_Error with "Account reconciliation tests failed";
   end if;
end Test_Account_Reconciliation;
