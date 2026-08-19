with Ada.Command_Line;       use Ada.Command_Line;
with Ada.Directories;        use Ada.Directories;
with Ada.Environment_Variables;
with Ada.Strings.Unbounded;  use Ada.Strings.Unbounded;
with Ada.Calendar;
with Ada.Calendar.Formatting;
with Ada.Calendar.Time_Zones;
with HRA;
with HRA.Dates;
with HRA.Household;          use HRA.Household;
with HRA.Household_Check_Observation;
with HRA.Household_Report_Observation;
with HRA.Household_Home_Command;
with HRA.Render;             use HRA.Render;
with HRA.Recent_Journal_Render;
with HRA.Planned_Payments_Render;
with HRA.Envelope_Report_Render;
with HRA.Output;             use HRA.Output;

procedure HRA_Main is

   procedure Print_Help is
   begin
      Put_Line ("Usage: hra COMMAND [OPTIONS]");
      New_Line;
      Put_Line ("Commands:");
      Put_Line ("  home     Render the Household Home overview with calendar and day details");
      Put_Line ("           Options: [--base ROOT] [--through DATE] [--day DATE]");
      Put_Line ("  check    Validate the fixed 8-source topology, typed policy, and balance laws");
      Put_Line ("           Options: [--base ROOT]");
      Put_Line ("  report   Render the currently admitted Household report portfolio");
      Put_Line ("           Options: [--base ROOT]");
      Put_Line ("  version  Show version information");
      Put_Line ("  help     Show this help message");
      New_Line;
      Put_Line ("Household root precedence:");
      Put_Line ("  --base, LEDGER_DATA_DIR, HKERNEL_LEDGER_DATA_DIR, ./ledger-data, .");
      New_Line;
      Put_Line
        ("WARNING: daily-flow, monthly-accounts, and presentation policy are " &
         "not yet fully applied; report output is not canonical.");
   end Print_Help;

   function Resolve_Household_Root (Explicit_Base : String := "") return String is
   begin
      if Explicit_Base'Length > 0 then
         return Explicit_Base;
      end if;

      if Ada.Environment_Variables.Exists ("LEDGER_DATA_DIR") then
         return Ada.Environment_Variables.Value ("LEDGER_DATA_DIR");
      elsif Ada.Environment_Variables.Exists ("HKERNEL_LEDGER_DATA_DIR") then
         return Ada.Environment_Variables.Value ("HKERNEL_LEDGER_DATA_DIR");
      end if;

      if Exists ("ledger-data") and then Kind ("ledger-data") = Directory then
         return "ledger-data";
      else
         return ".";
      end if;
   end Resolve_Household_Root;

   function Local_Today return HRA.Dates.Date is
      Now_Time : constant Ada.Calendar.Time := Ada.Calendar.Clock;
      Offset   : constant Ada.Calendar.Time_Zones.Time_Offset :=
        Ada.Calendar.Time_Zones.Local_Time_Offset (Now_Time);
      Stamp    : constant String :=
        Ada.Calendar.Formatting.Image (Now_Time, Time_Zone => Offset);
      Date_Str : constant String := Stamp (Stamp'First .. Stamp'First + 9);
      D        : HRA.Dates.Date;
      Status   : HRA.Dates.Date_Status;
   begin
      if not HRA.Dates.Parse (Date_Str, D, Status) then
         raise Program_Error with "failed to parse system clock date: " & Date_Str;
      end if;
      return D;
   end Local_Today;

begin
   if Argument_Count = 0 then
      Put_Line ("HRA: Double-Entry Accounting Kernel (Ada 2022)");
      Put_Line ("Version: " & HRA.Version);
      New_Line;
      Print_Help;
      return;
   end if;

   declare
      Cmd : constant String := Argument (1);
   begin
      if Cmd = "version" or Cmd = "-v" or Cmd = "--version" then
         Put_Line ("hra " & HRA.Version);
      elsif Cmd = "help" or Cmd = "-h" or Cmd = "--help" then
         Print_Help;
      elsif Cmd = "home" then
         declare
            use HRA.Household_Home_Command;
            Arg_Count : constant Natural := Argument_Count - 1;
            Args      : String_Array (1 .. Arg_Count);
         begin
            for I in 1 .. Arg_Count loop
               Args (I) := To_Unbounded_String (Argument (I + 1));
            end loop;

            declare
               Parse_Res : constant Parse_Resolution :=
                 Parse_Arguments (Args);
            begin
               if Parse_Res.Status /= HRA.Household_Home_Command.Success then
                  Put_Line ("Error: " & To_String (Parse_Res.Message));
                  Set_Exit_Status (Failure);
                  return;
               end if;

               declare
                  Options : constant Home_Options :=
                    (if Needs_Clock (Parse_Res.Parsed)
                     then Resolve_Home_Options (Parse_Res.Parsed, Local_Today)
                     else Resolve_Home_Options (Parse_Res.Parsed));
                  Root_Dir : constant String :=
                    Resolve_Household_Root (To_String (Options.Base_Directory));
                  State    : Household_State;
                  Err      : Unbounded_String;
               begin
                  if not Load_Canonical_Household (Root_Dir, State, Err) then
                     Put_Line
                       ("Error loading canonical household from " & Root_Dir &
                        ": " & To_String (Err));
                     Set_Exit_Status (Failure);
                     return;
                  end if;

                  Put
                    (Execute_Home
                       (State,
                        Options.Observed_Through,
                        Options.Selected_Day));
               end;
            end;
         end;
      elsif Cmd = "check" or Cmd = "report" then
         declare
            Explicit_Base : Unbounded_String := Null_Unbounded_String;
            I             : Positive := 2;
         begin
            while I <= Argument_Count loop
               declare
                  Arg : constant String := Argument (I);
               begin
                  if Arg = "--base" then
                     if I + 1 > Argument_Count then
                        Put_Line ("Error: missing value for option --base");
                        Set_Exit_Status (Failure);
                        return;
                     end if;
                     Explicit_Base := To_Unbounded_String (Argument (I + 1));
                     I := I + 2;
                  else
                     Put_Line ("Error: unknown option for " & Cmd & ": " & Arg);
                     Set_Exit_Status (Failure);
                     return;
                  end if;
               end;
            end loop;

            declare
               Root_Dir : constant String :=
                 Resolve_Household_Root (To_String (Explicit_Base));
               State    : Household_State;
               Err      : Unbounded_String;
            begin
               if not Load_Canonical_Household (Root_Dir, State, Err) then
                  Put_Line
                    ("Error loading canonical household from " & Root_Dir &
                     ": " & To_String (Err));
                  Set_Exit_Status (Failure);
                  return;
               end if;

               if Cmd = "check" then
                  declare
                     Check_Obs : constant HRA.Household_Check_Observation.Observation :=
                       HRA.Household_Check_Observation.Observe (State);
                  begin
                     Put_Line
                       ("SUCCESS: Fixed 8-source topology and currently supported " &
                        "admissions verified for " & Root_Dir);
                     Put_Line
                       ("  Configuration       : typed budget, household, and report policy admitted");
                     Put_Line
                       ("  Actual Transactions : " & Natural'Image (Check_Obs.Actual_Transactions));
                     Put_Line
                       ("  Plan Transactions   : " & Natural'Image (Check_Obs.Plan_Transactions));
                     Put_Line
                       ("  Budget Transactions : " & Natural'Image (Check_Obs.Budget_Transactions));
                     Put_Line
                       ("  Registered Accounts : " & Natural'Image (Check_Obs.Registered_Accounts));
                     Put_Line
                       ("  Open Issues         : " & Natural'Image (Check_Obs.Open_Issues));
                  end;
               elsif Cmd = "report" then
                  declare
                     Report_Day    : constant HRA.Dates.Date := Local_Today;
                     Household_Obs : HRA.Household_Report_Observation.Report_Observation;
                  begin
                     if not HRA.Household_Report_Observation.Observe
                       (Report_Day, State, Household_Obs, Err)
                     then
                        Put_Line
                          ("Error observing Household report state: " & To_String (Err));
                        Set_Exit_Status (Failure);
                        return;
                     end if;

                     Put_Line
                       ("WARNING: daily-flow, monthly-accounts, and presentation " &
                        "policy remain partial; this report book is not canonical.");
                     Put_Line ("==================================================");
                     Put_Line ("   HRA Household Reports");
                     Put_Line ("   Canonical Root: " & Root_Dir);
                     Put_Line ("==================================================");
                     New_Line;

                     for Section of Household_Obs.Section_Order loop
                        case Section is
                           when HRA.Household_Report_Observation.Envelope_And_Backing_Section =>
                              Put
                                (HRA.Envelope_Report_Render.Render
                                   (Household_Obs.Envelope_Report));
                           when HRA.Household_Report_Observation.Account_Balances_Section =>
                              Put
                                (Render_Account_Balances
                                   (Household_Obs.Account_Balances));
                           when HRA.Household_Report_Observation.Balance_Sheet_Section =>
                              Put
                                (Render_Balance_Sheet
                                   (Household_Obs.Balance_Sheet));
                           when HRA.Household_Report_Observation.Profit_And_Loss_Section =>
                              Put
                                (Render_Profit_And_Loss
                                   (Household_Obs.Profit_And_Loss));
                           when HRA.Household_Report_Observation.Recent_Journal_Section =>
                              Put
                                (HRA.Recent_Journal_Render.Render
                                   (Household_Obs.Recent_Journal));
                           when HRA.Household_Report_Observation.Planned_Payments_Section =>
                              Put
                                (HRA.Planned_Payments_Render.Render
                                   (Household_Obs.Planned_Payments));
                           when HRA.Household_Report_Observation.Open_Issues_Section =>
                              Put (Render_Household_Issues (Household_Obs.Open_Issues));
                        end case;
                        New_Line;
                     end loop;
                  end;
               end if;
            end;
         end;
      else
         Put_Line ("Unknown command: " & Cmd);
         Set_Exit_Status (Failure);
      end if;
   end;
end HRA_Main;
