with HRA.Household;
with HRA.Household_Report_Observation;

package HRA.Envelope_Report_Render is

   function Render
     (State       : HRA.Household.Household_State;
      Observation : HRA.Household_Report_Observation.Report_Observation)
      return String;

end HRA.Envelope_Report_Render;
