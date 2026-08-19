package body HRA.Issue_Observation is

   use type HRA.Dates.Date;
   use type HRA.Issues.Issue_Status;
   use type HRA.Issues.Issue_Due_Kind;
   use type HRA.Issues.Issue_Closed_Kind;

   function Observe
     (Inventory        : HRA.Issues.Issues_Inventory;
      Observed_Through : HRA.Dates.Date) return Observation
   is
      Result : Observation;
      Count  : constant Natural := HRA.Issues.Count (Inventory);
   begin
      Result.Observed_Through := Observed_Through;

      for I in 1 .. Count loop
         declare
            Item : constant HRA.Issues.Household_Issue :=
              HRA.Issues.Element (Inventory, I);
         begin
            if not (Item.Recorded_On > Observed_Through) then
               declare
                  St : As_Of_Status;
               begin
                  if Item.Status = HRA.Issues.Open then
                     St := Open;
                  elsif Item.Closed.Kind = HRA.Issues.Closed_On then
                     if Item.Closed.Closed_Date > Observed_Through then
                        --  Resolved or Dropped in future relative to Observed_Through:
                        --  was still Open as of Observed_Through.
                        St := Open;
                     else
                        if Item.Status = HRA.Issues.Resolved then
                           St := Resolved;
                        else
                           St := Dropped;
                        end if;
                     end if;
                  elsif Item.Closed.Kind = HRA.Issues.Closed_Undetermined then
                     St := Closure_Undetermined;
                  else
                     St := Open;
                  end if;

                  declare
                     Obs_Item : constant Observed_Issue :=
                       (Issue => Item, Status_As_Of => St);
                  begin
                     Result.All_Observed.Append (Obs_Item);
                     case St is
                        when Open =>
                           Result.Open_Issues.Append (Obs_Item);
                        when Resolved =>
                           Result.Resolved_Issues.Append (Obs_Item);
                        when Dropped =>
                           Result.Dropped_Issues.Append (Obs_Item);
                        when Closure_Undetermined =>
                           Result.Undetermined.Append (Obs_Item);
                     end case;
                  end;
               end;
            end if;
         end;
      end loop;

      return Result;
   end Observe;

   function Due_Issues_On
     (Obs        : Observation;
      Target_Day : HRA.Dates.Date) return Observed_Issue_Vectors.Vector
   is
      Result : Observed_Issue_Vectors.Vector;
   begin
      for Item of Obs.Open_Issues loop
         if Item.Issue.Due.Kind = HRA.Issues.Due_On
           and then Item.Issue.Due.Due_Date = Target_Day
         then
            Result.Append (Item);
         end if;
      end loop;
      return Result;
   end Due_Issues_On;

   function Has_Undetermined_Due_On
     (Obs        : Observation;
      Target_Day : HRA.Dates.Date) return Boolean
   is
   begin
      for Item of Obs.Undetermined loop
         if Item.Issue.Due.Kind = HRA.Issues.Due_On
           and then Item.Issue.Due.Due_Date = Target_Day
         then
            return True;
         end if;
      end loop;
      return False;
   end Has_Undetermined_Due_On;

end HRA.Issue_Observation;
