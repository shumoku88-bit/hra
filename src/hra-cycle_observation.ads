with HRA.Account;
with HRA.Dates;
with HRA.Ledger;
with HRA.Plan_Observation;

package HRA.Cycle_Observation is

   subtype Cycle_Window is HRA.Dates.Half_Open_Period;

   type Resolve_Status is
     (Success,
      Invalid_Observation_Date,
      Income_Account_Not_Declared,
      Income_Account_Has_Wrong_Type,
      Insufficient_Actual_Anchors,
      Missing_Future_Plan_Anchor,
      Invalid_Cycle_Window);

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
