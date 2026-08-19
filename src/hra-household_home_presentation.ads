with Ada.Containers.Vectors;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA.Account;
with HRA.Cycle_Observation;
with HRA.Dates;
with HRA.Household_Home_Observation;
with HRA.Issue_Observation;
with HRA.Issues;
with HRA.Money;
with HRA.Plan;
with HRA.Plan_Observation;

--  Pure presentation mapping for Household Home observation.
--  Transforms semantic Home_Observation into UI-neutral structured view models:
--    - Monthly calendar grid with attention facts
--    - Structured Selected-Day details for Actual, Plan, Issue, and Cycle
--
--  Terminal-specific formatting (fixed-width cells, ASCII boxes, glyph mapping)
--  is strictly excluded and owned by HRA.Household_Home_Text.
package HRA.Household_Home_Presentation is

   --  ========================================================================
   --  Attention Presentation Model
   --  ========================================================================

   type Attention_State is (Absent, Present, Unavailable);

   type Attention_Summary is record
      Plan_Scheduled : Attention_State := Absent;
      Issue_Due      : Attention_State := Absent;
      Cycle_End      : Attention_State := Absent;
   end record;

   --  ========================================================================
   --  Calendar Grid Model
   --  ========================================================================

   type Calendar_Cell_Kind is (Dated_Cell, Out_Of_Range_Padding);

   type Calendar_Cell (Kind : Calendar_Cell_Kind := Dated_Cell) is record
      case Kind is
         when Dated_Cell =>
            Date_Value          : HRA.Dates.Date;
            Is_Current_Month    : Boolean := False;
            Is_Selected         : Boolean := False;
            Is_Observed_Through : Boolean := False;
            Is_Future           : Boolean := False;
            Attention           : Attention_Summary;
         when Out_Of_Range_Padding =>
            null;
      end case;
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
   --  Structured Posting Model
   --  ========================================================================

   type Posting_Item is record
      Account : HRA.Account.Account;
      Amount  : HRA.Money.Amount;
   end record;

   package Posting_Item_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Posting_Item);

   --  ========================================================================
   --  Selected Day Domain Presentations
   --  ========================================================================

   type Domain_Availability is (Available, Unavailable);

   --  Actual Detail Presentation
   type Actual_Unavailable_Reason is (Observation_Horizon_Exceeded);

   type Actual_Item is record
      Transaction_Id : Unbounded_String;
      Date           : HRA.Dates.Date;
      Description    : Unbounded_String;
      Postings       : Posting_Item_Vectors.Vector;
   end record;

   package Actual_Item_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Actual_Item);

   type Actual_Presentation (Status : Domain_Availability := Unavailable) is record
      case Status is
         when Available =>
            Items : Actual_Item_Vectors.Vector;
         when Unavailable =>
            Reason : Actual_Unavailable_Reason := Observation_Horizon_Exceeded;
      end case;
   end record;

   --  Plan Detail Presentation
   type Plan_Item is record
      Plan_Id        : HRA.Plan.Plan_Id;
      Scheduled_Date : HRA.Dates.Date;
      Description    : Unbounded_String;
      Postings       : Posting_Item_Vectors.Vector;
   end record;

   package Plan_Item_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Plan_Item);

   type Plan_Presentation (Status : Domain_Availability := Unavailable) is record
      case Status is
         when Available =>
            Items : Plan_Item_Vectors.Vector;
         when Unavailable =>
            Diagnostic : HRA.Plan_Observation.Admission_Diagnostic;
      end case;
   end record;

   --  Issue Detail Presentation
   type Issue_Unavailable_Reason is (Closure_Timing_Undetermined);

   type Issue_Item is record
      Issue_Id     : HRA.Issues.Issue_Id;
      Title        : Unbounded_String;
      Category     : Unbounded_String;
      Status_As_Of : HRA.Issue_Observation.As_Of_Status;
      Due_Date     : HRA.Dates.Date;
      Details      : Unbounded_String;
      Amount       : HRA.Issues.Optional_Amount;
   end record;

   package Issue_Item_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Issue_Item);

   type Issue_Presentation (Status : Domain_Availability := Unavailable) is record
      case Status is
         when Available =>
            Items : Issue_Item_Vectors.Vector;
         when Unavailable =>
            Reason : Issue_Unavailable_Reason := Closure_Timing_Undetermined;
      end case;
   end record;

   --  Cycle Detail Presentation
   type Cycle_Focus_Role is
     (Previous_Cycle_End,
      Current_Cycle_End,
      Previous_Cycle,
      Current_Cycle,
      Outside_Known_Cycles);

   type Cycle_Unavailable_Reason is
     (Plan_Dependency_Unavailable,
      Cycle_Resolution_Failed);

   type Cycle_Unavailable_Detail
     (Reason : Cycle_Unavailable_Reason := Cycle_Resolution_Failed)
   is record
      case Reason is
         when Plan_Dependency_Unavailable =>
            Plan_Error : HRA.Plan_Observation.Admission_Diagnostic;
         when Cycle_Resolution_Failed =>
            Cycle_Error : HRA.Cycle_Observation.Resolve_Status;
      end case;
   end record;

   type Cycle_Presentation (Status : Domain_Availability := Unavailable) is record
      case Status is
         when Available =>
            Previous_Window : HRA.Dates.Half_Open_Period;
            Current_Window  : HRA.Dates.Half_Open_Period;
            Focus_Role      : Cycle_Focus_Role;
         when Unavailable =>
            Failure : Cycle_Unavailable_Detail;
      end case;
   end record;

   --  ========================================================================
   --  Top-Level Home Presentation Model
   --  ========================================================================

   type Home_Presentation is record
      Observed_Through : HRA.Dates.Date;
      Selected_Day     : HRA.Dates.Date;
      Is_Future_Focus  : Boolean := False;
      Attention        : Attention_Summary;
      Calendar         : Calendar_Grid;
      Actual           : Actual_Presentation;
      Plan             : Plan_Presentation;
      Issue            : Issue_Presentation;
      Cycle            : Cycle_Presentation;
   end record;

   --  Construct complete pure presentation model from semantic Home_Observation
   function Present
     (Observation : HRA.Household_Home_Observation.Home_Observation)
      return Home_Presentation;

end HRA.Household_Home_Presentation;
