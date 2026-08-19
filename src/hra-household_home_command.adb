with HRA.Household_Home_Observation;
with HRA.Household_Home_Presentation;
with HRA.Household_Home_Text;

package body HRA.Household_Home_Command is

   use Ada.Strings.Unbounded;
   use type HRA.Dates.Date;

   function Resolve_Dates
     (Through_Text : String;
      Day_Text     : String;
      Today        : HRA.Dates.Date) return Command_Resolution
   is
      Result : Command_Resolution :=
        (Status  => Success,
         Options => (Base_Directory   => Null_Unbounded_String,
                     Observed_Through => Today,
                     Through_Source   => Defaulted,
                     Selected_Day     => Today,
                     Day_Source       => Defaulted),
         Message => Null_Unbounded_String);
      Date_Val : HRA.Dates.Date;
      Date_St  : HRA.Dates.Date_Status;
   begin
      if Through_Text'Length > 0 then
         if not HRA.Dates.Parse (Through_Text, Date_Val, Date_St) then
            Result.Status := Invalid_Through_Date;
            Result.Message :=
              To_Unbounded_String
                ("invalid Gregorian date for --through: " & Through_Text);
            return Result;
         end if;
         Result.Options.Observed_Through := Date_Val;
         Result.Options.Through_Source   := Explicit;
      else
         Result.Options.Observed_Through := Today;
         Result.Options.Through_Source   := Defaulted;
      end if;

      if Day_Text'Length > 0 then
         if not HRA.Dates.Parse (Day_Text, Date_Val, Date_St) then
            Result.Status := Invalid_Day_Date;
            Result.Message :=
              To_Unbounded_String
                ("invalid Gregorian date for --day: " & Day_Text);
            return Result;
         end if;
         Result.Options.Selected_Day := Date_Val;
         Result.Options.Day_Source   := Explicit;
      else
         Result.Options.Selected_Day := Result.Options.Observed_Through;
         Result.Options.Day_Source   := Defaulted;
      end if;

      return Result;
   end Resolve_Dates;

   function Parse_Arguments
     (Args  : String_Array;
      Today : HRA.Dates.Date) return Command_Resolution
   is
      Base_Dir     : Unbounded_String := Null_Unbounded_String;
      Through_Str  : Unbounded_String := Null_Unbounded_String;
      Day_Str      : Unbounded_String := Null_Unbounded_String;
      I            : Positive := Args'First;
   begin
      while I <= Args'Last loop
         declare
            Arg : constant String := To_String (Args (I));
         begin
            if Arg = "--base" then
               if I + 1 > Args'Last then
                  return
                    (Status  => Missing_Option_Value,
                     Options => <>,
                     Message => To_Unbounded_String ("missing value for option --base"));
               end if;
               Base_Dir := Args (I + 1);
               I := I + 2;
            elsif Arg = "--through" then
               if I + 1 > Args'Last then
                  return
                    (Status  => Missing_Option_Value,
                     Options => <>,
                     Message => To_Unbounded_String ("missing value for option --through"));
               end if;
               Through_Str := Args (I + 1);
               I := I + 2;
            elsif Arg = "--day" then
               if I + 1 > Args'Last then
                  return
                    (Status  => Missing_Option_Value,
                     Options => <>,
                     Message => To_Unbounded_String ("missing value for option --day"));
               end if;
               Day_Str := Args (I + 1);
               I := I + 2;
            else
               return
                 (Status  => Unknown_Option,
                  Options => <>,
                  Message => To_Unbounded_String ("unknown option: " & Arg));
            end if;
         end;
      end loop;

      declare
         Res : Command_Resolution :=
           Resolve_Dates
             (Through_Text => To_String (Through_Str),
              Day_Text     => To_String (Day_Str),
              Today        => Today);
      begin
         if Res.Status = Success then
            Res.Options.Base_Directory := Base_Dir;
         end if;
         return Res;
      end;
   end Parse_Arguments;

   function Execute_Home
     (State            : HRA.Household.Household_State;
      Observed_Through : HRA.Dates.Date;
      Selected_Day     : HRA.Dates.Date) return String
   is
      Obs  : constant HRA.Household_Home_Observation.Home_Observation :=
        HRA.Household_Home_Observation.Observe
          (Observed_Through => Observed_Through,
           Selected_Day     => Selected_Day,
           State            => State);
      Pres : constant HRA.Household_Home_Presentation.Home_Presentation :=
        HRA.Household_Home_Presentation.Present (Obs);
   begin
      return HRA.Household_Home_Text.Render_Home
        (Pres, State.Report_Policy.Presentation.Calendar);
   end Execute_Home;

end HRA.Household_Home_Command;
