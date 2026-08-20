with HRA.Household;

--  Focused check observation over one already-admitted Household state.
--  This package produces a typed summary of admitted Household facts for the
--  check command. It does not perform validation or admission.
package HRA.Household_Check_Observation is

   type Observation is record
      Actual_Transactions  : Natural;
      Plan_Transactions    : Natural;
      Entitlement_Movements : Natural;
      Registered_Accounts  : Natural;
      Open_Issues          : Natural;
   end record;

   function Observe
     (State : HRA.Household.Household_State)
      return Observation;

end HRA.Household_Check_Observation;
