with Ada.Strings.Unbounded;
with HRA.Dates;
with HRA.Household;
with HRA.Report_Config;

--  Application command boundary for Household Home overview.
--  Coordinates option resolution, date defaulting according to the temporal
--  law, and pipeline execution:
--    Household_Home_Observation.Observe
--    -> Household_Home_Presentation.Present
--    -> Household_Home_Text.Render_Home
--
--  This package does NOT read the system clock and does NOT perform file I/O.
package HRA.Household_Home_Command is

   type Date_Option_Source is (Defaulted, Explicit);

   type Home_Options is record
      Base_Directory   : Ada.Strings.Unbounded.Unbounded_String;
      Observed_Through : HRA.Dates.Date;
      Through_Source   : Date_Option_Source := Defaulted;
      Selected_Day     : HRA.Dates.Date;
      Day_Source       : Date_Option_Source := Defaulted;
   end record;

   type Resolve_Status is
     (Success,
      Missing_Option_Value,
      Unknown_Option,
      Invalid_Through_Date,
      Invalid_Day_Date);

   type Command_Resolution is record
      Status  : Resolve_Status;
      Options : Home_Options;
      Message : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Pure temporal law date resolution:
   --  - If Through_Text non-empty: parse as Gregorian date. If invalid -> Invalid_Through_Date.
   --  - If Through_Text empty: use Today.
   --  - If Day_Text non-empty: parse as Gregorian date. If invalid -> Invalid_Day_Date.
   --  - If Day_Text empty: use resolved Observed_Through (whether explicit or defaulted).
   function Resolve_Dates
     (Through_Text : String;
      Day_Text     : String;
      Today        : HRA.Dates.Date) return Command_Resolution;

   --  Array of argument strings for pure CLI option parsing
   type String_Array is array (Positive range <>) of Ada.Strings.Unbounded.Unbounded_String;

   --  Parse CLI arguments for `home` command:
   --  Supported options (order-independent):
   --    --base <path>
   --    --through <YYYY-MM-DD>
   --    --day <YYYY-MM-DD>
   --  Fails closed on missing option values or unknown options.
   function Parse_Arguments
     (Args  : String_Array;
      Today : HRA.Dates.Date) return Command_Resolution;

   --  Pure execution pipeline on already-admitted Household_State:
   --  1. Household_Home_Observation.Observe (Observed_Through, Selected_Day, State)
   --  2. Household_Home_Presentation.Present (Obs)
   --  3. Household_Home_Text.Render_Home (Pres, State.Report_Configuration.Presentation.Calendar)
   function Execute_Home
     (State            : HRA.Household.Household_State;
      Observed_Through : HRA.Dates.Date;
      Selected_Day     : HRA.Dates.Date) return String;

end HRA.Household_Home_Command;
