with HRA.Household_Home_Presentation;
with HRA.Report_Config;

--  Terminal and CLI text rendering for Household Home presentation model.
--  This package depends exclusively on HRA.Household_Home_Presentation.
--  It does NOT import Household_State, Canonical_Source, or Home_Observation.
package HRA.Household_Home_Text is

   --  Resolve attention summary facts into a single character marker using
   --  configured marker glyphs:
   --    - 2+ Present: Markers.Multiple (default '+')
   --    - Exactly 1 Present:
   --        Plan_Scheduled = Present => Markers.Plan_Due (default '$')
   --        Issue_Due = Present      => Markers.Issue_Due (default '!')
   --        Cycle_End = Present      => Markers.Cycle_End (default '|')
   --    - 0 Present (Absent / Unavailable): ' '
   function Resolve_Marker
     (Attention : HRA.Household_Home_Presentation.Attention_Summary;
      Markers   : HRA.Report_Config.Calendar_Markers :=
        (Cycle_End => '|', Plan_Due => '$', Issue_Due => '!', Multiple => '+'))
      return Character;

   --  Format a single calendar cell to exact 5-column fixed width.
   --  Guarantees String'Length = 5 for all combinations of digit length,
   --  selection state, attention markers, and out-of-range padding.
   function Format_Cell
     (Cell    : HRA.Household_Home_Presentation.Calendar_Cell;
      Markers : HRA.Report_Config.Calendar_Markers :=
        (Cycle_End => '|', Plan_Due => '$', Issue_Due => '!', Multiple => '+'))
      return String;

   --  Render monthly calendar grid with weekday headers aligned to 5-col cells.
   function Render_Calendar_Grid
     (Grid    : HRA.Household_Home_Presentation.Calendar_Grid;
      Markers : HRA.Report_Config.Calendar_Markers :=
        (Cycle_End => '|', Plan_Due => '$', Issue_Due => '!', Multiple => '+'))
      return String;

   --  Render complete Household Home presentation view into human-readable text.
   function Render_Home
     (Pres    : HRA.Household_Home_Presentation.Home_Presentation;
      Markers : HRA.Report_Config.Calendar_Markers :=
        (Cycle_End => '|', Plan_Due => '$', Issue_Due => '!', Multiple => '+'))
      return String;

end HRA.Household_Home_Text;
