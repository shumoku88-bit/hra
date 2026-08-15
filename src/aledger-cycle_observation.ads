with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with ALedger.Account;
with ALedger.Ledger;
with ALedger.Plan_Observation;

package ALedger.Cycle_Observation is

   type Cycle_Window is record
      Start_Date    : Unbounded_String;
      End_Exclusive : Unbounded_String;
   end record;

   type Resolve_Status is
     (Success,
      Invalid_Observation_Date,
      Income_Account_Not_Declared,
      Income_Account_Has_Wrong_Type,
      Insufficient_Actual_Anchors,
      Missing_Future_Plan_Anchor,
      Invalid_Cycle_Window);

   function Resolve_Current
     (Observed_Through : String;
      Actual_Ledger    : ALedger.Ledger.Ledger;
      Open_Plans       : ALedger.Plan_Observation.Open_Plan_Vectors.Vector;
      Registry         : ALedger.Account.Account_Registry;
      Income_Account   : ALedger.Account.Account;
      Window           : out Cycle_Window;
      Status           : out Resolve_Status) return Boolean;

   function Contains
     (Window : Cycle_Window;
      Date   : String) return Boolean;

end ALedger.Cycle_Observation;
