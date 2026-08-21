with HRA.Household_Report_Observation;
with HRA.Planned_Payments;

package HRA.Planned_Payments_Render is

   function Render
     (Value : HRA.Planned_Payments.Observation) return String;

   function Render
     (Value : HRA.Household_Report_Observation.Planned_Payments_Report_Observation)
      return String;

end HRA.Planned_Payments_Render;
