with ALedger.Household;
with ALedger.Household_Report_Observation;

package ALedger.Envelope_Report_Render is

   function Render
     (State       : ALedger.Household.Household_State;
      Observation : ALedger.Household_Report_Observation.Report_Observation)
      return String;

end ALedger.Envelope_Report_Render;
