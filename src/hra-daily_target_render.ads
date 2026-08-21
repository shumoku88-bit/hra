with HRA.Daily_Target_Observation;
with HRA.Household_Daily_Target_View;

--  Presentation renderer for Daily Target report section.
--  Consumes exact Daily Target view and observation values without decimalizing
--  or rounding multi-commodity balances or day-count ratios.
package HRA.Daily_Target_Render is

   function Render
     (Value : HRA.Daily_Target_Observation.Observation) return String;

   function Render
     (Value : HRA.Household_Daily_Target_View.View) return String;

end HRA.Daily_Target_Render;
