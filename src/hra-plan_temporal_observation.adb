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

      function Visible_Completion_Index
        (Plan_ID : HRA.Plan.Plan_Id) return Natural
      is
      begin
         for I in 1 .. HRA.Plan_Completion.Count (Completions) loop
            declare
               Relation : constant HRA.Plan_Completion.Completion_Relation :=
                 HRA.Plan_Completion.Relation_At (Completions, I);
            begin
               if Relation.Plan_ID = Plan_ID
                 and then Relation.Actual.Tx.Date <= Observed_Through
               then
                  return I;
               end if;
            end;
         end loop;
         return 0;
      end Visible_Completion_Index;

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
            Completion_Index : constant Natural :=
              Visible_Completion_Index (Plan_Entry.ID);
         begin
            if Completion_Index > 0 then
               declare
                  Relation : constant HRA.Plan_Completion.Completion_Relation :=
                    HRA.Plan_Completion.Relation_At
                      (Completions, Positive (Completion_Index));
               begin
                  Result.Completed_Plans.Append
                    (Completed_Plan'
                       (ID            => Plan_Entry.ID,
                        Plan_Tx       => Plan_Entry.Tx,
                        Actual_Tx     => Relation.Actual.Tx,
                        Plan_Source   => Plan_Entry.Source,
                        Actual_Source => Relation.Actual.Source));
               end;
            elsif not Retired_As_Of (Plan_Entry) then
               Result.Open_Plans.Append
                 (Open_Plan'(ID => Plan_Entry.ID, Tx => Plan_Entry.Tx));
            end if;
         end;
      end loop;

      return Result;
   end Observe;

end HRA.Plan_Temporal_Observation;
