package body HRA.Plan_Temporal_Observation is

   use type HRA.Dates.Date;
   use type HRA.Plan.Plan_Id;
   use type HRA.Plan_Admission.Retirement_Kind;

   function Observe
     (Plans            : HRA.Plan_Admission.Plan_Journal;
      Completions      : HRA.Plan_Completion.Completion_Relations;
      Observed_Through : HRA.Dates.Date) return Observation
   is
      Result : Observation;

      function Retired_As_Of
        (Plan_Item : HRA.Plan_Admission.Plan_Transaction_Entry) return Boolean
      is
      begin
         case Plan_Item.Retirement.Kind is
            when HRA.Plan_Admission.No_Retirement =>
               return False;
            when HRA.Plan_Admission.Cancellation =>
               return Plan_Item.Retirement.Canceled_On <= Observed_Through;
            when HRA.Plan_Admission.Supersession =>
               return Plan_Item.Retirement.Superseded_On <= Observed_Through;
         end case;
      end Retired_As_Of;

   begin
      Result.Observed_Through := Observed_Through;
      Result.Open_Plans.Clear;
      Result.Completed_Plans.Clear;

      --  Planned transaction date is intentionally not a selection coordinate.
      --  A Plan remains an admitted commitment until retirement evidence becomes
      --  visible or a completing Actual becomes visible through the observation
      --  horizon.
      for I in 1 .. HRA.Plan_Admission.Transaction_Count (Plans) loop
         declare
            Plan_Entry : constant HRA.Plan_Admission.Plan_Transaction_Entry :=
              HRA.Plan_Admission.Transaction_At (Plans, I);
            Relation   : HRA.Plan_Completion.Completion_Relation;
         begin
            if HRA.Plan_Completion.Has_Visible_Completion
                 (Completions, Plan_Entry.ID, Observed_Through, Relation)
            then
               Result.Completed_Plans.Append
                 (Completed_Plan'
                    (ID            => Plan_Entry.ID,
                     Plan_Tx       => Plan_Entry.Tx,
                     Actual_Tx     => Relation.Actual.Tx,
                     Plan_Source   => Plan_Entry.Source,
                     Actual_Source => Relation.Actual.Source));
            elsif not Retired_As_Of (Plan_Entry) then
               Result.Open_Plans.Append
                 (Open_Plan'(ID => Plan_Entry.ID, Tx => Plan_Entry.Tx));
            end if;
         end;
      end loop;

      return Result;
   end Observe;

end HRA.Plan_Temporal_Observation;
