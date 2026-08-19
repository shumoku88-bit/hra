with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO; use Ada.Text_IO;
with HRA.Account;
with HRA.Account_Reconciliation;
with HRA.Actual_Admission;
with HRA.Dates;
with HRA.Journal;
with HRA.Journal_Evidence;
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

   Bank : constant HRA.Account.Account := HRA.Account.Make_Account ("assets:bank");

   function Balance_2
     (JPY_Value : HRA.Money.Quantity;
      USD_Value : HRA.Money.Quantity) return HRA.Money.Balance
   is
   begin
      return HRA.Money.Add_Balance
        (HRA.Money.Singleton_Balance (HRA.Money.Make_Amount (JPY, JPY_Value)),
         HRA.Money.Singleton_Balance (HRA.Money.Make_Amount (USD, USD_Value)));
   end Balance_2;

   Actual_Source : constant String :=
     "2026-08-01 Opening JPY" & ASCII.LF &
     "    assets:bank          100 JPY" & ASCII.LF &
     "    equity:opening      -100 JPY" & ASCII.LF & ASCII.LF &
     "2026-08-05 Opening USD" & ASCII.LF &
     "    assets:bank           20 USD" & ASCII.LF &
     "    equity:opening       -20 USD" & ASCII.LF & ASCII.LF &
     "2026-08-20 Future JPY" & ASCII.LF &
     "    assets:bank           50 JPY" & ASCII.LF &
     "    equity:opening       -50 JPY" & ASCII.LF;

   Actual_Ledger   : HRA.Ledger.Ledger;
   Actual_Evidence : HRA.Journal_Evidence.Journal_Evidence;
   Evidence_Diag   : HRA.Journal_Evidence.Evidence_Diagnostic;
   Parse_Error     : Unbounded_String;
   Actual          : HRA.Actual_Admission.Actual_Observation :=
     HRA.Actual_Admission.Empty_Observation;
   Actual_Diag     : HRA.Actual_Admission.Admission_Diagnostic;

begin
   Put_Line ("--- Testing external Account balance reconciliation ---");

   if not HRA.Journal.Parse_Journal_Text
     (Actual_Source, Actual_Ledger, Parse_Error)
   then
      raise Program_Error with
        "reconciliation fixture failed Journal admission: " &
        To_String (Parse_Error);
   end if;

   if not HRA.Journal_Evidence.Extract
     (Actual_Source,
      Actual_Ledger,
      Actual_Evidence,
      Evidence_Diag)
   then
      raise Program_Error with
        "reconciliation fixture failed evidence extraction: " &
        To_String (Evidence_Diag.Message);
   end if;

   Assert
     (HRA.Actual_Admission.Admit
        (Actual_Ledger,
         Actual_Evidence,
         Actual,
         Actual_Diag),
      "Setup: reconciliation consumes an admitted Actual observation");

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
      Admitted_Ledger : constant HRA.Ledger.Ledger :=
        HRA.Actual_Admission.Ledger_Of (Actual);
      Full_After : constant HRA.Money.Balance :=
        HRA.Ledger.Compute_Account_Balance (Admitted_Ledger, Bank);
      Through_After : constant HRA.Money.Balance :=
        HRA.Ledger.Compute_Account_Balance_Through
          (Admitted_Ledger, Bank, D ("2026-08-10"));
   begin
      Assert
        (HRA.Money.Lookup_Balance (Full_After, JPY) = 150.0
           and then HRA.Money.Lookup_Balance (Full_After, USD) = 20.0
           and then HRA.Money.Lookup_Balance (Through_After, JPY) = 100.0,
         "External reconciliation does not mutate opaque canonical Actual");
   end;

   Put_Line
     (Natural'Image (Passed_Count) & " passed, " &
      Natural'Image (Failed_Count) & " failed");

   if Failed_Count > 0 then
      raise Program_Error with "Account reconciliation tests failed";
   end if;
end Test_Account_Reconciliation;
