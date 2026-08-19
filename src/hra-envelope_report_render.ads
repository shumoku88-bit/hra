with HRA.Household_Report_Observation;

package HRA.Envelope_Report_Render is

   function Render
     (Observation :
        HRA.Household_Report_Observation.Envelope_Report_Observation)
      return String;

end HRA.Envelope_Report_Render;
