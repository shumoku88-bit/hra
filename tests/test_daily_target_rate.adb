with Ada.Command_Line;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO; use Ada.Text_IO;
with HRA.Account;
with HRA.Cycle_Accounts_Observation;
with HRA.Cycle_Observation;
with HRA.Daily_Target_Observation;
with HRA.Daily_Target_Rate;
with HRA.Daily_Target_Scope;
with HRA.Dates;
with HRA.Household_Config;
with HRA.Money;
with HRA.Plan_Admission;
with HRA.Plan_Completion;
with HRA.Plan_Temporal_Observation;

procedure Test_Daily_Target_Rate is
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

   function Cycle_Window return HRA.Cycle_Observation.Cycle_Window is
      Result : HRA.Dates.Half_Open_Period;
   begin
      if not HRA.Dates.Make_Half_Open_Period
        (D ("2026-08-01"), D ("2026-09-01"), Result)
      then
         raise Program_Error with "invalid synthetic cycle";
      end if;
      return Result;
   end Cycle_Window;

   JPY : constant HRA.Money.Commodity := HRA.Money.Make_Commodity ("JPY");
   USD : constant HRA.Money.Commodity := HRA.Money.Make_Commodity ("USD");

   function Single
     (Comm : HRA.Money.Commodity;
      Q    : HRA.Money.Quantity) return HRA.Money.Balance is
     (HRA.Money.Singleton_Balance (HRA.Money.Make_Amount (Comm, Q)));

   function Make_Registry return HRA.Account.Account_Registry is
      Result : HRA.Account.Account_Registry := HRA.Account.Empty_Registry;
      Status : HRA.Account.Registry_Status;

      procedure Register (Name : String) is
      begin
         if not HRA.Account.Register_Account
           (Result,
            HRA.Account.Declare_Account
              (HRA.Account.Make_Account (Name), HRA.Account.Asset),
            Status)
         then
            raise Program_Error with "registry setup failed";
         end if;
      end Register;
   begin
      Register ("assets:cash");
      Register ("assets:usd");
      return Result;
   end Make_Registry;

   Registry : constant HRA.Account.Account_Registry := Make_Registry;

   function Account_State
     (Cash_Value : HRA.Money.Quantity;
      USD_Value  : HRA.Money.Quantity;
      Through    : String)
      return HRA.Cycle_Accounts_Observation.Observation
   is
      Result : HRA.Cycle_Accounts_Observation.Observation :=
        (Window           => Cycle_Window,
         Observed_Through => D (Through),
         Rows             =>
           HRA.Cycle_Accounts_Observation.Account_Row_Vectors.Empty_Vector);
   begin
      Result.Rows.Append
        (HRA.Cycle_Accounts_Observation.Account_Row'
           (Acc     => HRA.Account.Make_Account ("assets:cash"),
            Opening => Single (JPY, Cash_Value),
            Debit   => HRA.Money.Empty_Balance,
            Credit  => HRA.Money.Empty_Balance));
      Result.Rows.Append
        (HRA.Cycle_Accounts_Observation.Account_Row'
           (Acc     => HRA.Account.Make_Account ("assets:usd"),
            Opening => Single (USD, USD_Value),
            Debit   => HRA.Money.Empty_Balance,
            Credit  => HRA.Money.Empty_Balance));
      return Result;
   end Account_State;

   function Capacity_Observation
     (Configured : Boolean;
      Cash_Value : HRA.Money.Quantity;
      USD_Value  : HRA.Money.Quantity;
      Through    : String) return HRA.Daily_Target_Observation.Observation
   is
      Policy : HRA.Household_Config.Household_Configuration;
      Plans  : constant HRA.Plan_Admission.Plan_Journal :=
        HRA.Plan_Admission.Empty_Journal;
      Scope      : HRA.Daily_Target_Scope.Scope;
      Scope_Diag : HRA.Daily_Target_Scope.Admission_Diagnostic;
      Plan_State : constant HRA.Plan_Temporal_Observation.Observation :=
        HRA.Plan_Temporal_Observation.Observe
          (Plans, HRA.Plan_Completion.Empty_Relations, D (Through));
      Accounts : constant HRA.Cycle_Accounts_Observation.Observation :=
        Account_State (Cash_Value, USD_Value, Through);
      Result : HRA.Daily_Target_Observation.Observation;
      Diag   : HRA.Daily_Target_Observation.Observe_Diagnostic;
   begin
      if Configured then
         Policy.Daily_Target_Assets.Append
           (HRA.Household_Config.Daily_Target_Asset'
              (ID      => To_Unbounded_String ("cash-policy"),
               Account => To_Unbounded_String ("assets:cash")));
         Policy.Daily_Target_Assets.Append
           (HRA.Household_Config.Daily_Target_Asset'
              (ID      => To_Unbounded_String ("usd-policy"),
               Account => To_Unbounded_String ("assets:usd")));
      end if;

      if not HRA.Daily_Target_Scope.Admit
        (Policy, Registry, Plans, Scope, Scope_Diag)
        or else not HRA.Daily_Target_Observation.Observe
          (Scope, Plan_State, Accounts, Result, Diag)
      then
         raise Program_Error with "Daily Target rate setup failed";
      end if;

      return Result;
   end Capacity_Observation;

begin
   Put_Line ("--- Testing HRA.Daily_Target_Rate ---");

   declare
      Value : constant HRA.Daily_Target_Rate.Rate :=
        HRA.Daily_Target_Rate.Derive
          (Capacity_Observation (True, 100.0, 10.0, "2026-08-01"));
   begin
      Assert
        (HRA.Daily_Target_Rate.Is_Configured (Value)
           and then HRA.Daily_Target_Rate.Remaining_Days (Value) = 31,
         "cycle-start observation retains the full 31-day denominator");
   end;

   declare
      Value : constant HRA.Daily_Target_Rate.Rate :=
        HRA.Daily_Target_Rate.Derive
          (Capacity_Observation (True, 100.0, 10.0, "2026-08-31"));
   begin
      Assert
        (HRA.Daily_Target_Rate.Remaining_Days (Value) = 1,
         "last in-cycle day has denominator one without clamping");
   end;

   declare
      Value : constant HRA.Daily_Target_Rate.Rate :=
        HRA.Daily_Target_Rate.Derive
          (Capacity_Observation (True, 100.0, 10.0, "2026-08-29"));
      Numerator : constant HRA.Money.Balance :=
        HRA.Daily_Target_Rate.Capacity_Numerator (Value);
   begin
      Assert
        (HRA.Daily_Target_Rate.Remaining_Days (Value) = 3
           and then HRA.Money.Lookup_Balance (Numerator, JPY) = 100.0,
         "100 over three days remains exact numerator and temporal denominator");
      Assert
        (HRA.Money.Lookup_Balance (Numerator, JPY) = 100.0
           and then HRA.Money.Lookup_Balance (Numerator, USD) = 10.0
           and then HRA.Daily_Target_Rate.Remaining_Days (Value) = 3,
         "all commodities share one retained temporal denominator");
   end;

   declare
      Value : constant HRA.Daily_Target_Rate.Rate :=
        HRA.Daily_Target_Rate.Derive
          (Capacity_Observation (True, -10.0, 0.0, "2026-08-29"));
   begin
      Assert
        (HRA.Money.Lookup_Balance
           (HRA.Daily_Target_Rate.Capacity_Numerator (Value), JPY) = -10.0
           and then HRA.Daily_Target_Rate.Remaining_Days (Value) = 3,
         "negative capacity remains negative exact rate evidence");
   end;

   declare
      Value : constant HRA.Daily_Target_Rate.Rate :=
        HRA.Daily_Target_Rate.Derive
          (Capacity_Observation (True, 0.0, 0.0, "2026-08-29"));
   begin
      Assert
        (HRA.Daily_Target_Rate.Is_Configured (Value)
           and then HRA.Money.Is_Zero_Balance
             (HRA.Daily_Target_Rate.Capacity_Numerator (Value))
           and then HRA.Daily_Target_Rate.Remaining_Days (Value) = 3,
         "configured zero remains a configured exact rate");
   end;

   declare
      Value : constant HRA.Daily_Target_Rate.Rate :=
        HRA.Daily_Target_Rate.Derive
          (Capacity_Observation (False, 100.0, 10.0, "2026-08-29"));
   begin
      Assert
        (not HRA.Daily_Target_Rate.Is_Configured (Value),
         "unconfigured Daily Target does not become numeric zero per day");
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
end Test_Daily_Target_Rate;
