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
   use type HRA.Dates.Date;

   procedure Draw
     (State       : HRA.Household.Household_State;
      Horizon     : HRA.Household_Home_Observation.Home_Horizon_Observation;
      Coordinates : Interaction.Home_Coordinates)
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
      Position : Natural := Text'First;
      Row      : Natural := 0;
   begin
      Curses.Clear;

      while Position <= Text'Last and then Row < Max_Rows loop
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

      Curses.Refresh;
   end Draw;

   procedure Run
     (State            : HRA.Household.Household_State;
      Observed_Through : HRA.Dates.Date;
      Selected_Day     : HRA.Dates.Date)
   is
      Coordinates : Interaction.Home_Coordinates :=
        Interaction.Make_Coordinates (Observed_Through, Selected_Day);
      Horizon : HRA.Household_Home_Observation.Home_Horizon_Observation :=
        HRA.Household_Home_Observation.Observe_Horizon
          (Coordinates.Observed_Through, State);
      Running        : Boolean := True;
      Screen_Started : Boolean := False;
   begin
      HRA.Terminal_UTF8.Initialize;
      Curses.Init_Screen;
      Screen_Started := True;
      Curses.Set_Cbreak_Mode (True);
      Curses.Set_Echo_Mode (False);
      Curses.Set_KeyPad_Mode (Curses.Standard_Window, True);

      Draw (State, Horizon, Coordinates);

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
                           if Result.Coordinates.Observed_Through /= Coordinates.Observed_Through then
                              Horizon :=
                                HRA.Household_Home_Observation.Observe_Horizon
                                  (Result.Coordinates.Observed_Through, State);
                           end if;
                           Coordinates := Result.Coordinates;
                           Draw (State, Horizon, Coordinates);
                        when Interaction.Lower_Bound_Exceeded
                           | Interaction.Upper_Bound_Exceeded =>
                           null;
                     end case;
                  end;

               when Input.Quit =>
                  Running := False;

               when Input.Redraw =>
                  Draw (State, Horizon, Coordinates);

               when Input.Ignored =>
                  null;
            end case;
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
