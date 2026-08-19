with Ada.Containers.Vectors;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA.Dates;
with HRA.Household_Home_Observation;
with HRA.Report_Config;

--  Pure presentation mapping for Household Home observation.
--  Transforms semantic Home_Observation into UI/render-ready view models:
--    - Monthly calendar grid with attention markers
--    - Formatted Selected-Day details for Actual, Plan, Issue, and Cycle
--    - Pure text rendering for CLI / TUI previews
package HRA.Household_Home_Presentation is

   --  ========================================================================
   --  Attention Marker Resolution
   --  ========================================================================

   --  Resolve attention facts (Plan_Scheduled, Issue_Due, Cycle_End) into a
   --  single character marker using configured marker glyphs:
   --    - 2+ Present: Markers.Multiple (default '+')
   --    - Exactly 1 Present:
   --        Plan_Scheduled = Present => Markers.Plan_Due (default '$')
   --        Issue_Due = Present      => Markers.Issue_Due (default '!')
   --        Cycle_End = Present      => Markers.Cycle_End (default '|')
   --    - 0 Present (Absent / Unavailable): ' '
   function Resolve_Marker
     (Attention : HRA.Household_Home_Observation.Attention_Observation;
      Markers   : HRA.Report_Config.Calendar_Markers) return Character;

   --  ========================================================================
   --  Calendar Grid Model
   --  ========================================================================

   type Calendar_Cell is record
      Date_Value          : HRA.Dates.Date;
      Day_Number          : Positive range 1 .. 31;
      Is_Current_Month    : Boolean := False;
      Is_Selected         : Boolean := False;
      Is_Observed_Through : Boolean := False;
      Is_Future           : Boolean := False;
      Attention           : HRA.Household_Home_Observation.Attention_Observation;
      Marker              : Character := ' ';
   end record;

   type Calendar_Week is array (HRA.Dates.Day_Of_Week) of Calendar_Cell;

   package Calendar_Week_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Calendar_Week);

   type Calendar_Grid is record
      Year  : Positive := 2026;
      Month : Positive range 1 .. 12 := 1;
      Weeks : Calendar_Week_Vectors.Vector;
   end record;

   --  ========================================================================
   --  Selected Day Domain Presentations
   --  ========================================================================

   --  Actual Detail Presentation
   type Actual_Item is record
      Transaction_Id : Unbounded_String;
      Date_Text      : Unbounded_String;
      Description    : Unbounded_String;
      Postings_Text  : Unbounded_String;
      Total_Amount   : Unbounded_String;
   end record;

   package Actual_Item_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Actual_Item);

   type Actual_Presentation
     (Status : HRA.Household_Home_Observation.Actual_Availability :=
        HRA.Household_Home_Observation.Unavailable)
   is record
      case Status is
         when HRA.Household_Home_Observation.Available =>
            Items : Actual_Item_Vectors.Vector;
         when HRA.Household_Home_Observation.Unavailable =>
            Unavailable_Message : Unbounded_String;
      end case;
   end record;

   --  Plan Detail Presentation
   type Plan_Item is record
      Plan_Id       : Unbounded_String;
      Due_Date_Text : Unbounded_String;
      Status_Text   : Unbounded_String;
      Description   : Unbounded_String;
      Postings_Text : Unbounded_String;
      Total_Amount  : Unbounded_String;
   end record;

   package Plan_Item_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Plan_Item);

   type Plan_Presentation
     (Status : HRA.Household_Home_Observation.Plan_Availability :=
        HRA.Household_Home_Observation.Unavailable)
   is record
      case Status is
         when HRA.Household_Home_Observation.Available =>
            Items : Plan_Item_Vectors.Vector;
         when HRA.Household_Home_Observation.Unavailable =>
            Unavailable_Message : Unbounded_String;
      end case;
   end record;

   --  Issue Detail Presentation
   type Issue_Item is record
      Issue_Id      : Unbounded_String;
      Title         : Unbounded_String;
      Category      : Unbounded_String;
      Status_Text   : Unbounded_String;
      Due_Date_Text : Unbounded_String;
      Details_Text  : Unbounded_String;
      Amount_Text   : Unbounded_String;
   end record;

   package Issue_Item_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Issue_Item);

   type Issue_Presentation
     (Status : HRA.Household_Home_Observation.Issue_Availability :=
        HRA.Household_Home_Observation.Unavailable)
   is record
      case Status is
         when HRA.Household_Home_Observation.Available =>
            Items : Issue_Item_Vectors.Vector;
         when HRA.Household_Home_Observation.Unavailable =>
            Unavailable_Message : Unbounded_String;
      end case;
   end record;

   --  Cycle Detail Presentation
   type Cycle_Presentation
     (Status : HRA.Household_Home_Observation.Cycle_Availability :=
        HRA.Household_Home_Observation.Unavailable)
   is record
      case Status is
         when HRA.Household_Home_Observation.Available =>
            Has_Previous_Window  : Boolean := False;
            Previous_Window_Text : Unbounded_String;
            Has_Current_Window   : Boolean := False;
            Current_Window_Text  : Unbounded_String;
            Focus_Cycle_Role     : Unbounded_String;
         when HRA.Household_Home_Observation.Unavailable =>
            Unavailable_Message : Unbounded_String;
      end case;
   end record;

   --  ========================================================================
   --  Top-Level Home Presentation Model
   --  ========================================================================

   type Home_Presentation is record
      Observed_Through : HRA.Dates.Date;
      Selected_Day     : HRA.Dates.Date;
      Is_Future_Focus  : Boolean := False;
      Attention        : HRA.Household_Home_Observation.Attention_Observation;
      Calendar         : Calendar_Grid;
      Actual           : Actual_Presentation;
      Plan             : Plan_Presentation;
      Issue            : Issue_Presentation;
      Cycle            : Cycle_Presentation;
   end record;

   --  Construct complete pure presentation model from semantic Home_Observation
   function Present
     (Observation : HRA.Household_Home_Observation.Home_Observation;
      Markers     : HRA.Report_Config.Calendar_Markers :=
        (Cycle_End => '|', Plan_Due => '$', Issue_Due => '!', Multiple => '+'))
      return Home_Presentation;

   --  ========================================================================
   --  Rendering and Text Formatting
   --  ========================================================================

   --  Format a single cell for terminal grid display (5 columns, e.g. "   19 ", " [19] ", "  25$ ", " [25$]")
   function Format_Cell (Cell : Calendar_Cell) return String;

   --  Render the monthly calendar grid view
   function Render_Calendar_Grid (Grid : Calendar_Grid) return String;

   --  Render full Household Home presentation into formatted text
   function Render_Home (Pres : Home_Presentation) return String;

end HRA.Household_Home_Presentation;
