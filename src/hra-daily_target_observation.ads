with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA.Cycle_Accounts_Observation;
with HRA.Cycle_Observation;
with HRA.Daily_Target_Scope;
with HRA.Dates;
with HRA.Money;
with HRA.Plan_Temporal_Observation;

--  Temporal Daily Target capacity assembled only from already-typed evidence.
--
--  Daily_Target_Scope remains atemporal. Plan_Temporal_Observation owns Plan
--  openness. Cycle_Accounts_Observation owns exact Actual Account state and the
--  current typed cycle coordinate. This package only intersects those meanings
--  and publishes the exact capacity evidence. It does not read source text,
--  query the Actual Ledger, round a per-day rate, or own report availability.
package HRA.Daily_Target_Observation is

   type Observation is private;

   function Is_Configured (Value : Observation) return Boolean;
   function Observed_Through (Value : Observation) return HRA.Dates.Date;
   function Window
     (Value : Observation) return HRA.Cycle_Observation.Cycle_Window;

   function Eligible_Assets (Value : Observation) return HRA.Money.Balance;
   function Open_Obligations (Value : Observation) return HRA.Money.Balance;
   function Already_Excluded (Value : Observation) return HRA.Money.Balance;
   function Net_Obligations (Value : Observation) return HRA.Money.Balance;
   function Capacity (Value : Observation) return HRA.Money.Balance;

   type Observe_Status is
     (Success,
      Observation_Date_Mismatch,
      Account_Observation_Outside_Cycle,
      Eligible_Asset_Missing_From_Account_State,
      Duplicate_Eligible_Asset_Row);

   type Observe_Diagnostic is record
      Status       : Observe_Status := Success;
      Account_Name : Unbounded_String := Null_Unbounded_String;
      Message      : Unbounded_String := Null_Unbounded_String;
   end record;

   --  The two temporal observations must describe the same inclusive day.
   --  Only selected Plans that are both open on that day and dated inside the
   --  supplied current cycle contribute obligation/reservation evidence.
   --  Capacity is never clamped:
   --
   --    eligible assets - (open obligations - already excluded reservations)
   function Observe
     (Scope         : HRA.Daily_Target_Scope.Scope;
      Plans         : HRA.Plan_Temporal_Observation.Observation;
      Account_State : HRA.Cycle_Accounts_Observation.Observation;
      Result        : out Observation;
      Diag          : out Observe_Diagnostic) return Boolean;

private

   type Observation is record
      Configured_Value       : Boolean := False;
      Observed_Through_Value : HRA.Dates.Date;
      Window_Value           : HRA.Cycle_Observation.Cycle_Window;
      Eligible_Assets_Value  : HRA.Money.Balance := HRA.Money.Empty_Balance;
      Open_Obligations_Value : HRA.Money.Balance := HRA.Money.Empty_Balance;
      Already_Excluded_Value : HRA.Money.Balance := HRA.Money.Empty_Balance;
   end record;

   function Is_Configured (Value : Observation) return Boolean is
     (Value.Configured_Value);

   function Observed_Through (Value : Observation) return HRA.Dates.Date is
     (Value.Observed_Through_Value);

   function Window
     (Value : Observation) return HRA.Cycle_Observation.Cycle_Window is
     (Value.Window_Value);

   function Eligible_Assets (Value : Observation) return HRA.Money.Balance is
     (Value.Eligible_Assets_Value);

   function Open_Obligations (Value : Observation) return HRA.Money.Balance is
     (Value.Open_Obligations_Value);

   function Already_Excluded (Value : Observation) return HRA.Money.Balance is
     (Value.Already_Excluded_Value);

   function Net_Obligations (Value : Observation) return HRA.Money.Balance is
     (HRA.Money.Subtract_Balance
        (Value.Open_Obligations_Value, Value.Already_Excluded_Value));

   function Capacity (Value : Observation) return HRA.Money.Balance is
     (HRA.Money.Subtract_Balance
        (Value.Eligible_Assets_Value, Net_Obligations (Value)));

end HRA.Daily_Target_Observation;
