with HRA.Household_Home_Observation;
with HRA.Household_Home_Presentation;
with HRA.Household_Home_Text;

package body HRA.Household_Home_Command is

   use Ada.Strings.Unbounded;

   function Is_Option_Token (S : String) return Boolean is
   begin
      return S'Length >= 2 and then S (S'First .. S'First + 1) = "--";
   end Is_Option_Token;

   function Parse_Arguments (Args : String_Array) return Parse_Resolution is
      Parsed  : Parsed_Home_Arguments;
      I       : Positive := Args'First;
      Date_St : HRA.Dates.Date_Status;
   begin
      while I <= Args'Last loop
         declare
            Arg : constant String := To_String (Args (I));
         begin
            if Arg = "--base" then
               if Parsed.Has_Base then
                  return
                    (Status  => Duplicate_Option,
                     Parsed  => Parsed,
                     Message => To_Unbounded_String ("duplicate option: --base"));
               end if;

               if I + 1 > Args'Last
                 or else Is_Option_Token (To_String (Args (I + 1)))
               then
                  return
                    (Status  => Missing_Option_Value,
                     Parsed  => Parsed,
                     Message => To_Unbounded_String ("missing value for option --base"));
               end if;

               Parsed.Base_Directory := Args (I + 1);
               Parsed.Has_Base       := True;
               I := I + 2;

            elsif Arg = "--through" then
               if Parsed.Has_Through then
                  return
                    (Status  => Duplicate_Option,
                     Parsed  => Parsed,
                     Message => To_Unbounded_String ("duplicate option: --through"));
               end if;

               if I + 1 > Args'Last
                 or else Is_Option_Token (To_String (Args (I + 1)))
               then
                  return
                    (Status  => Missing_Option_Value,
                     Parsed  => Parsed,
                     Message => To_Unbounded_String ("missing value for option --through"));
               end if;

               declare
                  Val : constant String := To_String (Args (I + 1));
               begin
                  if not HRA.Dates.Parse (Val, Parsed.Through_Date, Date_St) then
                     return
                       (Status  => Invalid_Through_Date,
                        Parsed  => Parsed,
                        Message =>
                          To_Unbounded_String
                            ("invalid Gregorian date for --through: " & Val));
                  end if;
               end;

               Parsed.Has_Through := True;
               I := I + 2;

            elsif Arg = "--day" then
               if Parsed.Has_Day then
                  return
                    (Status  => Duplicate_Option,
                     Parsed  => Parsed,
                     Message => To_Unbounded_String ("duplicate option: --day"));
               end if;

               if I + 1 > Args'Last
                 or else Is_Option_Token (To_String (Args (I + 1)))
               then
                  return
                    (Status  => Missing_Option_Value,
                     Parsed  => Parsed,
                     Message => To_Unbounded_String ("missing value for option --day"));
               end if;

               declare
                  Val : constant String := To_String (Args (I + 1));
               begin
                  if not HRA.Dates.Parse (Val, Parsed.Day_Date, Date_St) then
                     return
                       (Status  => Invalid_Day_Date,
                        Parsed  => Parsed,
                        Message =>
                          To_Unbounded_String
                            ("invalid Gregorian date for --day: " & Val));
                  end if;
               end;

               Parsed.Has_Day := True;
               I := I + 2;

            else
               return
                 (Status  => Unknown_Option,
                  Parsed  => Parsed,
                  Message => To_Unbounded_String ("unknown option: " & Arg));
            end if;
         end;
      end loop;

      return
        (Status  => Success,
         Parsed  => Parsed,
         Message => Null_Unbounded_String);
   end Parse_Arguments;

   function Needs_Clock (Parsed : Parsed_Home_Arguments) return Boolean is
   begin
      return not Parsed.Has_Through;
   end Needs_Clock;

   function Resolve_Home_Options
     (Parsed : Parsed_Home_Arguments;
      Today  : HRA.Dates.Date) return Home_Options
   is
      Opts : Home_Options;
   begin
      Opts.Base_Directory := Parsed.Base_Directory;

      if Parsed.Has_Through then
         Opts.Observed_Through := Parsed.Through_Date;
         Opts.Through_Source   := Explicit;
      else
         Opts.Observed_Through := Today;
         Opts.Through_Source   := Defaulted;
      end if;

      if Parsed.Has_Day then
         Opts.Selected_Day := Parsed.Day_Date;
         Opts.Day_Source   := Explicit;
      else
         Opts.Selected_Day := Opts.Observed_Through;
         Opts.Day_Source   := Defaulted;
      end if;

      return Opts;
   end Resolve_Home_Options;

   function Resolve_Home_Options
     (Parsed : Parsed_Home_Arguments) return Home_Options
   is
   begin
      if not Parsed.Has_Through then
         raise Program_Error with
           "cannot resolve temporal defaults without Today when --through is omitted";
      end if;

      return Resolve_Home_Options (Parsed, Parsed.Through_Date);
   end Resolve_Home_Options;

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
