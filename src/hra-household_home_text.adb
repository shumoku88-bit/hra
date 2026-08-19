with Ada.Strings;           use Ada.Strings;
with Ada.Strings.Fixed;     use Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA.Dates;

package body HRA.Household_Home_Text is

   function Format_Cell
     (Cell : HRA.Household_Home_Presentation.Calendar_Cell) return String
   is
      Day_Str : constant String :=
        (if Cell.Day_Number < 10
         then " " & Trim (Positive'Image (Cell.Day_Number), Both)
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
            return "  " & Day_Str & " ";
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

   function Render_Calendar_Grid
     (Grid : HRA.Household_Home_Presentation.Calendar_Grid) return String
   is
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

   function Render_Home
     (Pres : HRA.Household_Home_Presentation.Home_Presentation) return String
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
                  if Length (Item.Postings_Text) > 0 then
                     Append (Buf, To_String (Item.Postings_Text) & ASCII.LF);
                  end if;
               end loop;
            end if;
         when Unavailable =>
            Append
              (Buf,
               "   [Unavailable] " &
               To_String (Pres.Actual.Unavailable_Message) & ASCII.LF);
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
                     "   - Scheduled: " & To_String (Item.Scheduled_Date_Text) &
                     "  [" & To_String (Item.Status_Text) & "] " &
                     To_String (Item.Plan_Id) & ASCII.LF);
                  Append
                    (Buf,
                     "       " & To_String (Item.Description) & ASCII.LF);
                  if Length (Item.Postings_Text) > 0 then
                     Append (Buf, To_String (Item.Postings_Text) & ASCII.LF);
                  end if;
               end loop;
            end if;
         when Unavailable =>
            Append
              (Buf,
               "   [Unavailable] " &
               To_String (Pres.Plan.Unavailable_Message) & ASCII.LF);
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
         when Unavailable =>
            Append
              (Buf,
               "   [Unavailable] " &
               To_String (Pres.Issue.Unavailable_Message) & ASCII.LF);
      end case;
      Append (Buf, ASCII.LF);

      --  Cycle Section
      Append (Buf, " Cycle:" & ASCII.LF);
      case Pres.Cycle.Status is
         when Available =>
            Append
              (Buf,
               "   Previous Window: " &
               To_String (Pres.Cycle.Previous_Window_Text) & ASCII.LF);
            Append
              (Buf,
               "   Current Window : " &
               To_String (Pres.Cycle.Current_Window_Text) & ASCII.LF);
            Append
              (Buf,
               "   Role on Focus  : " &
               To_String (Pres.Cycle.Focus_Cycle_Role) & ASCII.LF);
         when Unavailable =>
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

end HRA.Household_Home_Text;
