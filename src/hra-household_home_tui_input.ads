with HRA.Household_Home_Interaction;

--  Thin terminal-input mapping boundary for Household Home TUI.
--  Owns terminal key interpretation only. It does not perform date arithmetic,
--  mutate Home coordinates, read the clock, or observe Household state.
package HRA.Household_Home_TUI_Input is

   type Input_Action_Kind is
     (Navigate,
      Quit,
      Redraw,
      Ignored);

   type Input_Action (Kind : Input_Action_Kind := Ignored) is record
      case Kind is
         when Navigate =>
            Intent : HRA.Household_Home_Interaction.Home_Intent;
         when Quit | Redraw | Ignored =>
            null;
      end case;
   end record;

   --  Map one terminal key code to a UI-neutral Home intent or shell action.
   --  The Integer boundary keeps curses-specific key representation out of the
   --  public type while the body owns the exact ncurses constants.
   function Decode_Key (Key : Integer) return Input_Action;

end HRA.Household_Home_TUI_Input;
