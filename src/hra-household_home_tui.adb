with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA.Actual_Admission;
with HRA.Actual_Id_Selection;
with HRA.Household_Actual_Record;
with HRA.Household_Actual_Record_TUI;
with HRA.Household_Home_Command;
with HRA.Household_Home_Interaction;
with HRA.Household_Home_Observation;
with HRA.Household_Home_TUI_Input;
with HRA.Terminal_UTF8;
with Terminal_Interface.Curses;

package body HRA.Household_Home_TUI is

   package Command renames HRA.Household_Home_Command;
   package Interaction renames HRA.Household_Home_Interaction;
   package Input renames HRA.Household_Home_TUI_Input;
   package Curses renames Terminal_Interface.Curses;
   package Record_TUI renames HRA.Household_Actual_Record_TUI;
   use type HRA.Dates.Date;

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
            Text        => "[h/l] day  [k/j] week  [g] known  [r] record  [q] quit");
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
              "unable to reload canonical Household after Actual mutation attempt: " &
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
                  Actual_ID : HRA.Actual_Admission.Actual_Id;
                  ID_Status : HRA.Actual_Id_Selection.Selection_Status;
                  Record_Diag : HRA.Household_Actual_Record.Record_Diagnostic;
               begin
                  if not HRA.Actual_Id_Selection.Select_Next
                    (Current_State.Actual_Identity, Actual_ID, ID_Status)
                  then
                     Notice := To_Unbounded_String
                       ("Record identity unavailable: " &
                        HRA.Actual_Id_Selection.Selection_Status'Image (ID_Status));
                  elsif HRA.Household_Actual_Record.Record_Actual
                    (Current_State, Edited.Tx, Actual_ID, Record_Diag)
                  then
                     Reload_Household;
                     Notice := To_Unbounded_String ("Recorded Actual.");
                  else
                     --  Publication can fail because the source premise became
                     --  stale. Never continue with the pre-attempt Household;
                     --  reload canonical authority before another mutation.
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
