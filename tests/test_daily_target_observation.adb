with Ada.Command_Line;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO; use Ada.Text_IO;
with HRA.Account;
with HRA.Cycle_Accounts_Observation;
with HRA.Cycle_Observation;
with HRA.Daily_Target_Observation;
with HRA.Daily_Target_Scope;
with HRA.Dates;
with HRA.Household_Config;
with HRA.Journal;
with HRA.Journal_Evidence;
with HRA.Ledger;
with HRA.Money;
with HRA.Plan_Admission;
with HRA.Plan_Completion;
with HRA.Plan_Temporal_Observation;

procedure Test_Daily_Target_Observation is
   use type HRA.Daily_Target_Observation.Observe_Status;
   use type HRA.Dates.Date;
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

   function D (Text : String) return HRA.Dates.Date is
      Value  : HRA.Dates.Date;
      Status : HRA.Dates.Date_Status;
   begin
      if not HRA.Dates.Parse (Text, Value, Status) then
         raise Program_Error with "invalid synthetic date";
      end if;
      return Value;
   end D;

   function Cycle_Window
     (First, Limit : String) return HRA.Cycle_Observation.Cycle_Window
   is
      Result : HRA.Dates.Half_Open_Period;
   begin
      if not HRA.Dates.Make_Half_Open_Period
        (D (First), D (Limit), Result)
      then
         raise Program_Error with "invalid synthetic cycle";
      end if;
      return Result;
   end Cycle_Window;

   function Make_Registry return HRA.Account.Account_Registry is
      Result : HRA.Account.Account_Registry := HRA.Account.Empty_Registry;
      Status : HRA.Account.Registry_Status;

      procedure Register (Name : String; Kind : HRA.Account.Account_Type) is
      begin
         if not HRA.Account.Register_Account
           (Result,
            HRA.Account.Declare_Account
              (HRA.Account.Make_Account (Name), Kind),
            Status)
         then
            raise Program_Error with "registry setup failed";
         end if;
      end Register;
   begin
      Register ("assets:cash", HRA.Account.Asset);
      Register ("assets:usd", HRA.Account.Asset);
      Register ("expenses:rent", HRA.Account.Expense);
      Register ("expenses:food", HRA.Account.Expense);
      return Result;
   end Make_Registry;

   function Admit_Plans (Source : String) return HRA.Plan_Admission.Plan_Journal is
      L             : HRA.Ledger.Ledger;
      Parse_Error   : Unbounded_String;
      Evidence      : HRA.Journal_Evidence.Journal_Evidence;
      Evidence_Diag : HRA.Journal_Evidence.Evidence_Diagnostic;
      Result        : HRA.Plan_Admission.Plan_Journal;
      Diag          : HRA.Plan_Admission.Admission_Diagnostic;
   begin
      if not HRA.Journal.Parse_Journal_Text (Source, L, Parse_Error)
        or else not HRA.Journal_Evidence.Extract
          (Source, L, Evidence, Evidence_Diag)
        or else not HRA.Plan_Admission.Admit (L, Evidence, Result, Diag)
      then
         raise Program_Error with "Plan setup admission failed";
      end if;
      return Result;
   end Admit_Plans;

   function Policy return HRA.Household_Config.Household_Configuration is
      Result : HRA.Household_Config.Household_Configuration;
   begin
      Result.Daily_Target_Assets.Append
        (HRA.Household_Config.Daily_Target_Asset'
           (ID      => To_Unbounded_String ("cash-policy"),
            Account => To_Unbounded_String ("assets:cash")));
      Result.Daily_Target_Assets.Append
        (HRA.Household_Config.Daily_Target_Asset'
           (ID      => To_Unbounded_String ("usd-policy"),
            Account => To_Unbounded_String ("assets:usd")));
      return Result;
   end Policy;

   JPY : constant HRA.Money.Commodity := HRA.Money.Make_Commodity ("JPY");
   USD : constant HRA.Money.Commodity := HRA.Money.Make_Commodity ("USD");

   function Single
     (Comm : HRA.Money.Commodity;
      Q    : HRA.Money.Quantity) return HRA.Money.Balance is
     (HRA.Money.Singleton_Balance (HRA.Money.Make_Amount (Comm, Q)));

   function Account_State
     (Cash_Value     : HRA.Money.Quantity;
      Include_USD    : Boolean := True;
      Duplicate_Cash : Boolean := False;
      Through        : String := "2026-08-20")
      return HRA.Cycle_Accounts_Observation.Observation
   is
      Result : HRA.Cycle_Accounts_Observation.Observation :=
        (Window           => Cycle_Window ("2026-08-01", "2026-09-01"),
         Observed_Through => D (Through),
         Rows             =>
           HRA.Cycle_Accounts_Observation.Account_Row_Vectors.Empty_Vector);

      procedure Add_Cash is
      begin
         Result.Rows.Append
           (HRA.Cycle_Accounts_Observation.Account_Row'
              (Acc     => HRA.Account.Make_Account ("assets:cash"),
               Opening => Single (JPY, Cash_Value),
               Debit   => HRA.Money.Empty_Balance,
               Credit  => HRA.Money.Empty_Balance));
      end Add_Cash;
   begin
      Add_Cash;
      if Duplicate_Cash then
         Add_Cash;
      end if;

      if Include_USD then
         Result.Rows.Append
           (HRA.Cycle_Accounts_Observation.Account_Row'
              (Acc     => HRA.Account.Make_Account ("assets:usd"),
               Opening => Single (USD, 10.0),
               Debit   => HRA.Money.Empty_Balance,
               Credit  => HRA.Money.Empty_Balance));
      end if;
      return Result;
   end Account_State;

   Registry : constant HRA.Account.Account_Registry := Make_Registry;

   Plan_Source : constant String :=
     "2026-08-10 Retired selected food" & ASCII.LF &
     "    ; plan-id: old-food" & ASCII.LF &
     "    ; daily-target-id: old-food-target" & ASCII.LF &
     "    ; superseded-on: 2026-08-15" & ASCII.LF &
     "    ; superseded-by: replacement-food" & ASCII.LF &
     "    assets:cash       -20 JPY" & ASCII.LF &
     "    expenses:food      20 JPY" & ASCII.LF & ASCII.LF &
     "2026-09-05 Replacement food" & ASCII.LF &
     "    ; plan-id: replacement-food" & ASCII.LF &
     "    assets:cash       -25 JPY" & ASCII.LF &
     "    expenses:food      25 JPY" & ASCII.LF & ASCII.LF &
     "2026-08-25 Current-cycle rent" & ASCII.LF &
     "    ; plan-id: rent" & ASCII.LF &
     "    ; daily-target-id: rent-target" & ASCII.LF &
     "    ; reservation-id: rent-buffer" & ASCII.LF &
     "    ; reservation-amount: 40" & ASCII.LF &
     "    ; reservation-commodity: JPY" & ASCII.LF &
     "    assets:cash      -100 JPY" & ASCII.LF &
     "    expenses:rent     100 JPY" & ASCII.LF & ASCII.LF &
     "2026-09-03 Next-cycle selected food" & ASCII.LF &
     "    ; plan-id: next-food" & ASCII.LF &
     "    ; daily-target-id: next-food-target" & ASCII.LF &
     "    assets:cash       -50 JPY" & ASCII.LF &
     "    expenses:food      50 JPY" & ASCII.LF;

   Plans : constant HRA.Plan_Admission.Plan_Journal := Admit_Plans (Plan_Source);
   Scope : HRA.Daily_Target_Scope.Scope;
   Scope_Diag : HRA.Daily_Target_Scope.Admission_Diagnostic;

begin
   Put_Line ("--- Testing HRA.Daily_Target_Observation ---");

   if not HRA.Daily_Target_Scope.Admit
     (Policy, Registry, Plans, Scope, Scope_Diag)
   then
      raise Program_Error with "Daily Target scope setup failed";
   end if;

   declare
      Plan_State : constant HRA.Plan_Temporal_Observation.Observation :=
        HRA.Plan_Temporal_Observation.Observe
          (Plans,
           HRA.Plan_Completion.Empty_Relations,
           D ("2026-08-20"));
      Accounts : constant HRA.Cycle_Accounts_Observation.Observation :=
        Account_State (200.0);
      Value : HRA.Daily_Target_Observation.Observation;
      Diag  : HRA.Daily_Target_Observation.Observe_Diagnostic;
      OK    : constant Boolean := HRA.Daily_Target_Observation.Observe
        (Scope, Plan_State, Accounts, Value, Diag);
   begin
      Assert (OK, "typed scope and aligned temporal observations derive capacity");
      if OK then
         Assert
           (HRA.Daily_Target_Observation.Is_Configured (Value)
              and then HRA.Daily_Target_Observation.Observed_Through (Value) =
                D ("2026-08-20")
              and then HRA.Cycle_Observation.Start_Date
                (HRA.Daily_Target_Observation.Window (Value)) = D ("2026-08-01"),
            "capacity retains the Account observation temporal coordinate");

         Assert
           (HRA.Money.Lookup_Balance
              (HRA.Daily_Target_Observation.Eligible_Assets (Value), JPY) = 200.0
              and then HRA.Money.Lookup_Balance
                (HRA.Daily_Target_Observation.Eligible_Assets (Value), USD) = 10.0,
            "eligible Asset closing state preserves every Commodity exactly");

         Assert
           (HRA.Money.Lookup_Balance
              (HRA.Daily_Target_Observation.Open_Obligations (Value), JPY) = 100.0
              and then HRA.Money.Lookup_Balance
                (HRA.Daily_Target_Observation.Already_Excluded (Value), JPY) = 40.0
              and then HRA.Money.Lookup_Balance
                (HRA.Daily_Target_Observation.Net_Obligations (Value), JPY) = 60.0,
            "only current-cycle open selected obligations contribute reservations");

         Assert
           (HRA.Money.Lookup_Balance
              (HRA.Daily_Target_Observation.Capacity (Value), JPY) = 140.0
              and then HRA.Money.Lookup_Balance
                (HRA.Daily_Target_Observation.Capacity (Value), USD) = 10.0,
            "capacity is exact eligible Assets minus net obligations");
      end if;
   end;

   declare
      Plan_State : constant HRA.Plan_Temporal_Observation.Observation :=
        HRA.Plan_Temporal_Observation.Observe
          (Plans,
           HRA.Plan_Completion.Empty_Relations,
           D ("2026-08-20"));
      Accounts : constant HRA.Cycle_Accounts_Observation.Observation :=
        Account_State (50.0);
      Value : HRA.Daily_Target_Observation.Observation;
      Diag  : HRA.Daily_Target_Observation.Observe_Diagnostic;
      OK    : constant Boolean := HRA.Daily_Target_Observation.Observe
        (Scope, Plan_State, Accounts, Value, Diag);
   begin
      Assert
        (OK
           and then HRA.Money.Lookup_Balance
             (HRA.Daily_Target_Observation.Capacity (Value), JPY) = -10.0,
         "negative exact capacity is preserved instead of clamped");
   end;

   declare
      Plan_State : constant HRA.Plan_Temporal_Observation.Observation :=
        HRA.Plan_Temporal_Observation.Observe
          (Plans,
           HRA.Plan_Completion.Empty_Relations,
           D ("2026-08-19"));
      Accounts : constant HRA.Cycle_Accounts_Observation.Observation :=
        Account_State (200.0);
      Value : HRA.Daily_Target_Observation.Observation;
      Diag  : HRA.Daily_Target_Observation.Observe_Diagnostic;
      OK    : constant Boolean := HRA.Daily_Target_Observation.Observe
        (Scope, Plan_State, Accounts, Value, Diag);
   begin
      Assert
        (not OK
           and then Diag.Status =
             HRA.Daily_Target_Observation.Observation_Date_Mismatch,
         "different Plan and Account observation days fail closed");
   end;

   declare
      Plan_State : constant HRA.Plan_Temporal_Observation.Observation :=
        HRA.Plan_Temporal_Observation.Observe
          (Plans,
           HRA.Plan_Completion.Empty_Relations,
           D ("2026-08-20"));
      Accounts : constant HRA.Cycle_Accounts_Observation.Observation :=
        Account_State (200.0, Include_USD => False);
      Value : HRA.Daily_Target_Observation.Observation;
      Diag  : HRA.Daily_Target_Observation.Observe_Diagnostic;
      OK    : constant Boolean := HRA.Daily_Target_Observation.Observe
        (Scope, Plan_State, Accounts, Value, Diag);
   begin
      Assert
        (not OK
           and then Diag.Status =
             HRA.Daily_Target_Observation.Eligible_Asset_Missing_From_Account_State
           and then To_String (Diag.Account_Name) = "assets:usd",
         "missing eligible Asset state fails closed instead of becoming zero");
   end;

   declare
      Plan_State : constant HRA.Plan_Temporal_Observation.Observation :=
        HRA.Plan_Temporal_Observation.Observe
          (Plans,
           HRA.Plan_Completion.Empty_Relations,
           D ("2026-08-20"));
      Accounts : constant HRA.Cycle_Accounts_Observation.Observation :=
        Account_State (200.0, Duplicate_Cash => True);
      Value : HRA.Daily_Target_Observation.Observation;
      Diag  : HRA.Daily_Target_Observation.Observe_Diagnostic;
      OK    : constant Boolean := HRA.Daily_Target_Observation.Observe
        (Scope, Plan_State, Accounts, Value, Diag);
   begin
      Assert
        (not OK
           and then Diag.Status =
             HRA.Daily_Target_Observation.Duplicate_Eligible_Asset_Row,
         "duplicate eligible Asset state fails closed instead of double counting");
   end;

   New_Line;
   Put_Line
     ("Summary: Passed =" & Natural'Image (Passed_Count) &
      ", Failed =" & Natural'Image (Failed_Count));

   if Failed_Count > 0 then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   else
      Put_Line ("RESULT: SUCCESS");
   end if;
end Test_Daily_Target_Observation;
