with HRA.Dates;
with HRA.Household;

--  Interactive terminal shell for the already-defined Household Home semantics.
--  The public boundary carries only admitted Household state and temporal
--  coordinates. Curses, key codes, rendering mechanics, clock access, and file
--  I/O are kept out of the specification.
package HRA.Household_Home_TUI is

   procedure Run
     (State            : HRA.Household.Household_State;
      Observed_Through : HRA.Dates.Date;
      Selected_Day     : HRA.Dates.Date);

end HRA.Household_Home_TUI;
