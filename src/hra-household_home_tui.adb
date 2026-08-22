with Ada.Strings;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA.Actual_Admission;
with HRA.Dates;
with HRA.Household_Actual_Record;
with HRA.Household_Actual_Record_TUI;
with HRA.Household_Home_Command;
with HRA.Household_Home_Interaction;
with HRA.Household_Home_Observation;
with HRA.Household_Home_TUI_Input;
with HRA.Household_Plan_Record;
with HRA.Issue_Close;
with HRA.Issue_Closure_Preparation;
with HRA.Issue_Closure_Preparation.Publication;
with HRA.Issue_Realization_Resume;
with HRA.Issue_Realization_Resume.Publication;
with HRA.Issue_Relation;
with HRA.Issue_Relation.Sidecar;
with HRA.Issues;
with HRA.Plan;
with HRA.Terminal_UTF8;
with Terminal_Interface.Curses;

package body HRA.Household_Home_TUI is

   package Command renames HRA.Household_Home_Command;
   package Interaction renames HRA.Household_Home_Interaction;
   package Input renames HRA.Household_Home_TUI_Input;
   package Curses renames Terminal_Interface.Curses;
   package Record_TUI renames HRA.Household_Actual_Record_TUI;
   use type HRA.Dates.Date;
   use type HRA.Household_Plan_Record.Record_Status;

   procedure Draw
     (State       : HRA.Household.Household_State;
      Horizon     : HRA.Household_Home_Observation.Home_Horizon_Observation;
      Coordinates : Interaction.Home_Coordinates;
      Notice      : String := "")
   is
      Text : constant String :=
        Command.Execute_Home
          (State,
           Horizon,
           Coordinates.Selected_Day);
      Max_Rows : constant Natural := Natural (Curses.Lines);
      Max_Columns : constant Natural := Natural (Curses.Columns);
      Writable_Columns : constant Natural :=
        (if Max_Columns > 1 then Max_Columns - 1 else 0);
      Reserved_Rows : constant Natural :=
        (if Notice'Length > 0 then 2 else 1);
      Content_Rows : constant Natural :=
        (if Max_Rows > Reserved_Rows then Max_Rows - Reserved_Rows else 0);
      Position : Natural := Text'First;
      Row      : Natural := 0;
   begin
      Curses.Clear;

      while Position <= Text'Last and then Row < Content_Rows loop
         declare
            Line_End : Natural := Position;
         begin
            while Line_End <= Text'Last
              and then Text (Line_End) /= ASCII.LF
            loop
               Line_End := Line_End + 1;
            end loop;

            if Line_End > Position and then Writable_Columns > 0 then
               HRA.Terminal_UTF8.Add_Line
                 (Line        => Row,
                  Column      => 0,
                  Max_Columns => Writable_Columns,
                  Text        => Text (Position .. Line_End - 1));
            end if;

            Row := Row + 1;
            Position := Line_End + 1;
         end;
      end loop;

      if Writable_Columns > 0 and then Max_Rows > 0 then
         if Notice'Length > 0 and then Max_Rows >= 2 then
            HRA.Terminal_UTF8.Add_Line
              (Line        => Max_Rows - 2,
               Column      => 0,
               Max_Columns => Writable_Columns,
               Text        => Notice);
         end if;
         HRA.Terminal_UTF8.Add_Line
           (Line        => Max_Rows - 1,
            Column      => 0,
            Max_Columns => Writable_Columns,
            Text        =>
              "[h/l] day  [k/j] week  [g] known  [r] actual  [p] plan  [i] issue  [q] quit");
      end if;

      Curses.Refresh;
   end Draw;

   procedure Run
     (State         : HRA.Household.Household_State;
      Known_Through : HRA.Dates.Date;
      Selected_Day  : HRA.Dates.Date)
   is
      Current_State : HRA.Household.Household_State := State;
      Coordinates : Interaction.Home_Coordinates :=
        Interaction.Make_Coordinates (Known_Through, Selected_Day);
      Horizon : HRA.Household_Home_Observation.Home_Horizon_Observation :=
        HRA.Household_Home_Observation.See_Horizon
          (Coordinates.Known_Through, Current_State);
      Notice         : Unbounded_String := Null_Unbounded_String;
      Running        : Boolean := True;
      Screen_Started : Boolean := False;

      procedure Reload_Household is
         Fresh : HRA.Household.Household_State;
         Error : Unbounded_String;
      begin
         if not HRA.Household.Load_Canonical_Household
           (To_String (Current_State.Root_Path), Fresh, Error)
         then
            raise Program_Error with
              "unable to reload canonical Household after mutation attempt: " &
              To_String (Error);
         end if;
         Current_State := Fresh;
         Horizon :=
           HRA.Household_Home_Observation.See_Horizon
             (Coordinates.Known_Through, Current_State);
      end Reload_Household;

      procedure Record_Selected_Day is
         Edited : constant Record_TUI.Edit_Result :=
           Record_TUI.Edit (Current_State, Coordinates.Selected_Day);
      begin
         case Edited.Kind is
            when Record_TUI.Cancelled =>
               Notice := To_Unbounded_String ("Record cancelled.");

            when Record_TUI.Accepted =>
               declare
                  Record_Diag : HRA.Household_Actual_Record.Record_Diagnostic;
               begin
                  if HRA.Household_Actual_Record.Record_Ordinary
                    (Current_State, Edited.Tx, Record_Diag)
                  then
                     Reload_Household;
                     Notice := To_Unbounded_String ("Recorded Actual.");
                  else
                     Reload_Household;
                     Notice := To_Unbounded_String
                       (if Length (Record_Diag.Message) > 0
                        then "Record rejected: " & To_String (Record_Diag.Message)
                        else "Record rejected: " &
                          HRA.Household_Actual_Record.Record_Status'Image
                            (Record_Diag.Status));
                  end if;
               end;
         end case;
      end Record_Selected_Day;

      function Prompt_Line
        (Label : String;
         Value : out Unbounded_String) return Boolean
      is
         Buffer : String (1 .. 128) := (others => ' ');
         Max_Columns : constant Natural := Natural (Curses.Columns);
         Writable_Columns : constant Natural :=
           (if Max_Columns > 1 then Max_Columns - 1 else 0);
      begin
         Value := Null_Unbounded_String;
         Curses.Clear;
         if Writable_Columns > 0 then
            HRA.Terminal_UTF8.Add_Line
              (Line        => 0,
               Column      => 0,
               Max_Columns => Writable_Columns,
               Text        => Label);
         end if;
         Curses.Move_Cursor (Line => 1, Column => 0);
         Curses.Refresh;
         Curses.Set_Echo_Mode (True);
         begin
            Curses.Get (Str => Buffer, Len => Buffer'Length);
         exception
            when others =>
               Curses.Set_Echo_Mode (False);
               raise;
         end;
         Curses.Set_Echo_Mode (False);

         declare
            Text : constant String :=
              Ada.Strings.Fixed.Trim (Buffer, Ada.Strings.Right);
         begin
            if Text'Length = 0 then
               return False;
            end if;
            Value := To_Unbounded_String (Text);
            return True;
         end;
      end Prompt_Line;

      function Prompt_Selected_Date
        (Label : String;
         Value : out HRA.Dates.Date) return Boolean
      is
         Text   : Unbounded_String;
         Status : HRA.Dates.Date_Status;
      begin
         if not Prompt_Line
           (Label & " [.] selected " & HRA.Dates.Image (Coordinates.Selected_Day) &
            " or YYYY-MM-DD (blank cancels):",
            Text)
         then
            return False;
         end if;

         if To_String (Text) = "." then
            Value := Coordinates.Selected_Day;
            return True;
         end if;

         if not HRA.Dates.Parse (To_String (Text), Value, Status) then
            Notice := To_Unbounded_String
              ("Date rejected: " & HRA.Dates.Date_Status'Image (Status));
            return False;
         end if;
         return True;
      end Prompt_Selected_Date;

      function Prompt_Plan_Id (Plan_ID : out HRA.Plan.Plan_Id) return Boolean is
         Value  : Unbounded_String;
         Status : HRA.Plan.Plan_Id_Status;
      begin
         if not Prompt_Line ("Plan ID (blank cancels):", Value) then
            Notice := To_Unbounded_String ("Plan cancelled.");
            return False;
         end if;

         if not HRA.Plan.Create_Plan_Id (To_String (Value), Plan_ID, Status) then
            Notice := To_Unbounded_String
              ("Plan ID rejected: " & HRA.Plan.Plan_Id_Status'Image (Status));
            return False;
         end if;
         return True;
      end Prompt_Plan_Id;

      procedure Plan_Selected_Day is
         Plan_ID : HRA.Plan.Plan_Id;
      begin
         if not Prompt_Plan_Id (Plan_ID) then
            return;
         end if;

         declare
            Edited : constant Record_TUI.Edit_Result :=
              Record_TUI.Edit (Current_State, Coordinates.Selected_Day);
         begin
            case Edited.Kind is
               when Record_TUI.Cancelled =>
                  Notice := To_Unbounded_String ("Plan cancelled.");

               when Record_TUI.Accepted =>
                  declare
                     Plan_Diag : HRA.Household_Plan_Record.Record_Diagnostic;
                     Recorded  : constant Boolean :=
                       HRA.Household_Plan_Record.Record_Pending
                         (Current_State, Plan_ID, Edited.Tx, Plan_Diag);
                  begin
                     Reload_Household;
                     if Recorded then
                        if Plan_Diag.Status = HRA.Household_Plan_Record.Already_Present then
                           Notice := To_Unbounded_String ("Plan already present.");
                        else
                           Notice := To_Unbounded_String ("Recorded Plan.");
                        end if;
                     else
                        Notice := To_Unbounded_String
                          (if Length (Plan_Diag.Message) > 0
                           then "Plan rejected: " & To_String (Plan_Diag.Message)
                           else "Plan rejected: " &
                             HRA.Household_Plan_Record.Record_Status'Image
                               (Plan_Diag.Status));
                     end if;
                  end;
            end case;
         end;
      end Plan_Selected_Day;

      function Prompt_Issue_Id
        (Issue_ID : out HRA.Issues.Issue_Id) return Boolean
      is
         Value  : Unbounded_String;
         Status : HRA.Issues.Issue_Id_Status;
      begin
         if not Prompt_Line ("Issue ID (blank cancels):", Value) then
            Notice := To_Unbounded_String ("Issue action cancelled.");
            return False;
         end if;

         if not HRA.Issues.Create_Issue_Id
           (To_String (Value), Issue_ID, Status)
         then
            Notice := To_Unbounded_String
              ("Issue ID rejected: " & HRA.Issues.Issue_Id_Status'Image (Status));
            return False;
         end if;
         return True;
      end Prompt_Issue_Id;

      function Prompt_Issue_Disposition
        (Disposition : out HRA.Issue_Close.Close_Disposition) return Boolean
      is
         Value : Unbounded_String;
      begin
         if not Prompt_Line
           ("Close as [r]esolved or [d]ropped (blank cancels):", Value)
         then
            Notice := To_Unbounded_String ("Issue close cancelled.");
            return False;
         end if;

         declare
            Choice : constant String := To_String (Value);
         begin
            if Choice = "r" or else Choice = "R"
              or else Choice = "resolved" or else Choice = "Resolved"
            then
               Disposition := HRA.Issue_Close.Resolve_Issue;
               return True;
            elsif Choice = "d" or else Choice = "D"
              or else Choice = "dropped" or else Choice = "Dropped"
            then
               Disposition := HRA.Issue_Close.Drop_Issue;
               return True;
            end if;
         end;

         Notice := To_Unbounded_String
           ("Issue close choice rejected; use resolved or dropped.");
         return False;
      end Prompt_Issue_Disposition;

      procedure Close_Issue (Issue_ID : HRA.Issues.Issue_Id) is
         Disposition : HRA.Issue_Close.Close_Disposition;
         Closed_On   : HRA.Dates.Date;
      begin
         if not Prompt_Issue_Disposition (Disposition)
           or else not Prompt_Selected_Date ("Closed on:", Closed_On)
         then
            Notice := To_Unbounded_String ("Issue close cancelled.");
            return;
         end if;

         declare
            Prepared : HRA.Issue_Closure_Preparation.Prepared_Closure;
            Prep_Diag : HRA.Issue_Closure_Preparation.Preparation_Diagnostic;
            Pub_Result :
              HRA.Issue_Closure_Preparation.Publication.Publication_Result;
         begin
            if not HRA.Issue_Closure_Preparation.Prepare
              (Current_State,
               Issue_ID,
               Disposition,
               Closed_On,
               Prepared,
               Prep_Diag)
            then
               Notice := To_Unbounded_String
                 (if Length (Prep_Diag.Message) > 0
                  then "Issue close rejected: " & To_String (Prep_Diag.Message)
                  else "Issue close rejected: " &
                    HRA.Issue_Closure_Preparation.Preparation_Status'Image
                      (Prep_Diag.Status));
               return;
            end if;

            if not HRA.Issue_Closure_Preparation.Publication.Publish
              (Prepared, Pub_Result)
            then
               Reload_Household;
               Notice := To_Unbounded_String
                 (if Length (Pub_Result.Message) > 0
                  then "Issue close rejected: " & To_String (Pub_Result.Message)
                  else "Issue close publication rejected.");
               return;
            end if;

            Reload_Household;
            Notice := To_Unbounded_String
              (if HRA.Issue_Closure_Preparation.Is_Already_Closed (Prepared)
               then "Issue already closed as requested."
               else "Issue closed.");
         end;
      end Close_Issue;

      function Prompt_Actual_Id
        (Actual_ID : out HRA.Actual_Admission.Actual_Id) return Boolean
      is
         Value  : Unbounded_String;
         Status : HRA.Actual_Admission.Actual_Id_Status;
      begin
         if not Prompt_Line
           ("Durable Actual ID (reuse exactly when resuming):", Value)
         then
            Notice := To_Unbounded_String ("Issue realization cancelled.");
            return False;
         end if;

         if not HRA.Actual_Admission.Create_Actual_Id
           (To_String (Value), Actual_ID, Status)
         then
            Notice := To_Unbounded_String
              ("Actual ID rejected: " &
               HRA.Actual_Admission.Actual_Id_Status'Image (Status));
            return False;
         end if;
         return True;
      end Prompt_Actual_Id;

      function Prompt_Relation_Id
        (Relation_ID : out HRA.Issue_Relation.Relation_Event_Id) return Boolean
      is
         Value  : Unbounded_String;
         Status : HRA.Issue_Relation.Relation_Event_Id_Status;
      begin
         if not Prompt_Line
           ("Durable relation ID (reuse exactly when resuming):", Value)
         then
            Notice := To_Unbounded_String ("Issue realization cancelled.");
            return False;
         end if;

         if not HRA.Issue_Relation.Create_Relation_Event_Id
           (To_String (Value), Relation_ID, Status)
         then
            Notice := To_Unbounded_String
              ("Relation ID rejected: " &
               HRA.Issue_Relation.Relation_Event_Id_Status'Image (Status));
            return False;
         end if;
         return True;
      end Prompt_Relation_Id;

      procedure Realize_Issue (Issue_ID : HRA.Issues.Issue_Id) is
         Edited : constant Record_TUI.Edit_Result :=
           Record_TUI.Edit (Current_State, Coordinates.Selected_Day);
      begin
         case Edited.Kind is
            when Record_TUI.Cancelled =>
               Notice := To_Unbounded_String ("Issue realization cancelled.");

            when Record_TUI.Accepted =>
               declare
                  Actual_ID       : HRA.Actual_Admission.Actual_Id;
                  Relation_ID     : HRA.Issue_Relation.Relation_Event_Id;
                  Relation_On     : HRA.Dates.Date;
                  Closed_On       : HRA.Dates.Date;
                  Details_Value   : Unbounded_String;
               begin
                  if not Prompt_Actual_Id (Actual_ID)
                    or else not Prompt_Relation_Id (Relation_ID)
                    or else not Prompt_Selected_Date ("Relation recorded on:", Relation_On)
                    or else not Prompt_Selected_Date ("Issue closed on:", Closed_On)
                    or else not Prompt_Line
                      ("Relation details ('-' for none; reuse exactly when resuming):",
                       Details_Value)
                  then
                     Notice := To_Unbounded_String ("Issue realization cancelled.");
                     return;
                  end if;

                  declare
                     Relation_Observation : HRA.Issue_Relation.Sidecar.Observation;
                     Observation_Diag :
                       HRA.Issue_Relation.Sidecar.Observation_Diagnostic;
                     Prepared : HRA.Issue_Realization_Resume.Prepared_Resume;
                     Resume_Diag : HRA.Issue_Realization_Resume.Resume_Diagnostic;
                     Pub_Result :
                       HRA.Issue_Realization_Resume.Publication.Publication_Result;
                     Details : constant String :=
                       (if To_String (Details_Value) = "-"
                        then ""
                        else To_String (Details_Value));
                  begin
                     if not HRA.Issue_Relation.Sidecar.Observe
                       (To_String (Current_State.Root_Path),
                        Relation_Observation,
                        Observation_Diag)
                     then
                        Notice := To_Unbounded_String
                          (if Length (Observation_Diag.Message) > 0
                           then "Issue relation observation failed: " &
                             To_String (Observation_Diag.Message)
                           else "Issue relation observation failed: " &
                             HRA.Issue_Relation.Sidecar.Observation_Status'Image
                               (Observation_Diag.Status));
                        return;
                     end if;

                     if not HRA.Issue_Realization_Resume.Prepare_Resume
                       (State                => Current_State,
                        Tx                   => Edited.Tx,
                        Issue_ID             => Issue_ID,
                        Actual_ID            => Actual_ID,
                        Relation_Event_ID    => Relation_ID,
                        Relation_Recorded_On => Relation_On,
                        Closed_On            => Closed_On,
                        Relation_Details     => Details,
                        Relation_Observation => Relation_Observation,
                        Prepared             => Prepared,
                        Diag                 => Resume_Diag)
                     then
                        Notice := To_Unbounded_String
                          (if Length (Resume_Diag.Message) > 0
                           then "Issue realization rejected: " &
                             To_String (Resume_Diag.Message)
                           else "Issue realization rejected: " &
                             HRA.Issue_Realization_Resume.Resume_Status'Image
                               (Resume_Diag.Status));
                        return;
                     end if;

                     if not HRA.Issue_Realization_Resume.Publication.Publish
                       (Prepared, Pub_Result)
                     then
                        Reload_Household;
                        Notice := To_Unbounded_String
                          ("Issue realization paused at " &
                           HRA.Issue_Realization_Resume.Publication.Confirmed_World'Image
                             (Pub_Result.Last_Confirmed) &
                           "; retry the same transaction, IDs, dates and details." &
                           (if Length (Pub_Result.Message) > 0
                            then " " & To_String (Pub_Result.Message)
                            else ""));
                        return;
                     end if;

                     Reload_Household;
                     Notice := To_Unbounded_String ("Issue realized as Actual.");
                  end;
               end;
         end case;
      end Realize_Issue;

      procedure Open_Issue_Action is
         Action_Value : Unbounded_String;
         Issue_ID     : HRA.Issues.Issue_Id;
      begin
         if not Prompt_Line
           ("Issue action: [c] close  [r] realize (blank cancels):",
            Action_Value)
         then
            Notice := To_Unbounded_String ("Issue action cancelled.");
            return;
         end if;

         if not Prompt_Issue_Id (Issue_ID) then
            return;
         end if;

         declare
            Choice : constant String := To_String (Action_Value);
         begin
            if Choice = "c" or else Choice = "C"
              or else Choice = "close" or else Choice = "Close"
            then
               Close_Issue (Issue_ID);
            elsif Choice = "r" or else Choice = "R"
              or else Choice = "realize" or else Choice = "Realize"
            then
               Realize_Issue (Issue_ID);
            else
               Notice := To_Unbounded_String
                 ("Issue action rejected; use close or realize.");
            end if;
         end;
      end Open_Issue_Action;

   begin
      HRA.Terminal_UTF8.Initialize;
      Curses.Init_Screen;
      Screen_Started := True;
      Curses.Set_Cbreak_Mode (True);
      Curses.Set_Echo_Mode (False);
      Curses.Set_KeyPad_Mode (Curses.Standard_Window, True);

      Draw (Current_State, Horizon, Coordinates, To_String (Notice));

      while Running loop
         declare
            Key : constant Curses.Real_Key_Code := Curses.Get_Keystroke;
            Action : constant Input.Input_Action := Input.Decode_Key (Integer (Key));
         begin
            case Action.Kind is
               when Input.Navigate =>
                  declare
                     Result : constant Interaction.Transition_Result :=
                       Interaction.Apply_Intent (Coordinates, Action.Intent);
                  begin
                     case Result.Status is
                        when Interaction.Applied =>
                           if Result.Coordinates.Known_Through /= Coordinates.Known_Through then
                              Horizon :=
                                HRA.Household_Home_Observation.See_Horizon
                                  (Result.Coordinates.Known_Through, Current_State);
                           end if;
                           Coordinates := Result.Coordinates;
                           Notice := Null_Unbounded_String;
                        when Interaction.Lower_Bound_Exceeded
                           | Interaction.Upper_Bound_Exceeded =>
                           null;
                     end case;
                  end;

               when Input.Open_Record =>
                  Record_Selected_Day;

               when Input.Open_Plan =>
                  Plan_Selected_Day;

               when Input.Open_Issue =>
                  Open_Issue_Action;

               when Input.Quit =>
                  Running := False;

               when Input.Redraw =>
                  null;

               when Input.Ignored =>
                  null;
            end case;

            if Running then
               Draw
                 (Current_State,
                  Horizon,
                  Coordinates,
                  To_String (Notice));
            end if;
         end;
      end loop;

      Curses.End_Windows;
      Screen_Started := False;
   exception
      when others =>
         if Screen_Started then
            begin
               Curses.End_Windows;
            exception
               when others =>
                  null;
            end;
         end if;
         raise;
   end Run;

end HRA.Household_Home_TUI;