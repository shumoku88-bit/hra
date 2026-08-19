package body HRA.Household_Home_Interaction is

   Days_Per_Week : constant Positive := 7;

   function Step_Days_Forward
     (Start  : HRA.Dates.Date;
      Count  : Positive;
      Result : out HRA.Dates.Date) return Boolean
   is
      Cur : HRA.Dates.Date := Start;
   begin
      for Step in 1 .. Count loop
         if not HRA.Dates.Has_Next (Cur) then
            return False;
         end if;
         Cur := HRA.Dates.Next (Cur);
      end loop;
      Result := Cur;
      return True;
   end Step_Days_Forward;

   function Step_Days_Backward
     (Start  : HRA.Dates.Date;
      Count  : Positive;
      Result : out HRA.Dates.Date) return Boolean
   is
      Cur : HRA.Dates.Date := Start;
   begin
      for Step in 1 .. Count loop
         if not HRA.Dates.Has_Previous (Cur) then
            return False;
         end if;
         Cur := HRA.Dates.Previous (Cur);
      end loop;
      Result := Cur;
      return True;
   end Step_Days_Backward;

   function Make_Coordinates
     (Observed_Through : HRA.Dates.Date) return Home_Coordinates
   is
     ((Observed_Through => Observed_Through,
       Selected_Day     => Observed_Through));

   function Make_Coordinates
     (Observed_Through : HRA.Dates.Date;
      Selected_Day     : HRA.Dates.Date) return Home_Coordinates
   is
     ((Observed_Through => Observed_Through,
       Selected_Day     => Selected_Day));

   function Select_Day
     (Coordinates : Home_Coordinates;
      Day         : HRA.Dates.Date) return Transition_Result
   is
     ((Status      => Applied,
       Coordinates =>
         (Observed_Through => Coordinates.Observed_Through,
          Selected_Day     => Day)));

   function Previous_Day
     (Coordinates : Home_Coordinates) return Transition_Result
   is
      Target : HRA.Dates.Date;
   begin
      if Step_Days_Backward (Coordinates.Selected_Day, 1, Target) then
         return
           (Status      => Applied,
            Coordinates =>
              (Observed_Through => Coordinates.Observed_Through,
               Selected_Day     => Target));
      else
         return
           (Status      => Lower_Bound_Exceeded,
            Coordinates => Coordinates);
      end if;
   end Previous_Day;

   function Next_Day
     (Coordinates : Home_Coordinates) return Transition_Result
   is
      Target : HRA.Dates.Date;
   begin
      if Step_Days_Forward (Coordinates.Selected_Day, 1, Target) then
         return
           (Status      => Applied,
            Coordinates =>
              (Observed_Through => Coordinates.Observed_Through,
               Selected_Day     => Target));
      else
         return
           (Status      => Upper_Bound_Exceeded,
            Coordinates => Coordinates);
      end if;
   end Next_Day;

   function Previous_Week
     (Coordinates : Home_Coordinates) return Transition_Result
   is
      Target : HRA.Dates.Date;
   begin
      if Step_Days_Backward (Coordinates.Selected_Day, Days_Per_Week, Target) then
         return
           (Status      => Applied,
            Coordinates =>
              (Observed_Through => Coordinates.Observed_Through,
               Selected_Day     => Target));
      else
         return
           (Status      => Lower_Bound_Exceeded,
            Coordinates => Coordinates);
      end if;
   end Previous_Week;

   function Next_Week
     (Coordinates : Home_Coordinates) return Transition_Result
   is
      Target : HRA.Dates.Date;
   begin
      if Step_Days_Forward (Coordinates.Selected_Day, Days_Per_Week, Target) then
         return
           (Status      => Applied,
            Coordinates =>
              (Observed_Through => Coordinates.Observed_Through,
               Selected_Day     => Target));
      else
         return
           (Status      => Upper_Bound_Exceeded,
            Coordinates => Coordinates);
      end if;
   end Next_Week;

   function Focus_Observed_Through
     (Coordinates : Home_Coordinates) return Transition_Result
   is
     ((Status      => Applied,
       Coordinates =>
         (Observed_Through => Coordinates.Observed_Through,
          Selected_Day     => Coordinates.Observed_Through)));

   function Apply_Intent
     (Coordinates : Home_Coordinates;
      Intent      : Home_Intent) return Transition_Result
   is
   begin
      case Intent.Kind is
         when Select_Day =>
            return Select_Day (Coordinates, Intent.Target_Day);
         when Previous_Day =>
            return Previous_Day (Coordinates);
         when Next_Day =>
            return Next_Day (Coordinates);
         when Previous_Week =>
            return Previous_Week (Coordinates);
         when Next_Week =>
            return Next_Week (Coordinates);
         when Focus_Observed_Through =>
            return Focus_Observed_Through (Coordinates);
      end case;
   end Apply_Intent;

end HRA.Household_Home_Interaction;
