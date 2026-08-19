with HRA.Dates;  use type HRA.Dates.Date;
                 use type HRA.Dates.Day_Of_Week;
with HRA.Issues; use type HRA.Issues.Issue_Due_Kind;

package body HRA.Household_Home_Presentation is

   function Map_Attention_Status
     (Status : HRA.Household_Home_Observation.Attention_Status) return Attention_State is
   begin
      return
        (case Status is
            when HRA.Household_Home_Observation.Absent => Absent,
            when HRA.Household_Home_Observation.Present => Present,
            when HRA.Household_Home_Observation.Unavailable => Unavailable);
   end Map_Attention_Status;

   function Map_Attention
     (Obs : HRA.Household_Home_Observation.Attention_Observation) return Attention_Summary is
   begin
      return
        (Plan_Scheduled => Map_Attention_Status (Obs.Plan_Scheduled),
         Issue_Due      => Map_Attention_Status (Obs.Issue_Due),
         Cycle_End      => Map_Attention_Status (Obs.Cycle_End));
   end Map_Attention;

   function Build_Calendar_Grid
     (Observation : HRA.Household_Home_Observation.Home_Observation)
      return Calendar_Grid
   is
      Focus_Day     : constant HRA.Dates.Date :=
        HRA.Household_Home_Observation.Selected_Day (Observation);
      Obs_Through   : constant HRA.Dates.Date :=
        HRA.Household_Home_Observation.Observed_Through (Observation);
      Focus_Year    : constant Positive := HRA.Dates.Year (Focus_Day);
      Focus_Month   : constant Positive := HRA.Dates.Month (Focus_Day);

      First_Date    : constant HRA.Dates.Date :=
        HRA.Dates.First_Of_Month (Focus_Day);
      Last_Date     : constant HRA.Dates.Date :=
        HRA.Dates.Last_Of_Month (Focus_Day);

      Grid_Start    : HRA.Dates.Date := First_Date;
      Start_Weekday : constant HRA.Dates.Day_Of_Week :=
        HRA.Dates.Day_Of_Week_Of (First_Date);

      Result        : Calendar_Grid;
   begin
      Result.Year  := Focus_Year;
      Result.Month := Focus_Month;

      --  Rewind Grid_Start to previous Monday if month does not start on Monday.
      --  Bounded by Gregorian origin (year 1 month 1 starts on Monday).
      case Start_Weekday is
         when HRA.Dates.Monday =>
            null;
         when HRA.Dates.Tuesday =>
            if HRA.Dates.Has_Previous (Grid_Start) then
               Grid_Start := HRA.Dates.Previous (Grid_Start);
            end if;
         when HRA.Dates.Wednesday =>
            for I in 1 .. 2 loop
               if HRA.Dates.Has_Previous (Grid_Start) then
                  Grid_Start := HRA.Dates.Previous (Grid_Start);
               end if;
            end loop;
         when HRA.Dates.Thursday =>
            for I in 1 .. 3 loop
               if HRA.Dates.Has_Previous (Grid_Start) then
                  Grid_Start := HRA.Dates.Previous (Grid_Start);
               end if;
            end loop;
         when HRA.Dates.Friday =>
            for I in 1 .. 4 loop
               if HRA.Dates.Has_Previous (Grid_Start) then
                  Grid_Start := HRA.Dates.Previous (Grid_Start);
               end if;
            end loop;
         when HRA.Dates.Saturday =>
            for I in 1 .. 5 loop
               if HRA.Dates.Has_Previous (Grid_Start) then
                  Grid_Start := HRA.Dates.Previous (Grid_Start);
               end if;
            end loop;
         when HRA.Dates.Sunday =>
            for I in 1 .. 6 loop
               if HRA.Dates.Has_Previous (Grid_Start) then
                  Grid_Start := HRA.Dates.Previous (Grid_Start);
               end if;
            end loop;
      end case;

      declare
         Current_Day : HRA.Dates.Date := Grid_Start;
         Done        : Boolean := False;
         Past_Limit  : Boolean := False;
      begin
         while not Done loop
            declare
               Week : Calendar_Week;
            begin
               for Wday in HRA.Dates.Day_Of_Week loop
                  declare
                     Cell : Calendar_Cell;
                  begin
                     if not Past_Limit then
                        Cell :=
                          (Kind                => Dated_Cell,
                           Date_Value          => Current_Day,
                           Is_Current_Month    =>
                             (HRA.Dates.Year (Current_Day) = Focus_Year
                              and then HRA.Dates.Month (Current_Day) = Focus_Month),
                           Is_Selected         => (Current_Day = Focus_Day),
                           Is_Observed_Through => (Current_Day = Obs_Through),
                           Is_Future           => (Current_Day > Obs_Through),
                           Attention           =>
                             Map_Attention
                               (HRA.Household_Home_Observation.Day_Attention
                                  (Observation, Current_Day)));

                        if Current_Day = Last_Date and then Wday = HRA.Dates.Sunday then
                           Done := True;
                        end if;

                        if HRA.Dates.Has_Next (Current_Day) then
                           Current_Day := HRA.Dates.Next (Current_Day);
                        else
                           Past_Limit := True;
                        end if;
                     else
                        --  Explicit typed padding beyond Gregorian limit (e.g. 9999-12 trailing cells)
                        Cell := (Kind => Out_Of_Range_Padding);
                     end if;

                     Week (Wday) := Cell;
                  end;
               end loop;

               Result.Weeks.Append (Week);

               if Past_Limit or else Current_Day > Last_Date then
                  Done := True;
               end if;
            end;
         end loop;
      end;

      return Result;
   end Build_Calendar_Grid;

   function Build_Actual_Presentation
     (Obs : HRA.Household_Home_Observation.Actual_Home_Observation)
      return Actual_Presentation
   is
   begin
      case Obs.Status is
         when HRA.Household_Home_Observation.Available =>
            declare
               Result : Actual_Presentation (Status => Available);
            begin
               for Tx of Obs.Transactions loop
                  declare
                     Item : Actual_Item;
                  begin
                     Item.Transaction_Id := Tx.Event_ID;
                     Item.Date           := Tx.Date;
                     Item.Description    := Tx.Code_Or_Payee;

                     for P of Tx.Postings loop
                        Item.Postings.Append
                          (Posting_Item'
                             (Account => P.Acc,
                              Amount  => P.Amt));
                     end loop;

                     Result.Items.Append (Item);
                  end;
               end loop;
               return Result;
            end;

         when HRA.Household_Home_Observation.Unavailable =>
            declare
               Reason : constant Actual_Unavailable_Reason :=
                 (case Obs.Reason is
                     when HRA.Household_Home_Observation.Observation_Horizon_Exceeded =>
                        Observation_Horizon_Exceeded);
            begin
               return (Status => Unavailable, Reason => Reason);
            end;
      end case;
   end Build_Actual_Presentation;

   function Build_Plan_Presentation
     (Obs : HRA.Household_Home_Observation.Plan_Home_Observation)
      return Plan_Presentation
   is
   begin
      case Obs.Status is
         when HRA.Household_Home_Observation.Available =>
            declare
               Result : Plan_Presentation (Status => Available);
            begin
               for P of Obs.Open_Plans loop
                  declare
                     Item : Plan_Item;
                  begin
                     Item.Plan_Id        := P.ID;
                     Item.Scheduled_Date := P.Tx.Date;
                     Item.Description    := P.Tx.Code_Or_Payee;

                     for Post of P.Tx.Postings loop
                        Item.Postings.Append
                          (Posting_Item'
                             (Account => Post.Acc,
                              Amount  => Post.Amt));
                     end loop;

                     Result.Items.Append (Item);
                  end;
               end loop;
               return Result;
            end;

         when HRA.Household_Home_Observation.Unavailable =>
            return (Status => Unavailable, Diagnostic => Obs.Error);
      end case;
   end Build_Plan_Presentation;

   function Build_Issue_Presentation
     (Obs : HRA.Household_Home_Observation.Issue_Home_Observation)
      return Issue_Presentation
   is
   begin
      case Obs.Status is
         when HRA.Household_Home_Observation.Available =>
            declare
               Result : Issue_Presentation (Status => Available);
            begin
               for I of Obs.Due_Issues loop
                  declare
                     Item : Issue_Item;
                  begin
                     Item.Issue_Id     := I.Issue.ID;
                     Item.Title        := I.Issue.Title;
                     Item.Category     := I.Issue.Category;
                     Item.Status_As_Of := I.Status_As_Of;
                     Item.Details      := I.Issue.Details;
                     Item.Amount       := I.Issue.Amt;

                     if I.Issue.Due.Kind = HRA.Issues.Due_On then
                        Item.Due_Date := I.Issue.Due.Due_Date;
                     else
                        Item.Due_Date := I.Issue.Recorded_On;
                     end if;

                     Result.Items.Append (Item);
                  end;
               end loop;
               return Result;
            end;

         when HRA.Household_Home_Observation.Unavailable =>
            declare
               Reason : constant Issue_Unavailable_Reason :=
                 (case Obs.Reason is
                     when HRA.Household_Home_Observation.Closure_Timing_Undetermined =>
                        Closure_Timing_Undetermined);
            begin
               return (Status => Unavailable, Reason => Reason);
            end;
      end case;
   end Build_Issue_Presentation;

   function Build_Cycle_Presentation
     (Obs       : HRA.Household_Home_Observation.Cycle_Home_Observation;
      Focus_Day : HRA.Dates.Date) return Cycle_Presentation
   is
   begin
      case Obs.Status is
         when HRA.Household_Home_Observation.Available =>
            declare
               Prev     : constant HRA.Dates.Half_Open_Period :=
                 Obs.Observation.Previous_Window;
               Curr     : constant HRA.Dates.Half_Open_Period :=
                 Obs.Observation.Current_Window;
               Prev_End : constant HRA.Dates.Date :=
                 HRA.Dates.Previous (HRA.Dates.Limit (Prev));
               Curr_End : constant HRA.Dates.Date :=
                 HRA.Dates.Previous (HRA.Dates.Limit (Curr));
               Role     : Cycle_Focus_Role;
            begin
               if Focus_Day = Prev_End then
                  Role := Previous_Cycle_End;
               elsif Focus_Day = Curr_End then
                  Role := Current_Cycle_End;
               elsif HRA.Dates.Contains (Curr, Focus_Day) then
                  Role := Current_Cycle;
               elsif HRA.Dates.Contains (Prev, Focus_Day) then
                  Role := Previous_Cycle;
               else
                  Role := Outside_Known_Cycles;
               end if;

               return
                 (Status          => Available,
                  Previous_Window => Prev,
                  Current_Window  => Curr,
                  Focus_Role      => Role);
            end;

         when HRA.Household_Home_Observation.Unavailable =>
            declare
               Detail : Cycle_Unavailable_Detail;
            begin
               case Obs.Failure.Reason is
                  when HRA.Household_Home_Observation.Plan_Dependency_Unavailable =>
                     Detail :=
                       (Reason     => Plan_Dependency_Unavailable,
                        Plan_Error => Obs.Failure.Plan_Error);
                  when HRA.Household_Home_Observation.Cycle_Resolution_Failed =>
                     Detail :=
                       (Reason      => Cycle_Resolution_Failed,
                        Cycle_Error => Obs.Failure.Cycle_Error);
               end case;
               return (Status => Unavailable, Failure => Detail);
            end;
      end case;
   end Build_Cycle_Presentation;

   function Present
     (Observation : HRA.Household_Home_Observation.Home_Observation)
      return Home_Presentation
   is
      Focus_Day   : constant HRA.Dates.Date :=
        HRA.Household_Home_Observation.Selected_Day (Observation);
      Obs_Through : constant HRA.Dates.Date :=
        HRA.Household_Home_Observation.Observed_Through (Observation);
      Result      : Home_Presentation;
   begin
      Result.Observed_Through := Obs_Through;
      Result.Selected_Day     := Focus_Day;
      Result.Is_Future_Focus  := (Focus_Day > Obs_Through);
      Result.Attention        :=
        Map_Attention
          (HRA.Household_Home_Observation.Selected_Attention (Observation));

      Result.Calendar := Build_Calendar_Grid (Observation);
      Result.Actual   :=
        Build_Actual_Presentation
          (HRA.Household_Home_Observation.Actual (Observation));
      Result.Plan     :=
        Build_Plan_Presentation
          (HRA.Household_Home_Observation.Plan (Observation));
      Result.Issue    :=
        Build_Issue_Presentation
          (HRA.Household_Home_Observation.Issue (Observation));
      Result.Cycle    :=
        Build_Cycle_Presentation
          (HRA.Household_Home_Observation.Cycle (Observation),
           Focus_Day);

      return Result;
   end Present;

end HRA.Household_Home_Presentation;
