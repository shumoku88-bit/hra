with Ada.Strings;       use Ada.Strings;
with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with HRA.Account;
with HRA.Cycle_Observation;
with HRA.Dates;         use type HRA.Dates.Date;
                        use type HRA.Dates.Day_Of_Week;
with HRA.Issue_Observation;
with HRA.Issues;        use type HRA.Issues.Issue_Due_Kind;
with HRA.Money;
with HRA.Plan;

package body HRA.Household_Home_Presentation is

   function Render_Amount (Amt : HRA.Money.Amount) return String is
   begin
      return HRA.Money.Render_Quantity (Amt.Val) & " " & HRA.Money.Code (Amt.Comm);
   end Render_Amount;

   function Resolve_Marker
     (Attention : HRA.Household_Home_Observation.Attention_Observation;
      Markers   : HRA.Report_Config.Calendar_Markers) return Character
   is
      use type HRA.Household_Home_Observation.Attention_Status;
      Plan_Count  : constant Natural :=
        (if Attention.Plan_Scheduled = HRA.Household_Home_Observation.Present then 1 else 0);
      Issue_Count : constant Natural :=
        (if Attention.Issue_Due = HRA.Household_Home_Observation.Present then 1 else 0);
      Cycle_Count : constant Natural :=
        (if Attention.Cycle_End = HRA.Household_Home_Observation.Present then 1 else 0);
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
      Last_Day_Num  : constant Positive :=
        HRA.Dates.Days_In_Month (Focus_Year, Focus_Month);

      First_Day_Str : constant String :=
        HRA.Dates.Image (Focus_Day) (1 .. 8) & "01";
      Last_Day_Str  : constant String :=
        HRA.Dates.Image (Focus_Day) (1 .. 8) &
        (if Last_Day_Num < 10 then "0" & Trim (Positive'Image (Last_Day_Num), Both)
         else Trim (Positive'Image (Last_Day_Num), Both));

      First_Date    : HRA.Dates.Date;
      Last_Date     : HRA.Dates.Date;
      Date_Stat     : HRA.Dates.Date_Status;
      Parsed_First  : constant Boolean :=
        HRA.Dates.Parse (First_Day_Str, First_Date, Date_Stat);
      Parsed_Last   : constant Boolean :=
        HRA.Dates.Parse (Last_Day_Str, Last_Date, Date_Stat);

      Grid_Start    : HRA.Dates.Date := First_Date;
      Start_Weekday : constant HRA.Dates.Day_Of_Week :=
        HRA.Dates.Day_Of_Week_Of (First_Date);

      Result        : Calendar_Grid;
   begin
      pragma Assert (Parsed_First and then Parsed_Last);
      Result.Year  := Focus_Year;
      Result.Month := Focus_Month;

      --  Rewind Grid_Start to previous Monday if month does not start on Monday
      case Start_Weekday is
         when HRA.Dates.Monday =>
            null;
         when HRA.Dates.Tuesday =>
            Grid_Start := HRA.Dates.Previous (Grid_Start);
         when HRA.Dates.Wednesday =>
            for I in 1 .. 2 loop
               Grid_Start := HRA.Dates.Previous (Grid_Start);
            end loop;
         when HRA.Dates.Thursday =>
            for I in 1 .. 3 loop
               Grid_Start := HRA.Dates.Previous (Grid_Start);
            end loop;
         when HRA.Dates.Friday =>
            for I in 1 .. 4 loop
               Grid_Start := HRA.Dates.Previous (Grid_Start);
            end loop;
         when HRA.Dates.Saturday =>
            for I in 1 .. 5 loop
               Grid_Start := HRA.Dates.Previous (Grid_Start);
            end loop;
         when HRA.Dates.Sunday =>
            for I in 1 .. 6 loop
               Grid_Start := HRA.Dates.Previous (Grid_Start);
            end loop;
      end case;

      declare
         Current_Day : HRA.Dates.Date := Grid_Start;
         Done        : Boolean := False;
      begin
         while not Done loop
            declare
               Week : Calendar_Week;
            begin
               for Wday in HRA.Dates.Day_Of_Week loop
                  declare
                     Cell : Calendar_Cell;
                  begin
                     Cell.Date_Value          := Current_Day;
                     Cell.Day_Number          := HRA.Dates.Day (Current_Day);
                     Cell.Is_Current_Month    :=
                       (HRA.Dates.Year (Current_Day) = Focus_Year
                        and then HRA.Dates.Month (Current_Day) = Focus_Month);
                     Cell.Is_Selected         := (Current_Day = Focus_Day);
                     Cell.Is_Observed_Through := (Current_Day = Obs_Through);
                     Cell.Is_Future           := (Current_Day > Obs_Through);
                     Cell.Attention           :=
                       HRA.Household_Home_Observation.Day_Attention
                         (Observation, Current_Day);
                     Cell.Marker              :=
                       Resolve_Marker (Cell.Attention, Markers);

                     Week (Wday) := Cell;
                  end;

                  if Current_Day = Last_Date and then Wday = HRA.Dates.Sunday then
                     Done := True;
                  end if;

                  Current_Day := HRA.Dates.Next (Current_Day);
               end loop;

               Result.Weeks.Append (Week);

               if Current_Day > Last_Date then
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
               Result : Actual_Presentation
                 (Status => HRA.Household_Home_Observation.Available);
            begin
               for Tx of Obs.Transactions loop
                  declare
                     Item         : Actual_Item;
                     Postings_Buf : Unbounded_String;
                     Total_Buf    : Unbounded_String;
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

                     if not Tx.Postings.Is_Empty then
                        Total_Buf :=
                          To_Unbounded_String
                            (Render_Amount (Tx.Postings.Element (1).Amt));
                     end if;
                     Item.Total_Amount := Total_Buf;

                     Result.Items.Append (Item);
                  end;
               end loop;
               return Result;
            end;

         when HRA.Household_Home_Observation.Unavailable =>
            declare
               Result : Actual_Presentation
                 (Status => HRA.Household_Home_Observation.Unavailable);
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
               Result : Plan_Presentation
                 (Status => HRA.Household_Home_Observation.Available);
            begin
               for P of Obs.Open_Plans loop
                  declare
                     Item         : Plan_Item;
                     Postings_Buf : Unbounded_String;
                     Total_Buf    : Unbounded_String;
                     First_Post   : Boolean := True;
                  begin
                     Item.Plan_Id       :=
                       To_Unbounded_String (HRA.Plan.Text (P.ID));
                     Item.Due_Date_Text :=
                       To_Unbounded_String (HRA.Dates.Image (P.Tx.Date));
                     Item.Status_Text   := To_Unbounded_String ("Open");
                     Item.Description   := P.Tx.Code_Or_Payee;

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

                     if not P.Tx.Postings.Is_Empty then
                        Total_Buf :=
                          To_Unbounded_String
                            (Render_Amount (P.Tx.Postings.Element (1).Amt));
                     end if;
                     Item.Total_Amount := Total_Buf;

                     Result.Items.Append (Item);
                  end;
               end loop;
               return Result;
            end;

         when HRA.Household_Home_Observation.Unavailable =>
            declare
               Result : Plan_Presentation
                 (Status => HRA.Household_Home_Observation.Unavailable);
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
               Result : Issue_Presentation
                 (Status => HRA.Household_Home_Observation.Available);
            begin
               for I of Obs.Due_Issues loop
                  declare
                     Item : Issue_Item;
                  begin
                     Item.Issue_Id      :=
                       To_Unbounded_String (HRA.Issues.Text (I.Issue.ID));
                     Item.Title         := I.Issue.Title;
                     Item.Category      := I.Issue.Category;
                     Item.Status_Text   :=
                       To_Unbounded_String
                         (HRA.Issue_Observation.As_Of_Status'Image (I.Status_As_Of));
                     Item.Details_Text  := I.Issue.Details;

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
               Result : Issue_Presentation
                 (Status => HRA.Household_Home_Observation.Unavailable);
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
               Result    : Cycle_Presentation
                 (Status => HRA.Household_Home_Observation.Available);
               Prev      : constant HRA.Dates.Half_Open_Period :=
                 Obs.Observation.Previous_Window;
               Curr      : constant HRA.Dates.Half_Open_Period :=
                 Obs.Observation.Current_Window;
               Prev_End  : constant HRA.Dates.Date :=
                 HRA.Dates.Previous (HRA.Dates.Limit (Prev));
               Curr_End  : constant HRA.Dates.Date :=
                 HRA.Dates.Previous (HRA.Dates.Limit (Curr));
            begin
               Result.Has_Previous_Window := True;
               Result.Previous_Window_Text :=
                 To_Unbounded_String
                   (HRA.Dates.Image (HRA.Dates.First (Prev)) & " .. " &
                    HRA.Dates.Image (Prev_End));

               Result.Has_Current_Window := True;
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
               Result : Cycle_Presentation
                 (Status => HRA.Household_Home_Observation.Unavailable);
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
        HRA.Household_Home_Observation.Selected_Attention (Observation);

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

   function Format_Cell (Cell : Calendar_Cell) return String is
      Day_Str : constant String :=
        (if Cell.Day_Number < 10 then " " & Trim (Positive'Image (Cell.Day_Number), Both)
         else Trim (Positive'Image (Cell.Day_Number), Both));
      M : constant Character := Cell.Marker;
   begin
      if Cell.Is_Selected then
         if M /= ' ' then
            return "[" & Day_Str & M & "]";
         else
            return "[" & Day_Str & "] ";
         end if;
      else
         if M /= ' ' then
            return " " & Day_Str & M & " ";
         else
            return "  " & Day_Str & "  ";
         end if;
      end if;
   end Format_Cell;

   function Month_Name (Month_Num : Positive) return String is
   begin
      return
        (case Month_Num is
            when 1 => "January",
            when 2 => "February",
            when 3 => "March",
            when 4 => "April",
            when 5 => "May",
            when 6 => "June",
            when 7 => "July",
            when 8 => "August",
            when 9 => "September",
            when 10 => "October",
            when 11 => "November",
            when 12 => "December",
            when others => "Unknown");
   end Month_Name;

   function Render_Calendar_Grid (Grid : Calendar_Grid) return String is
      Buf : Unbounded_String;
      Title : constant String :=
        Month_Name (Grid.Month) & " " & Trim (Positive'Image (Grid.Year), Both);
   begin
      Append (Buf, "        " & Title & ASCII.LF);
      Append (Buf, "  Mon  Tue  Wed  Thu  Fri  Sat  Sun" & ASCII.LF);

      for Week of Grid.Weeks loop
         for Wday in HRA.Dates.Day_Of_Week loop
            Append (Buf, Format_Cell (Week (Wday)));
         end loop;
         Append (Buf, ASCII.LF);
      end loop;

      return To_String (Buf);
   end Render_Calendar_Grid;

   function Render_Home (Pres : Home_Presentation) return String is
      Buf : Unbounded_String;
      Focus_Wday : constant String :=
        HRA.Dates.Day_Of_Week'Image
          (HRA.Dates.Day_Of_Week_Of (Pres.Selected_Day));
   begin
      Append
        (Buf,
         "================================================================================" &
         ASCII.LF);
      Append
        (Buf,
         " Household Home: " & HRA.Dates.Image (Pres.Observed_Through) &
         "  [Focus: " & HRA.Dates.Image (Pres.Selected_Day) &
         (if Pres.Is_Future_Focus then " (Future)]" else "]") & ASCII.LF);
      Append
        (Buf,
         "================================================================================" &
         ASCII.LF);

      Append (Buf, Render_Calendar_Grid (Pres.Calendar));
      Append
        (Buf,
         "--------------------------------------------------------------------------------" &
         ASCII.LF);
      Append
        (Buf,
         " Selected Day: " & HRA.Dates.Image (Pres.Selected_Day) &
         " (" & Focus_Wday & ")" &
         (if Pres.Is_Future_Focus then "  [Future coordinate]" else "") &
         ASCII.LF);
      Append
        (Buf,
         " Horizon     : " & HRA.Dates.Image (Pres.Observed_Through) &
         ASCII.LF);
      Append
        (Buf,
         " Attention   : Plan: " &
         HRA.Household_Home_Observation.Attention_Status'Image
           (Pres.Attention.Plan_Scheduled) &
         ", Issue: " &
         HRA.Household_Home_Observation.Attention_Status'Image
           (Pres.Attention.Issue_Due) &
         ", Cycle: " &
         HRA.Household_Home_Observation.Attention_Status'Image
           (Pres.Attention.Cycle_End) &
         ASCII.LF);
      Append
        (Buf,
         "--------------------------------------------------------------------------------" &
         ASCII.LF);

      --  Actual Section
      Append (Buf, " Actual Transactions:" & ASCII.LF);
      case Pres.Actual.Status is
         when HRA.Household_Home_Observation.Available =>
            if Pres.Actual.Items.Is_Empty then
               Append (Buf, "   (none recorded)" & ASCII.LF);
            else
               for Item of Pres.Actual.Items loop
                  Append
                    (Buf,
                     "   - " & To_String (Item.Description) & "   " &
                     To_String (Item.Total_Amount) & ASCII.LF);
                  if Length (Item.Postings_Text) > 0 then
                     Append (Buf, To_String (Item.Postings_Text) & ASCII.LF);
                  end if;
               end loop;
            end if;
         when HRA.Household_Home_Observation.Unavailable =>
            Append
              (Buf,
               "   [Unavailable] " &
               To_String (Pres.Actual.Unavailable_Message) & ASCII.LF);
      end case;
      Append (Buf, ASCII.LF);

      --  Plan Section
      Append (Buf, " Planned Payments:" & ASCII.LF);
      case Pres.Plan.Status is
         when HRA.Household_Home_Observation.Available =>
            if Pres.Plan.Items.Is_Empty then
               Append (Buf, "   (none scheduled)" & ASCII.LF);
            else
               for Item of Pres.Plan.Items loop
                  Append
                    (Buf,
                     "   - " & To_String (Item.Due_Date_Text) & "  " &
                     To_String (Item.Status_Text) & "  " &
                     To_String (Item.Plan_Id) & "  " &
                     To_String (Item.Total_Amount) & ASCII.LF);
                  Append
                    (Buf,
                     "       " & To_String (Item.Description) & ASCII.LF);
                  if Length (Item.Postings_Text) > 0 then
                     Append (Buf, To_String (Item.Postings_Text) & ASCII.LF);
                  end if;
               end loop;
            end if;
         when HRA.Household_Home_Observation.Unavailable =>
            Append
              (Buf,
               "   [Unavailable] " &
               To_String (Pres.Plan.Unavailable_Message) & ASCII.LF);
      end case;
      Append (Buf, ASCII.LF);

      --  Issue Section
      Append (Buf, " Due Issues:" & ASCII.LF);
      case Pres.Issue.Status is
         when HRA.Household_Home_Observation.Available =>
            if Pres.Issue.Items.Is_Empty then
               Append (Buf, "   (none due)" & ASCII.LF);
            else
               for Item of Pres.Issue.Items loop
                  Append
                    (Buf,
                     "   - [" & To_String (Item.Status_Text) & "] " &
                     To_String (Item.Issue_Id) & ": " &
                     To_String (Item.Title) & " [" &
                     To_String (Item.Category) & "]");
                  if Length (Item.Amount_Text) > 0 then
                     Append (Buf, "  " & To_String (Item.Amount_Text));
                  end if;
                  Append (Buf, ASCII.LF);
               end loop;
            end if;
         when HRA.Household_Home_Observation.Unavailable =>
            Append
              (Buf,
               "   [Unavailable] " &
               To_String (Pres.Issue.Unavailable_Message) & ASCII.LF);
      end case;
      Append (Buf, ASCII.LF);

      --  Cycle Section
      Append (Buf, " Cycle:" & ASCII.LF);
      case Pres.Cycle.Status is
         when HRA.Household_Home_Observation.Available =>
            if Pres.Cycle.Has_Previous_Window then
               Append
                 (Buf,
                  "   Previous Window: " &
                  To_String (Pres.Cycle.Previous_Window_Text) & ASCII.LF);
            end if;
            if Pres.Cycle.Has_Current_Window then
               Append
                 (Buf,
                  "   Current Window : " &
                  To_String (Pres.Cycle.Current_Window_Text) & ASCII.LF);
            end if;
            Append
              (Buf,
               "   Role on Focus  : " &
               To_String (Pres.Cycle.Focus_Cycle_Role) & ASCII.LF);
         when HRA.Household_Home_Observation.Unavailable =>
            Append
              (Buf,
               "   [Unavailable] " &
               To_String (Pres.Cycle.Unavailable_Message) & ASCII.LF);
      end case;
      Append
        (Buf,
         "================================================================================" &
         ASCII.LF);

      return To_String (Buf);
   end Render_Home;

end HRA.Household_Home_Presentation;
