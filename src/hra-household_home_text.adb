with Ada.Strings;           use Ada.Strings;
with Ada.Strings.Fixed;     use Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA.Account;
with HRA.Cycle_Observation;
with HRA.Dates;
with HRA.Issue_Observation;
with HRA.Issues;
with HRA.Money;
with HRA.Plan;

package body HRA.Household_Home_Text is

   function Render_Amount (Amt : HRA.Money.Amount) return String is
   begin
      return HRA.Money.Render_Quantity (Amt.Val) & " " & HRA.Money.Code (Amt.Comm);
   end Render_Amount;

   function Resolve_Marker
     (Attention : HRA.Household_Home_Presentation.Attention_Summary;
      Markers   : HRA.Report_Config.Calendar_Markers :=
        (Cycle_End => '|', Plan_Due => '$', Issue_Due => '!', Multiple => '+'))
      return Character
   is
      use HRA.Household_Home_Presentation;
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

   function Format_Cell
     (Cell    : HRA.Household_Home_Presentation.Calendar_Cell;
      Markers : HRA.Report_Config.Calendar_Markers :=
        (Cycle_End => '|', Plan_Due => '$', Issue_Due => '!', Multiple => '+'))
      return String
   is
      use HRA.Household_Home_Presentation;
   begin
      case Cell.Kind is
         when Out_Of_Range_Padding =>
            return "     ";
         when Dated_Cell =>
            declare
               Day_Num : constant Positive := HRA.Dates.Day (Cell.Date_Value);
               Day_Str : constant String :=
                 (if Day_Num < 10
                  then " " & Trim (Positive'Image (Day_Num), Both)
                  else Trim (Positive'Image (Day_Num), Both));
               M       : constant Character := Resolve_Marker (Cell.Attention, Markers);
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
                     return "  " & Day_Str & " ";
                  end if;
               end if;
            end;
      end case;
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

   function Render_Calendar_Grid
     (Grid    : HRA.Household_Home_Presentation.Calendar_Grid;
      Markers : HRA.Report_Config.Calendar_Markers :=
        (Cycle_End => '|', Plan_Due => '$', Issue_Due => '!', Multiple => '+'))
      return String
   is
      Buf   : Unbounded_String;
      Title : constant String :=
        Month_Name (Grid.Month) & " " & Trim (Positive'Image (Grid.Year), Both);
   begin
      Append (Buf, "        " & Title & ASCII.LF);
      Append (Buf, "  Mon  Tue  Wed  Thu  Fri  Sat  Sun" & ASCII.LF);

      for Week of Grid.Weeks loop
         for Wday in HRA.Dates.Day_Of_Week loop
            Append (Buf, Format_Cell (Week (Wday), Markers));
         end loop;
         Append (Buf, ASCII.LF);
      end loop;

      return To_String (Buf);
   end Render_Calendar_Grid;

   function Focus_Role_Label
     (Role : HRA.Household_Home_Presentation.Cycle_Focus_Role) return String is
   begin
      case Role is
         when HRA.Household_Home_Presentation.Previous_Cycle_End =>
            return "Previous Cycle End";
         when HRA.Household_Home_Presentation.Current_Cycle_End =>
            return "Current Cycle End";
         when HRA.Household_Home_Presentation.Previous_Cycle =>
            return "Previous Cycle";
         when HRA.Household_Home_Presentation.Current_Cycle =>
            return "Current Cycle";
         when HRA.Household_Home_Presentation.Outside_Known_Cycles =>
            return "Outside Known Cycles";
      end case;
   end Focus_Role_Label;

   function Render_Home
     (Pres    : HRA.Household_Home_Presentation.Home_Presentation;
      Markers : HRA.Report_Config.Calendar_Markers :=
        (Cycle_End => '|', Plan_Due => '$', Issue_Due => '!', Multiple => '+'))
      return String
   is
      use HRA.Household_Home_Presentation;
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

      Append (Buf, Render_Calendar_Grid (Pres.Calendar, Markers));
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
         Attention_State'Image (Pres.Attention.Plan_Scheduled) &
         ", Issue: " &
         Attention_State'Image (Pres.Attention.Issue_Due) &
         ", Cycle: " &
         Attention_State'Image (Pres.Attention.Cycle_End) &
         ASCII.LF);
      Append
        (Buf,
         "--------------------------------------------------------------------------------" &
         ASCII.LF);

      --  Actual Section
      Append (Buf, " Actual Transactions:" & ASCII.LF);
      case Pres.Actual.Status is
         when Available =>
            if Pres.Actual.Items.Is_Empty then
               Append (Buf, "   (none recorded)" & ASCII.LF);
            else
               for Item of Pres.Actual.Items loop
                  Append
                    (Buf,
                     "   - " & To_String (Item.Description) & ASCII.LF);
                  for P of Item.Postings loop
                     Append
                       (Buf,
                        "       " & HRA.Account.Name (P.Account) & "  " &
                        Render_Amount (P.Amount) & ASCII.LF);
                  end loop;
               end loop;
            end if;
         when Unavailable =>
            case Pres.Actual.Reason is
               when Observation_Horizon_Exceeded =>
                  Append
                    (Buf,
                     "   [Unavailable] Observation horizon exceeded (Observed through: " &
                     HRA.Dates.Image (Pres.Observed_Through) & ")" & ASCII.LF);
            end case;
      end case;
      Append (Buf, ASCII.LF);

      --  Plan Section
      Append (Buf, " Planned Payments:" & ASCII.LF);
      case Pres.Plan.Status is
         when Available =>
            if Pres.Plan.Items.Is_Empty then
               Append (Buf, "   (none scheduled)" & ASCII.LF);
            else
               for Item of Pres.Plan.Items loop
                  Append
                    (Buf,
                     "   - Scheduled: " & HRA.Dates.Image (Item.Scheduled_Date) &
                     "  [Open] " &
                     HRA.Plan.Text (Item.Plan_Id) & ASCII.LF);
                  Append
                    (Buf,
                     "       " & To_String (Item.Description) & ASCII.LF);
                  for P of Item.Postings loop
                     Append
                       (Buf,
                        "       " & HRA.Account.Name (P.Account) & "  " &
                        Render_Amount (P.Amount) & ASCII.LF);
                  end loop;
               end loop;
            end if;
         when Unavailable =>
            Append
              (Buf,
               "   [Unavailable] Plan observation unavailable: " &
               To_String (Pres.Plan.Diagnostic.Message) & ASCII.LF);
      end case;
      Append (Buf, ASCII.LF);

      --  Issue Section
      Append (Buf, " Due Issues:" & ASCII.LF);
      case Pres.Issue.Status is
         when Available =>
            if Pres.Issue.Items.Is_Empty then
               Append (Buf, "   (none due)" & ASCII.LF);
            else
               for Item of Pres.Issue.Items loop
                  Append
                    (Buf,
                     "   - [" &
                     HRA.Issue_Observation.As_Of_Status'Image (Item.Status_As_Of) &
                     "] " &
                     HRA.Issues.Text (Item.Issue_Id) & ": " &
                     To_String (Item.Title) & " [" &
                     To_String (Item.Category) & "]");
                  if Item.Amount.Has_Amount then
                     Append (Buf, "  " & Render_Amount (Item.Amount.Value));
                  end if;
                  Append (Buf, ASCII.LF);
               end loop;
            end if;
         when Unavailable =>
            case Pres.Issue.Reason is
               when Closure_Timing_Undetermined =>
                  Append
                    (Buf,
                     "   [Unavailable] Closure timing undetermined for issues due on this day" &
                     ASCII.LF);
            end case;
      end case;
      Append (Buf, ASCII.LF);

      --  Cycle Section
      Append (Buf, " Cycle:" & ASCII.LF);
      case Pres.Cycle.Status is
         when Available =>
            declare
               Prev_End : constant HRA.Dates.Date :=
                 HRA.Dates.Previous (HRA.Dates.Limit (Pres.Cycle.Previous_Window));
               Curr_End : constant HRA.Dates.Date :=
                 HRA.Dates.Previous (HRA.Dates.Limit (Pres.Cycle.Current_Window));
            begin
               Append
                 (Buf,
                  "   Previous Window: " &
                  HRA.Dates.Image (HRA.Dates.First (Pres.Cycle.Previous_Window)) &
                  " .. " &
                  HRA.Dates.Image (Prev_End) & ASCII.LF);
               Append
                 (Buf,
                  "   Current Window : " &
                  HRA.Dates.Image (HRA.Dates.First (Pres.Cycle.Current_Window)) &
                  " .. " &
                  HRA.Dates.Image (Curr_End) & ASCII.LF);
               Append
                 (Buf,
                  "   Role on Focus  : " &
                  Focus_Role_Label (Pres.Cycle.Focus_Role) & ASCII.LF);
            end;
         when Unavailable =>
            case Pres.Cycle.Failure.Reason is
               when Plan_Dependency_Unavailable =>
                  Append
                    (Buf,
                     "   [Unavailable] Cycle unavailable due to Plan dependency: " &
                     To_String (Pres.Cycle.Failure.Plan_Error.Message) & ASCII.LF);
               when Cycle_Resolution_Failed =>
                  Append
                    (Buf,
                     "   [Unavailable] Cycle resolution failed: " &
                     HRA.Cycle_Observation.Resolve_Status'Image
                       (Pres.Cycle.Failure.Cycle_Error) & ASCII.LF);
            end case;
      end case;
      Append
        (Buf,
         "================================================================================" &
         ASCII.LF);

      return To_String (Buf);
   end Render_Home;

end HRA.Household_Home_Text;
