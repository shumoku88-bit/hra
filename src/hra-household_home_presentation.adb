with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA.Account;
with HRA.Cycle_Observation;
with HRA.Dates;             use type HRA.Dates.Date;
                            use type HRA.Dates.Day_Of_Week;
with HRA.Issue_Observation;
with HRA.Issues;            use type HRA.Issues.Issue_Due_Kind;
with HRA.Money;
with HRA.Plan;

package body HRA.Household_Home_Presentation is

   function Render_Amount (Amt : HRA.Money.Amount) return String is
   begin
      return HRA.Money.Render_Quantity (Amt.Val) & " " & HRA.Money.Code (Amt.Comm);
   end Render_Amount;

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

   function Resolve_Marker
     (Attention : Attention_Summary;
      Markers   : HRA.Report_Config.Calendar_Markers) return Character
   is
      Plan_Count  : constant Natural :=
        (if Attention.Plan_Scheduled = Present then 1 else 0);
      Issue_Count : constant Natural :=
        (if Attention.Issue_Due = Present then 1 else 0);
      Cycle_Count : constant Natural :=
        (if Attention.Cycle_End = Present then 1 else 0);
      Total_Count : constant Natural := Plan_Count + Issue_Count + Cycle_Count;
   begin
      if Total_Count >= 2 then
         return Markers.Multiple;
      elsif Plan_Count = 1 then
         return Markers.Plan_Due;
      elsif Issue_Count = 1 then
         return Markers.Issue_Due;
      elsif Cycle_Count = 1 then
         return Markers.Cycle_End;
      else
         return ' ';
      end if;
   end Resolve_Marker;

   function Resolve_Marker
     (Attention : HRA.Household_Home_Observation.Attention_Observation;
      Markers   : HRA.Report_Config.Calendar_Markers) return Character is
   begin
      return Resolve_Marker (Map_Attention (Attention), Markers);
   end Resolve_Marker;

   function Build_Calendar_Grid
     (Observation : HRA.Household_Home_Observation.Home_Observation;
      Markers     : HRA.Report_Config.Calendar_Markers) return Calendar_Grid
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
         Pad_Day_Num : Positive := 1;
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
                        Cell.Date_Value          := Current_Day;
                        Cell.Day_Number          := HRA.Dates.Day (Current_Day);
                        Cell.Is_Current_Month    :=
                          (HRA.Dates.Year (Current_Day) = Focus_Year
                           and then HRA.Dates.Month (Current_Day) = Focus_Month);
                        Cell.Is_Selected         := (Current_Day = Focus_Day);
                        Cell.Is_Observed_Through := (Current_Day = Obs_Through);
                        Cell.Is_Future           := (Current_Day > Obs_Through);
                        Cell.Attention           :=
                          Map_Attention
                            (HRA.Household_Home_Observation.Day_Attention
                               (Observation, Current_Day));
                        Cell.Marker              :=
                          Resolve_Marker (Cell.Attention, Markers);

                        if Current_Day = Last_Date and then Wday = HRA.Dates.Sunday then
                           Done := True;
                        end if;

                        if HRA.Dates.Has_Next (Current_Day) then
                           Current_Day := HRA.Dates.Next (Current_Day);
                        else
                           Past_Limit := True;
                        end if;
                     else
                        --  Gracefully pad trailing week cells beyond Gregorian limit (e.g. 9999-12)
                        Cell.Date_Value          := Last_Date;
                        Cell.Day_Number          := Pad_Day_Num;
                        Cell.Is_Current_Month    := False;
                        Cell.Is_Selected         := False;
                        Cell.Is_Observed_Through := False;
                        Cell.Is_Future           := True;
                        Cell.Attention           := (others => Absent);
                        Cell.Marker              := ' ';
                        Pad_Day_Num              := Pad_Day_Num + 1;
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
     (Obs         : HRA.Household_Home_Observation.Actual_Home_Observation;
      Obs_Through : HRA.Dates.Date) return Actual_Presentation
   is
   begin
      case Obs.Status is
         when HRA.Household_Home_Observation.Available =>
            declare
               Result : Actual_Presentation (Status => Available);
            begin
               for Tx of Obs.Transactions loop
                  declare
                     Item         : Actual_Item;
                     Postings_Buf : Unbounded_String;
                     First_Post   : Boolean := True;
                  begin
                     Item.Transaction_Id := Tx.Event_ID;
                     Item.Date_Text      :=
                       To_Unbounded_String (HRA.Dates.Image (Tx.Date));
                     Item.Description    := Tx.Code_Or_Payee;

                     for P of Tx.Postings loop
                        if not First_Post then
                           Append (Postings_Buf, ASCII.LF);
                        end if;
                        First_Post := False;
                        Append
                          (Postings_Buf,
                           "       " & HRA.Account.Name (P.Acc) & "  " &
                           Render_Amount (P.Amt));
                     end loop;
                     Item.Postings_Text := Postings_Buf;

                     Result.Items.Append (Item);
                  end;
               end loop;
               return Result;
            end;

         when HRA.Household_Home_Observation.Unavailable =>
            declare
               Result : Actual_Presentation (Status => Unavailable);
            begin
               case Obs.Reason is
                  when HRA.Household_Home_Observation.Observation_Horizon_Exceeded =>
                     Result.Unavailable_Message :=
                       To_Unbounded_String
                         ("Observation horizon exceeded (Observed through: " &
                          HRA.Dates.Image (Obs_Through) & ")");
               end case;
               return Result;
            end;
      end case;
   end Build_Actual_Presentation;

   function Build_Plan_Presentation
     (Obs : HRA.Household_Home_Observation.Plan_Home_Observation) return Plan_Presentation
   is
   begin
      case Obs.Status is
         when HRA.Household_Home_Observation.Available =>
            declare
               Result : Plan_Presentation (Status => Available);
            begin
               for P of Obs.Open_Plans loop
                  declare
                     Item         : Plan_Item;
                     Postings_Buf : Unbounded_String;
                     First_Post   : Boolean := True;
                  begin
                     Item.Plan_Id             :=
                       To_Unbounded_String (HRA.Plan.Text (P.ID));
                     Item.Scheduled_Date_Text :=
                       To_Unbounded_String (HRA.Dates.Image (P.Tx.Date));
                     Item.Status_Text         := To_Unbounded_String ("Open");
                     Item.Description         := P.Tx.Code_Or_Payee;

                     for Post of P.Tx.Postings loop
                        if not First_Post then
                           Append (Postings_Buf, ASCII.LF);
                        end if;
                        First_Post := False;
                        Append
                          (Postings_Buf,
                           "       " & HRA.Account.Name (Post.Acc) & "  " &
                           Render_Amount (Post.Amt));
                     end loop;
                     Item.Postings_Text := Postings_Buf;

                     Result.Items.Append (Item);
                  end;
               end loop;
               return Result;
            end;

         when HRA.Household_Home_Observation.Unavailable =>
            declare
               Result : Plan_Presentation (Status => Unavailable);
            begin
               Result.Unavailable_Message :=
                 To_Unbounded_String
                   ("Plan observation unavailable: " &
                    To_String (Obs.Error.Message));
               return Result;
            end;
      end case;
   end Build_Plan_Presentation;

   function Build_Issue_Presentation
     (Obs : HRA.Household_Home_Observation.Issue_Home_Observation) return Issue_Presentation
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
                     Item.Issue_Id     :=
                       To_Unbounded_String (HRA.Issues.Text (I.Issue.ID));
                     Item.Title        := I.Issue.Title;
                     Item.Category     := I.Issue.Category;
                     Item.Status_Text  :=
                       To_Unbounded_String
                         (HRA.Issue_Observation.As_Of_Status'Image (I.Status_As_Of));
                     Item.Details_Text := I.Issue.Details;

                     if I.Issue.Due.Kind = HRA.Issues.Due_On then
                        Item.Due_Date_Text :=
                          To_Unbounded_String (HRA.Dates.Image (I.Issue.Due.Due_Date));
                     else
                        Item.Due_Date_Text := Null_Unbounded_String;
                     end if;

                     if I.Issue.Amt.Has_Amount then
                        Item.Amount_Text :=
                          To_Unbounded_String (Render_Amount (I.Issue.Amt.Value));
                     else
                        Item.Amount_Text := Null_Unbounded_String;
                     end if;

                     Result.Items.Append (Item);
                  end;
               end loop;
               return Result;
            end;

         when HRA.Household_Home_Observation.Unavailable =>
            declare
               Result : Issue_Presentation (Status => Unavailable);
            begin
               case Obs.Reason is
                  when HRA.Household_Home_Observation.Closure_Timing_Undetermined =>
                     Result.Unavailable_Message :=
                       To_Unbounded_String
                         ("Closure timing undetermined for issues due on this day");
               end case;
               return Result;
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
               Result    : Cycle_Presentation (Status => Available);
               Prev      : constant HRA.Dates.Half_Open_Period :=
                 Obs.Observation.Previous_Window;
               Curr      : constant HRA.Dates.Half_Open_Period :=
                 Obs.Observation.Current_Window;
               Prev_End  : constant HRA.Dates.Date :=
                 HRA.Dates.Previous (HRA.Dates.Limit (Prev));
               Curr_End  : constant HRA.Dates.Date :=
                 HRA.Dates.Previous (HRA.Dates.Limit (Curr));
            begin
               Result.Previous_Window_Text :=
                 To_Unbounded_String
                   (HRA.Dates.Image (HRA.Dates.First (Prev)) & " .. " &
                    HRA.Dates.Image (Prev_End));

               Result.Current_Window_Text :=
                 To_Unbounded_String
                   (HRA.Dates.Image (HRA.Dates.First (Curr)) & " .. " &
                    HRA.Dates.Image (Curr_End));

               if Focus_Day = Prev_End then
                  Result.Focus_Cycle_Role :=
                    To_Unbounded_String ("Previous Cycle End");
               elsif Focus_Day = Curr_End then
                  Result.Focus_Cycle_Role :=
                    To_Unbounded_String ("Current Cycle End");
               elsif HRA.Dates.Contains (Curr, Focus_Day) then
                  Result.Focus_Cycle_Role :=
                    To_Unbounded_String ("Current Cycle");
               elsif HRA.Dates.Contains (Prev, Focus_Day) then
                  Result.Focus_Cycle_Role :=
                    To_Unbounded_String ("Previous Cycle");
               else
                  Result.Focus_Cycle_Role :=
                    To_Unbounded_String ("Outside Known Cycles");
               end if;

               return Result;
            end;

         when HRA.Household_Home_Observation.Unavailable =>
            declare
               Result : Cycle_Presentation (Status => Unavailable);
            begin
               case Obs.Failure.Reason is
                  when HRA.Household_Home_Observation.Plan_Dependency_Unavailable =>
                     Result.Unavailable_Message :=
                       To_Unbounded_String
                         ("Cycle unavailable due to Plan dependency: " &
                          To_String (Obs.Failure.Plan_Error.Message));
                  when HRA.Household_Home_Observation.Cycle_Resolution_Failed =>
                     Result.Unavailable_Message :=
                       To_Unbounded_String
                         ("Cycle resolution failed: " &
                          HRA.Cycle_Observation.Resolve_Status'Image
                            (Obs.Failure.Cycle_Error));
               end case;
               return Result;
            end;
      end case;
   end Build_Cycle_Presentation;

   function Present
     (Observation : HRA.Household_Home_Observation.Home_Observation;
      Markers     : HRA.Report_Config.Calendar_Markers :=
        (Cycle_End => '|', Plan_Due => '$', Issue_Due => '!', Multiple => '+'))
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

      Result.Calendar := Build_Calendar_Grid (Observation, Markers);
      Result.Actual   :=
        Build_Actual_Presentation
          (HRA.Household_Home_Observation.Actual (Observation),
           Obs_Through);
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
