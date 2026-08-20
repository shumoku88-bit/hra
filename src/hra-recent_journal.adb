package body HRA.Recent_Journal is

   use type HRA.Dates.Date;

   function Observe
     (Actual       : HRA.Actual_Admission.Actual_Observation;
      Through_Date : HRA.Dates.Date;
      Count        : Positive) return Observation
   is
      Result   : Observation;
      Selected : Natural := 0;
      Index    : Natural :=
        HRA.Actual_Admission.Transaction_Count (Actual);
   begin
      Result.Through_Date := Through_Date;
      Result.Requested := Count;
      Result.Entries.Clear;

      --  Actual admission owns source-order Transaction/provenance alignment.
      --  Walk backwards for newest-first presentation without rebuilding that
      --  association from display text or accepting independently paired data.
      while Index > 0 and then Selected < Count loop
         declare
            Item : constant HRA.Actual_Admission.Actual_Transaction_Entry :=
              HRA.Actual_Admission.Transaction_At (Actual, Index);
         begin
            if Item.Tx.Date <= Through_Date then
               Result.Entries.Append
                 (Recent_Entry'
                    (Value    => Item.Tx,
                     Identity => Item.Identity,
                     Source   => Item.Source));
               Selected := Selected + 1;
            end if;
         end;
         Index := Index - 1;
      end loop;

      return Result;
   end Observe;

end HRA.Recent_Journal;
