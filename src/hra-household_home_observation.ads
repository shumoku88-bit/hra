with HRA.Cycle_Observation;
with HRA.Dates;
with HRA.Household;
with HRA.Household_Daily_Target_View;
with HRA.Issue_Observation;
with HRA.Ledger;
with HRA.Plan_Temporal_Observation;

--  Pure semantic view for Household Home over one already-admitted
--  Household_State.
--
--  Temporal coordinate laws:
--    Known_Through : knowledge horizon
--    Selected_Day  : focus coordinate
--
--  Selected_Day > Known_Through means Actual is Unavailable.
--  Future-dated admitted Actual transactions in State are never leaked.
--  Plan, Issue, Cycle, and Daily Target reflect what is known through Known_Through.
--  Empty results (0 transactions/plans/issues) are distinct from Unavailable.
--
--  Home_Observation is opaque; presentation layers cannot manufacture
--  instances or inspect internal context vectors directly.
--
--  Calendar presentation (grid, weekday layout, marker chars, color, width)
--  is strictly excluded from this package.
package HRA.Household_Home_Observation is

   type Attention_Status is (Present, Absent, Unavailable);

   type Attention_Observation is record
      Plan_Scheduled : Attention_Status := Absent;
      Issue_Due      : Attention_Status := Absent;
      Cycle_End      : Attention_Status := Absent;
   end record;

   type Actual_Availability is (Available, Unavailable);

   type Actual_Unavailable_Reason is (Beyond_Known_Horizon);

   type Actual_Home_Observation (Status : Actual_Availability := Unavailable) is record
      case Status is
         when Available =>
            Transactions : HRA.Ledger.Transaction_Vectors.Vector;
         when Unavailable =>
            Reason : Actual_Unavailable_Reason := Beyond_Known_Horizon;
      end case;
   end record;

   function Is_Available (Obs : Actual_Home_Observation) return Boolean;

   function Transaction_Count (Obs : Actual_Home_Observation) return Natural
     with Pre => Is_Available (Obs);

   --  Plan source admission and completion relation resolution have already
   --  succeeded before a Household_State exists. Home therefore owns only a
   --  temporal Plan projection; there is no synthetic Plan-unavailable state.
   type Plan_Home_Observation is record
      Open_Plans : HRA.Plan_Temporal_Observation.Open_Plan_Vectors.Vector;
   end record;

   function Open_Plan_Count (Obs : Plan_Home_Observation) return Natural;

   type Issue_Availability is (Available, Unavailable);

   type Issue_Unavailable_Reason is (Closure_Timing_Undetermined);

   type Issue_Home_Observation (Status : Issue_Availability := Unavailable) is record
      case Status is
         when Available =>
            Due_Issues : HRA.Issue_Observation.Observed_Issue_Vectors.Vector;
         when Unavailable =>
            Reason : Issue_Unavailable_Reason := Closure_Timing_Undetermined;
      end case;
   end record;

   function Is_Available (Obs : Issue_Home_Observation) return Boolean;

   function Due_Issue_Count (Obs : Issue_Home_Observation) return Natural
     with Pre => Is_Available (Obs);

   type Cycle_Availability is (Available, Unavailable);

   type Cycle_Home_Observation (Status : Cycle_Availability := Unavailable) is record
      case Status is
         when Available =>
            Observation : HRA.Cycle_Observation.Observation;
         when Unavailable =>
            Error : HRA.Cycle_Observation.Resolve_Status;
      end case;
   end record;

   function Is_Available (Obs : Cycle_Home_Observation) return Boolean;

   type Home_Horizon_Observation is private;

   --  See the horizon-stable Plan, Issue, Cycle, Daily Target, and
   --  calendar-attention projections using only facts known through Known_Through.
   function See_Horizon
     (Known_Through : HRA.Dates.Date;
      State         : HRA.Household.Household_State) return Home_Horizon_Observation;

   function Known_Through
     (Horizon : Home_Horizon_Observation) return HRA.Dates.Date;

   function Cycle
     (Horizon : Home_Horizon_Observation) return Cycle_Home_Observation;

   function Daily_Target
     (Horizon : Home_Horizon_Observation) return HRA.Household_Daily_Target_View.View;

   function Day_Attention
     (Horizon : Home_Horizon_Observation;
      Day     : HRA.Dates.Date) return Attention_Observation;

   type Home_Day_Observation is private;

   --  Project day-local details (Actual transactions, open Plans, due Issues,
   --  selected-day attention) onto an existing horizon observation.
   --  Home_Day_Observation does NOT own or copy Home_Horizon_Observation.
   function Project_Day
     (Horizon      : Home_Horizon_Observation;
      Selected_Day : HRA.Dates.Date;
      State        : HRA.Household.Household_State) return Home_Day_Observation;

   function Selected_Day (Day_Obs : Home_Day_Observation) return HRA.Dates.Date;
   function Actual (Day_Obs : Home_Day_Observation) return Actual_Home_Observation;
   function Plan (Day_Obs : Home_Day_Observation) return Plan_Home_Observation;
   function Issue (Day_Obs : Home_Day_Observation) return Issue_Home_Observation;
   function Selected_Attention (Day_Obs : Home_Day_Observation) return Attention_Observation;

   type Home_Observation is private;

   --  Combined convenience: See_Horizon followed by Project_Day.
   function See_Home
     (Known_Through : HRA.Dates.Date;
      Selected_Day  : HRA.Dates.Date;
      State         : HRA.Household.Household_State) return Home_Observation;

   function Horizon (Obs : Home_Observation) return Home_Horizon_Observation;
   function Day (Obs : Home_Observation) return Home_Day_Observation;
   function Known_Through (Obs : Home_Observation) return HRA.Dates.Date;
   function Selected_Day (Obs : Home_Observation) return HRA.Dates.Date;
   function Actual (Obs : Home_Observation) return Actual_Home_Observation;
   function Plan (Obs : Home_Observation) return Plan_Home_Observation;
   function Issue (Obs : Home_Observation) return Issue_Home_Observation;
   function Cycle (Obs : Home_Observation) return Cycle_Home_Observation;
   function Daily_Target (Obs : Home_Observation) return HRA.Household_Daily_Target_View.View;

   function Selected_Attention (Obs : Home_Observation) return Attention_Observation;

   function Day_Attention
     (Obs : Home_Observation;
      Day : HRA.Dates.Date) return Attention_Observation;

private

   type Home_Horizon_Observation is record
      Known_Through  : HRA.Dates.Date;
      Cycle          : Cycle_Home_Observation;
      All_Open_Plans : HRA.Plan_Temporal_Observation.Open_Plan_Vectors.Vector;
      Issue_Context  : HRA.Issue_Observation.Observation;
      Daily_Target   : HRA.Household_Daily_Target_View.View;
   end record;

   type Home_Day_Observation is record
      Selected_Day : HRA.Dates.Date;
      Actual       : Actual_Home_Observation;
      Plan         : Plan_Home_Observation;
      Issue        : Issue_Home_Observation;
      Attention    : Attention_Observation;
   end record;

   type Home_Observation is record
      Horizon : Home_Horizon_Observation;
      Day     : Home_Day_Observation;
   end record;

end HRA.Household_Home_Observation;
