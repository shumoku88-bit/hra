with ALedger.Account;
with ALedger.Dates;
with ALedger.Ledger;
with ALedger.Plan_Observation;

package ALedger.Cycle_Observation is

   subtype Cycle_Window is ALedger.Dates.Half_Open_Period;

   type Resolve_Status is
     (Success,
      Invalid_Observation_Date,
      Income_Account_Not_Declared,
      Income_Account_Has_Wrong_Type,
      Insufficient_Actual_Anchors,
      Missing_Future_Plan_Anchor,
      Invalid_Cycle_Window);

   function Resolve_Current
     (Observed_Through : ALedger.Dates.Date;
      Actual_Ledger    : ALedger.Ledger.Ledger;
      Open_Plans       : ALedger.Plan_Observation.Open_Plan_Vectors.Vector;
      Registry         : ALedger.Account.Account_Registry;
      Income_Account   : ALedger.Account.Account;
      Window           : out Cycle_Window;
      Status           : out Resolve_Status) return Boolean;

   function Start_Date (Window : Cycle_Window) return ALedger.Dates.Date;
   function End_Exclusive (Window : Cycle_Window) return ALedger.Dates.Date;

   function Contains
     (Window : Cycle_Window;
      Date   : ALedger.Dates.Date) return Boolean;

end ALedger.Cycle_Observation;
