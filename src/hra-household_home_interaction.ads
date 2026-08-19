with HRA.Dates;
use type HRA.Dates.Date;

--  Pure UI-neutral interaction semantics for Household Home navigation.
--  Maps user navigation intents to pure coordinate transitions over:
--    Observed_Through : fixed knowledge / observation horizon
--    Selected_Day     : mutable focus coordinate
--
--  Temporal navigation laws:
--    1. Navigation NEVER alters Observed_Through (knowledge horizon is invariant).
--    2. Navigation ONLY changes Selected_Day (presentation focus coordinate).
--    3. Selected_Day may freely move before, on, or beyond Observed_Through.
--    4. Boundary transitions fail closed without wraparound, sentinels, or exceptions.
--    5. No system clock, no file I/O, no UI glyph/key/terminal coupling.
package HRA.Household_Home_Interaction
  with Pure, SPARK_Mode => On
is

   --  ========================================================================
   --  Home Focus Coordinates
   --  ========================================================================

   type Home_Coordinates is record
      Observed_Through : HRA.Dates.Date;
      Selected_Day     : HRA.Dates.Date;
   end record;

   --  Construct focus coordinates with initial focus matching the observation horizon.
   function Make_Coordinates
     (Observed_Through : HRA.Dates.Date) return Home_Coordinates
     with Post =>
       Make_Coordinates'Result.Observed_Through = Observed_Through
       and then Make_Coordinates'Result.Selected_Day = Observed_Through;

   --  Construct focus coordinates with explicit observation horizon and selected day.
   function Make_Coordinates
     (Observed_Through : HRA.Dates.Date;
      Selected_Day     : HRA.Dates.Date) return Home_Coordinates
     with Post =>
       Make_Coordinates'Result.Observed_Through = Observed_Through
       and then Make_Coordinates'Result.Selected_Day = Selected_Day;

   --  ========================================================================
   --  Navigation Intents
   --  ========================================================================

   type Home_Intent_Kind is
     (Select_Day,
      Previous_Day,
      Next_Day,
      Previous_Week,
      Next_Week,
      Focus_Observed_Through);

   type Home_Intent (Kind : Home_Intent_Kind := Focus_Observed_Through) is record
      case Kind is
         when Select_Day =>
            Target_Day : HRA.Dates.Date;
         when Previous_Day
            | Next_Day
            | Previous_Week
            | Next_Week
            | Focus_Observed_Through =>
            null;
      end case;
   end record;

   --  Intent constructors for UI event mappers
   function Intent_Select_Day (Day : HRA.Dates.Date) return Home_Intent is
     ((Kind => Select_Day, Target_Day => Day));

   function Intent_Previous_Day return Home_Intent is
     ((Kind => Previous_Day));

   function Intent_Next_Day return Home_Intent is
     ((Kind => Next_Day));

   function Intent_Previous_Week return Home_Intent is
     ((Kind => Previous_Week));

   function Intent_Next_Week return Home_Intent is
     ((Kind => Next_Week));

   function Intent_Focus_Observed_Through return Home_Intent is
     ((Kind => Focus_Observed_Through));

   --  ========================================================================
   --  Transition Status and Result
   --  ========================================================================

   type Transition_Status is
     (Applied,
      Lower_Bound_Exceeded,
      Upper_Bound_Exceeded);

   type Transition_Result is record
      Status      : Transition_Status := Applied;
      Coordinates : Home_Coordinates;
   end record;

   function Is_Applied (Result : Transition_Result) return Boolean is
     (Result.Status = Applied);

   --  ========================================================================
   --  Direct Navigation Transitions
   --  ========================================================================

   --  Directly set focus to specified day. Always succeeds.
   function Select_Day
     (Coordinates : Home_Coordinates;
      Day         : HRA.Dates.Date) return Transition_Result
     with Post =>
       Select_Day'Result.Coordinates.Observed_Through = Coordinates.Observed_Through
       and then Select_Day'Result.Coordinates.Selected_Day = Day
       and then Select_Day'Result.Status = Applied;

   --  Move focus 1 day backward (-1 day).
   --  Fails closed with Lower_Bound_Exceeded if Selected_Day is 0001-01-01.
   function Previous_Day
     (Coordinates : Home_Coordinates) return Transition_Result
     with Post =>
       Previous_Day'Result.Coordinates.Observed_Through = Coordinates.Observed_Through
       and then Previous_Day'Result.Status in Applied | Lower_Bound_Exceeded
       and then (if Previous_Day'Result.Status = Lower_Bound_Exceeded
                 then Previous_Day'Result.Coordinates.Selected_Day = Coordinates.Selected_Day);

   --  Move focus 1 day forward (+1 day).
   --  Fails closed with Upper_Bound_Exceeded if Selected_Day is 9999-12-31.
   function Next_Day
     (Coordinates : Home_Coordinates) return Transition_Result
     with Post =>
       Next_Day'Result.Coordinates.Observed_Through = Coordinates.Observed_Through
       and then Next_Day'Result.Status in Applied | Upper_Bound_Exceeded
       and then (if Next_Day'Result.Status = Upper_Bound_Exceeded
                 then Next_Day'Result.Coordinates.Selected_Day = Coordinates.Selected_Day);

   --  Move focus 1 week (7 days) backward (-7 days).
   --  Fails closed with Lower_Bound_Exceeded if stepping 7 days reaches before 0001-01-01.
   function Previous_Week
     (Coordinates : Home_Coordinates) return Transition_Result
     with Post =>
       Previous_Week'Result.Coordinates.Observed_Through = Coordinates.Observed_Through
       and then Previous_Week'Result.Status in Applied | Lower_Bound_Exceeded
       and then (if Previous_Week'Result.Status = Lower_Bound_Exceeded
                 then Previous_Week'Result.Coordinates.Selected_Day = Coordinates.Selected_Day);

   --  Move focus 1 week (7 days) forward (+7 days).
   --  Fails closed with Upper_Bound_Exceeded if stepping 7 days reaches after 9999-12-31.
   function Next_Week
     (Coordinates : Home_Coordinates) return Transition_Result
     with Post =>
       Next_Week'Result.Coordinates.Observed_Through = Coordinates.Observed_Through
       and then Next_Week'Result.Status in Applied | Upper_Bound_Exceeded
       and then (if Next_Week'Result.Status = Upper_Bound_Exceeded
                 then Next_Week'Result.Coordinates.Selected_Day = Coordinates.Selected_Day);

   --  Reset focus to Observed_Through. Always succeeds.
   function Focus_Observed_Through
     (Coordinates : Home_Coordinates) return Transition_Result
     with Post =>
       Focus_Observed_Through'Result.Coordinates.Observed_Through = Coordinates.Observed_Through
       and then Focus_Observed_Through'Result.Coordinates.Selected_Day = Coordinates.Observed_Through
       and then Focus_Observed_Through'Result.Status = Applied;

   --  ========================================================================
   --  Intent Dispatch
   --  ========================================================================

   --  Apply high-level navigation intent to focus coordinates.
   function Apply_Intent
     (Coordinates : Home_Coordinates;
      Intent      : Home_Intent) return Transition_Result
     with Post =>
       Apply_Intent'Result.Coordinates.Observed_Through = Coordinates.Observed_Through
       and then (if Apply_Intent'Result.Status /= Applied
                 then Apply_Intent'Result.Coordinates.Selected_Day = Coordinates.Selected_Day);

end HRA.Household_Home_Interaction;
