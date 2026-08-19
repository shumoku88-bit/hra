with HRA.Cycle_Observation;
with HRA.Dates;
with HRA.Household;
with HRA.Issue_Observation;
with HRA.Ledger;
with HRA.Plan_Observation;

--  Pure semantic observation for the Household Home view over one
--  already-admitted Household_State.
--
--  Temporal coordinate laws:
--    Observed_Through : knowledge / observation horizon
--    Selected_Day     : focus coordinate
--
--  Selected_Day > Observed_Through means Actual is Unavailable.
--  Future-dated admitted Actual transactions in State are never leaked.
--  Plan, Issue, and Cycle reflect knowledge known as of Observed_Through.
--  Empty results (0 transactions/plans/issues) are distinct from Unavailable.
--
--  Home_Observation is opaque; presentation layers cannot manufacture
--  instances or inspect internal context vectors directly.
--
--  Calendar presentation (grid, weekday layout, marker chars, color, width)
--  is strictly excluded from this package.
package HRA.Household_Home_Observation is

   --  ========================================================================
   --  Attention Facts (Present / Absent / Unavailable)
   --  ========================================================================

   type Attention_Status is (Present, Absent, Unavailable);

   type Attention_Observation is record
      Plan_Scheduled : Attention_Status := Absent;
      Issue_Due      : Attention_Status := Absent;
      Cycle_End      : Attention_Status := Absent;
   end record;

   --  ========================================================================
   --  Actual Observation on Selected Day
   --  ========================================================================

   type Actual_Availability is (Available, Unavailable);

   type Actual_Unavailable_Reason is (Observation_Horizon_Exceeded);

   type Actual_Home_Observation (Status : Actual_Availability := Unavailable) is record
      case Status is
         when Available =>
            Transactions : HRA.Ledger.Transaction_Vectors.Vector;
         when Unavailable =>
            Reason : Actual_Unavailable_Reason := Observation_Horizon_Exceeded;
      end case;
   end record;

   function Is_Available (Obs : Actual_Home_Observation) return Boolean;

   function Transaction_Count (Obs : Actual_Home_Observation) return Natural
     with Pre => Is_Available (Obs);

   --  ========================================================================
   --  Plan Observation on Selected Day
   --  ========================================================================

   type Plan_Availability is (Available, Unavailable);

   type Plan_Home_Observation (Status : Plan_Availability := Unavailable) is record
      case Status is
         when Available =>
            Open_Plans : HRA.Plan_Observation.Open_Plan_Vectors.Vector;
         when Unavailable =>
            Error : HRA.Plan_Observation.Admission_Diagnostic;
      end case;
   end record;

   function Is_Available (Obs : Plan_Home_Observation) return Boolean;

   function Open_Plan_Count (Obs : Plan_Home_Observation) return Natural
     with Pre => Is_Available (Obs);

   --  ========================================================================
   --  Issue Observation on Selected Day
   --  ========================================================================

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

   --  ========================================================================
   --  Cycle Observation
   --  ========================================================================

   type Cycle_Availability is (Available, Unavailable);

   type Cycle_Unavailable_Reason is
     (Plan_Dependency_Unavailable,
      Cycle_Resolution_Failed);

   type Cycle_Home_Observation (Status : Cycle_Availability := Unavailable) is record
      case Status is
         when Available =>
            Current_Window : HRA.Cycle_Observation.Cycle_Window;
            Human_End_Day  : HRA.Dates.Date;
         when Unavailable =>
            Reason      : Cycle_Unavailable_Reason := Cycle_Resolution_Failed;
            Plan_Error  : HRA.Plan_Observation.Admission_Diagnostic;
            Cycle_Error : HRA.Cycle_Observation.Resolve_Status :=
              HRA.Cycle_Observation.Success;
      end case;
   end record;

   function Is_Available (Obs : Cycle_Home_Observation) return Boolean;

   --  ========================================================================
   --  Household Home Observation (Opaque Type)
   --  ========================================================================

   type Home_Observation is private;

   --  Observe Household Home for given observation horizon and focus coordinate.
   function Observe
     (Observed_Through : HRA.Dates.Date;
      Selected_Day     : HRA.Dates.Date;
      State            : HRA.Household.Household_State) return Home_Observation;

   --  Read-only projections for the observation coordinates and domain results.
   function Observed_Through (Obs : Home_Observation) return HRA.Dates.Date;
   function Selected_Day (Obs : Home_Observation) return HRA.Dates.Date;
   function Actual (Obs : Home_Observation) return Actual_Home_Observation;
   function Plan (Obs : Home_Observation) return Plan_Home_Observation;
   function Issue (Obs : Home_Observation) return Issue_Home_Observation;
   function Cycle (Obs : Home_Observation) return Cycle_Home_Observation;

   --  Derived attention for the selected day.
   function Selected_Attention (Obs : Home_Observation) return Attention_Observation;

   --  Derive semantic attention facts for an arbitrary coordinate day using the
   --  private as-of context retained in Home_Observation.
   function Day_Attention
     (Obs : Home_Observation;
      Day : HRA.Dates.Date) return Attention_Observation;

private

   type Home_Observation is record
      Observed_Through : HRA.Dates.Date;
      Selected_Day     : HRA.Dates.Date;
      Actual           : Actual_Home_Observation;
      Plan             : Plan_Home_Observation;
      Issue            : Issue_Home_Observation;
      Cycle            : Cycle_Home_Observation;
      All_Open_Plans   : HRA.Plan_Observation.Open_Plan_Vectors.Vector;
      Issue_Context    : HRA.Issue_Observation.Observation;
   end record;

end HRA.Household_Home_Observation;
