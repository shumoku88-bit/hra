with HRA.Cycle_Observation;
with HRA.Daily_Target_Observation;
with HRA.Dates;
with HRA.Money;

--  Exact Daily Target rate evidence.
--
--  The authoritative value is intentionally not decimalized. Capacity remains
--  an exact multi-commodity Balance and the common denominator remains the
--  positive number of calendar days in [Observed_Through, End_Exclusive).
--  Keeping those coordinates separate preserves temporal provenance such as
--  "100 JPY over 3 remaining days" without inventing rounding policy.
package HRA.Daily_Target_Rate is

   type Rate is private;

   function Derive
     (Value : HRA.Daily_Target_Observation.Observation) return Rate
     with Pre =>
       HRA.Cycle_Observation.Contains
         (HRA.Daily_Target_Observation.Window (Value),
          HRA.Daily_Target_Observation.Observed_Through (Value));

   function Is_Configured (Value : Rate) return Boolean;

   function Capacity_Numerator (Value : Rate) return HRA.Money.Balance
     with Pre => Is_Configured (Value);

   function Remaining_Days
     (Value : Rate) return HRA.Dates.Positive_Day_Count
     with Pre => Is_Configured (Value);

private

   type Rate is record
      Configured_Value     : Boolean := False;
      Numerator_Value      : HRA.Money.Balance := HRA.Money.Empty_Balance;
      Remaining_Days_Value : HRA.Dates.Positive_Day_Count := 1;
   end record;

   function Is_Configured (Value : Rate) return Boolean is
     (Value.Configured_Value);

   function Capacity_Numerator (Value : Rate) return HRA.Money.Balance is
     (Value.Numerator_Value);

   function Remaining_Days
     (Value : Rate) return HRA.Dates.Positive_Day_Count is
     (Value.Remaining_Days_Value);

end HRA.Daily_Target_Rate;
