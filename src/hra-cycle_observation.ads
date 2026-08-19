with HRA.Account;
with HRA.Dates;
with HRA.Ledger;
with HRA.Plan_Observation;

package HRA.Cycle_Observation is

   subtype Cycle_Window is HRA.Dates.Half_Open_Period;

   type Observation is record
      Current_Window  : Cycle_Window;
      Previous_Window : Cycle_Window;
   end record;

   type Resolve_Status is
     (Success,
      Invalid_Observation_Date,
      Income_Account_Not_Declared,
      Income_Account_Has_Wrong_Type,
      Insufficient_Actual_Anchors,
      Missing_Future_Plan_Anchor,
      Invalid_Cycle_Window);

   --  Observe the income-anchor cycle context once. The previous cycle is the
   --  interval between the two latest admitted Actual anchors, while the current
   --  cycle runs from the latest Actual anchor to the first applicable future
   --  Plan anchor. Both windows are retained as typed evidence.
   function Observe
     (Observed_Through : HRA.Dates.Date;
      Actual_Ledger    : HRA.Ledger.Ledger;
      Open_Plans       : HRA.Plan_Observation.Open_Plan_Vectors.Vector;
      Registry         : HRA.Account.Account_Registry;
      Income_Account   : HRA.Account.Account;
      Result           : out Observation;
      Status           : out Resolve_Status) return Boolean;

   --  Current-window projection over the same observation owner. This keeps
   --  existing focused callers small without introducing a second resolver.
   function Resolve_Current
     (Observed_Through : HRA.Dates.Date;
      Actual_Ledger    : HRA.Ledger.Ledger;
      Open_Plans       : HRA.Plan_Observation.Open_Plan_Vectors.Vector;
      Registry         : HRA.Account.Account_Registry;
      Income_Account   : HRA.Account.Account;
      Window           : out Cycle_Window;
      Status           : out Resolve_Status) return Boolean;

   function Start_Date (Window : Cycle_Window) return HRA.Dates.Date;
   function End_Exclusive (Window : Cycle_Window) return HRA.Dates.Date;

   function Contains
     (Window : Cycle_Window;
      Date   : HRA.Dates.Date) return Boolean;

end HRA.Cycle_Observation;
