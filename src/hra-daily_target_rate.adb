package body HRA.Daily_Target_Rate is

   function Derive
     (Value : HRA.Daily_Target_Observation.Observation) return Rate
   is
      Result : Rate;
   begin
      if not HRA.Daily_Target_Observation.Is_Configured (Value) then
         return Result;
      end if;

      declare
         Remaining_Window : HRA.Dates.Half_Open_Period;
      begin
         if not HRA.Dates.Make_Half_Open_Period
           (HRA.Daily_Target_Observation.Observed_Through (Value),
            HRA.Cycle_Observation.End_Exclusive
              (HRA.Daily_Target_Observation.Window (Value)),
            Remaining_Window)
         then
            raise Program_Error with
              "Daily Target observation day must lie inside its current cycle";
         end if;

         return
           (Configured_Value     => True,
            Numerator_Value      => HRA.Daily_Target_Observation.Capacity (Value),
            Remaining_Days_Value => HRA.Dates.Length_In_Days (Remaining_Window));
      end;
   end Derive;

end HRA.Daily_Target_Rate;
