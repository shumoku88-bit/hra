with Ada.Strings.Unbounded;
with HRA.Dates;
with HRA.Household;

--  Application command boundary for Household Home overview.
--  Coordinates pure option parsing (Stage A), temporal default resolution (Stage B),
--  and pure pipeline execution:
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

   type Parse_Status is
     (Success,
      Missing_Option_Value,
      Duplicate_Option,
      Unknown_Option,
      Invalid_Through_Date,
      Invalid_Day_Date);

   --  Stage A: Pure parsed CLI arguments without temporal default resolution
   type Parsed_Home_Arguments is record
      Base_Directory : Ada.Strings.Unbounded.Unbounded_String;
      Has_Base       : Boolean := False;
      Has_Through    : Boolean := False;
      Through_Date   : HRA.Dates.Date;
      Has_Day        : Boolean := False;
      Day_Date       : HRA.Dates.Date;
   end record;

   type Parse_Resolution is record
      Status  : Parse_Status := Success;
      Parsed  : Parsed_Home_Arguments;
      Message : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Array of argument strings for pure CLI option parsing
   type String_Array is array (Positive range <>) of Ada.Strings.Unbounded.Unbounded_String;

   --  Stage A: Pure argv parsing without reading system clock or resolving defaults.
   --  Supported options (order-independent):
   --    --base <path>
   --    --through <YYYY-MM-DD>
   --    --day <YYYY-MM-DD>
   --  Fails closed on:
   --    - Unknown options
   --    - Missing option values (at argv end or followed by another option token)
   --    - Duplicate options (--base, --through, --day)
   --    - Invalid Gregorian dates for --through or --day
   function Parse_Arguments (Args : String_Array) return Parse_Resolution;

   --  Check whether resolving temporal defaults requires reading the system clock.
   --  Returns True if and only if --through was omitted (Has_Through is False).
   --  If explicit --through was provided, system clock is NEVER needed (returns False).
   function Needs_Clock (Parsed : Parsed_Home_Arguments) return Boolean;

   --  Stage B: Resolve temporal defaults when Today is provided / required.
   --  Temporal law:
   --    if explicit Through: Observed_Through := explicit Through else Today
   --    if explicit Day:     Selected_Day     := explicit Day     else Observed_Through
   function Resolve_Home_Options
     (Parsed : Parsed_Home_Arguments;
      Today  : HRA.Dates.Date) return Home_Options;

   --  Stage B: Resolve temporal defaults when explicit --through was provided.
   --  Does NOT take or require any Today date (clock is never read).
   --  Precondition: Parsed.Has_Through = True.
   function Resolve_Home_Options
     (Parsed : Parsed_Home_Arguments) return Home_Options;

   --  Pure execution pipeline on already-admitted Household_State:
   --  1. Household_Home_Observation.Observe (Observed_Through, Selected_Day, State)
   --  2. Household_Home_Presentation.Present (Obs)
   --  3. Household_Home_Text.Render_Home (Pres, State.Report_Policy.Presentation.Calendar)
   function Execute_Home
     (State            : HRA.Household.Household_State;
      Observed_Through : HRA.Dates.Date;
      Selected_Day     : HRA.Dates.Date) return String;

end HRA.Household_Home_Command;
