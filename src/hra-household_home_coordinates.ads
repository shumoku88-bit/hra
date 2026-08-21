with HRA.Dates;
with HRA.Household;
with HRA.Household_Home_Observation;

--  Local temporal coordinates for Household Home.
--
--  Visible_Through is Home's current as-of horizon. Existing observers compare
--  Actual and lifecycle evidence dates with this coordinate when deciding what
--  is already visible. It is not a ceiling on target dates: an admitted Plan or
--  Issue may point beyond it.
--
--  Visible_Through is deliberately NOT named as a canonical knowledge time:
--  HRA does not yet retain a separate "when this fact became known" coordinate
--  for admitted facts.
--
--  Focus_Day is where Home looks. It may lie before, at, or after
--  Visible_Through. A focus beyond the visible horizon does not manufacture a
--  future Actual fact; the existing Home observation laws remain authoritative.
--
--  This package is intentionally local to Home. It does not introduce a shared
--  Time_Coordinate abstraction for the rest of HRA.
package HRA.Household_Home_Coordinates is

   type Coordinates is private;

   function Place
     (Visible_Through : HRA.Dates.Date;
      Focus_Day       : HRA.Dates.Date) return Coordinates;

   function Visible_Through
     (Position : Coordinates) return HRA.Dates.Date;

   function Focus_Day
     (Position : Coordinates) return HRA.Dates.Date;

   --  Project one already-admitted Household from this explicit Home position.
   --  This delegates semantics to Household_Home_Observation; it owns only the
   --  distinction between the visibility and focus coordinates.
   function See
     (Position : Coordinates;
      State    : HRA.Household.Household_State)
      return HRA.Household_Home_Observation.Home_Observation;

private

   type Coordinates is record
      Through_Date : HRA.Dates.Date;
      Focus_Date   : HRA.Dates.Date;
   end record;

end HRA.Household_Home_Coordinates;
