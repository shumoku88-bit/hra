package body HRA.Household_Home_Coordinates is

   function Place
     (Visible_Through : HRA.Dates.Date;
      Focus_Day       : HRA.Dates.Date) return Coordinates
   is
   begin
      return
        (Through_Date => Visible_Through,
         Focus_Date   => Focus_Day);
   end Place;

   function Visible_Through
     (Position : Coordinates) return HRA.Dates.Date is
     (Position.Through_Date);

   function Focus_Day
     (Position : Coordinates) return HRA.Dates.Date is
     (Position.Focus_Date);

   function See
     (Position : Coordinates;
      State    : HRA.Household.Household_State)
      return HRA.Household_Home_Observation.Home_Observation
   is
   begin
      return HRA.Household_Home_Observation.See_Home
        (Known_Through => Position.Through_Date,
         Selected_Day  => Position.Focus_Date,
         State         => State);
   end See;

end HRA.Household_Home_Coordinates;
