with HRA.Household_Report_Observation;
with HRA.Household_Envelope_Change;
with HRA.Household_Envelope_Cycle_Comparison;

package HRA.Envelope_Report_Render is

   function Render
     (Observation :
        HRA.Household_Report_Observation.Envelope_Report_Observation)
      return String;

   --  Render an already-observed same-cycle Change. This surface performs no
   --  temporal resolution or arithmetic; it only exposes the typed differences
   --  retained by Household_Envelope_Change.
   function Render
     (Observation : HRA.Household_Envelope_Change.Change_Observation)
      return String;

   --  Render an already-observed aligned previous-cycle comparison without
   --  weakening it into a cross-cycle Change.
   function Render
     (Observation :
        HRA.Household_Envelope_Cycle_Comparison.Comparison_Observation)
      return String;

end HRA.Envelope_Report_Render;
