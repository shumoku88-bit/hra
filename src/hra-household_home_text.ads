with HRA.Household_Home_Presentation;

--  Terminal and CLI text rendering for Household Home presentation model.
--  This package depends exclusively on HRA.Household_Home_Presentation.
--  It does NOT import Household_State, Canonical_Source, or Home_Observation.
package HRA.Household_Home_Text is

   --  Format a single calendar cell to exact 5-column fixed width.
   --  Guarantees String'Length = 5 for all combinations of digit length,
   --  selection state, and attention markers.
   function Format_Cell
     (Cell : HRA.Household_Home_Presentation.Calendar_Cell) return String;

   --  Render monthly calendar grid with weekday headers aligned to 5-col cells.
   function Render_Calendar_Grid
     (Grid : HRA.Household_Home_Presentation.Calendar_Grid) return String;

   --  Render complete Household Home presentation view into human-readable text.
   function Render_Home
     (Pres : HRA.Household_Home_Presentation.Home_Presentation) return String;

end HRA.Household_Home_Text;
