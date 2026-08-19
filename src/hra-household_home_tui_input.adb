with HRA.Household_Home_Interaction;
with Terminal_Interface.Curses;

package body HRA.Household_Home_TUI_Input is

   package Curses renames Terminal_Interface.Curses;
   package Interaction renames HRA.Household_Home_Interaction;

   Ctrl_L : constant Integer := 12;

   function Decode_Key (Key : Integer) return Input_Action is
   begin
      if Key = Character'Pos ('h') or else Key = Integer (Curses.KEY_LEFT) then
         return
           (Kind   => Navigate,
            Intent => Interaction.Intent_Previous_Day);
      elsif Key = Character'Pos ('l') or else Key = Integer (Curses.KEY_RIGHT) then
         return
           (Kind   => Navigate,
            Intent => Interaction.Intent_Next_Day);
      elsif Key = Character'Pos ('k') or else Key = Integer (Curses.KEY_UP) then
         return
           (Kind   => Navigate,
            Intent => Interaction.Intent_Previous_Week);
      elsif Key = Character'Pos ('j') or else Key = Integer (Curses.KEY_DOWN) then
         return
           (Kind   => Navigate,
            Intent => Interaction.Intent_Next_Week);
      elsif Key = Character'Pos ('g') or else Key = Character'Pos ('G') then
         return
           (Kind   => Navigate,
            Intent => Interaction.Intent_Focus_Observed_Through);
      elsif Key = Character'Pos ('q') or else Key = Character'Pos ('Q') then
         return (Kind => Quit);
      elsif Key = Ctrl_L or else Key = Integer (Curses.Key_Resize) then
         return (Kind => Redraw);
      else
         return (Kind => Ignored);
      end if;
   end Decode_Key;

end HRA.Household_Home_TUI_Input;
