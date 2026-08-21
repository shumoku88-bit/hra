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
with HRA.Household_Home_TUI;
with HRA.Household_Temporal;
with HRA.Household_Envelope_Change;
with HRA.Household_Envelope_Cycle_Comparison;
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
      Put_Line ("  tui      Open the interactive Household Home terminal view");
      Put_Line ("           Options: [--base ROOT] [--through DATE] [--day DATE]");
      Put_Line ("  check    Validate the fixed 8-source topology, typed policy, and balance laws");
      Put_Line ("           Options: [--base ROOT]");
      Put_Line ("  report [book]");
      Put_Line ("           Render the admitted Household report book");
      Put_Line ("           Options: [--base ROOT] [--through DATE]");
      Put_Line ("  report envelope-change");
      Put_Line ("           Render same-cycle Envelope Change");
      Put_Line
        ("           Options: [--base ROOT] [--through DATE] " &
         "[--from cycle-start|previous-day|DATE]");
      Put_Line ("  report envelope-previous-cycle");
      Put_Line ("           Render aligned previous-cycle Envelope comparison");
      Put_Line ("           Options: [--base ROOT] [--through DATE]");
      Put_Line ("  version  Show version information");
      Put_Line ("  help     Show this help message");
      New_Line;
      Put_Line ("Household root precedence:");
      Put_Line ("  --base, LEDGER_DATA_DIR, HKERNEL_LEDGER_DATA_DIR, ./ledger-data, .");
      New_Line;
      Put_Line
        ("WARNING: presentation policy is not yet fully applied; " &
         "report output is not canonical.");
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
      elsif Cmd = "home" or else Cmd = "tui" then
         declare
            use HRA.Household_Home_Command;
            Arg_Count : constant Natural := Argument_Count - 1;
            Args      : String_Array (1 .. Arg_Count);
         begin
            for I in 1 .. Arg_Count loop
               Args (I) := To_Unbounded_String (Argument (I + 1));
            end loop;

            declare
               Parse_Res : constant Parse_Resolution := Parse_Arguments (Args);
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

                  if Cmd = "home" then
                     Put
                       (Execute_Home
                          (State,
                           Options.Observed_Through,
                           Options.Selected_Day));
                  else
                     HRA.Household_Home_TUI.Run
                       (State,
                        Options.Observed_Through,
                        Options.Selected_Day);
                  end if;
               end;
            end;
         end;
      elsif Cmd = "check" or Cmd = "report" then
         declare
            type Report_Mode is
              (Report_Book,
               Envelope_Change_Report,
               Envelope_Previous_Cycle_Report);

            Explicit_Base : Unbounded_String := Null_Unbounded_String;
            Through_Text  : Unbounded_String := Null_Unbounded_String;
            Change_From   : Unbounded_String := To_Unbounded_String ("cycle-start");
            Mode          : Report_Mode := Report_Book;
            I             : Positive := 2;
         begin
            if Cmd = "report"
              and then I <= Argument_Count
              and then Argument (I)'Length > 0
              and then Argument (I) (Argument (I)'First) /= '-'
            then
               declare
                  Name : constant String := Argument (I);
               begin
                  if Name = "book" then
                     Mode := Report_Book;
                  elsif Name = "envelope-change" then
                     Mode := Envelope_Change_Report;
                  elsif Name = "envelope-previous-cycle" then
                     Mode := Envelope_Previous_Cycle_Report;
                  else
                     Put_Line ("Error: unknown report: " & Name);
                     Set_Exit_Status (Failure);
                     return;
                  end if;
                  I := I + 1;
               end;
            end if;

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
                  elsif Cmd = "report" and then Arg = "--through" then
                     if I + 1 > Argument_Count then
                        Put_Line ("Error: missing value for option --through");
                        Set_Exit_Status (Failure);
                        return;
                     end if;
                     Through_Text := To_Unbounded_String (Argument (I + 1));
                     I := I + 2;
                  elsif Cmd = "report" and then Arg = "--from" then
                     if I + 1 > Argument_Count then
                        Put_Line ("Error: missing value for option --from");
                        Set_Exit_Status (Failure);
                        return;
                     end if;
                     Change_From := To_Unbounded_String (Argument (I + 1));
                     I := I + 2;
                  else
                     Put_Line ("Error: unknown option for " & Cmd & ": " & Arg);
                     Set_Exit_Status (Failure);
                     return;
                  end if;
               end;
            end loop;

            if Cmd = "check"
              and then (Length (Through_Text) > 0
                        or else To_String (Change_From) /= "cycle-start")
            then
               Put_Line ("Error: temporal report options are not valid for check");
               Set_Exit_Status (Failure);
               return;
            end if;

            if Cmd = "report"
              and then Mode /= Envelope_Change_Report
              and then To_String (Change_From) /= "cycle-start"
            then
               Put_Line ("Error: --from is valid only for report envelope-change");
               Set_Exit_Status (Failure);
               return;
            end if;

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
                       ("  Configuration        : typed envelope, household, and report policy admitted");
                     Put_Line
                       ("  Actual Transactions  : " & Natural'Image (Check_Obs.Actual_Transactions));
                     Put_Line
                       ("  Plan Transactions    : " & Natural'Image (Check_Obs.Plan_Transactions));
                     Put_Line
                       ("  Entitlement Movements: " & Natural'Image (Check_Obs.Entitlement_Movements));
                     Put_Line
                       ("  Registered Accounts  : " & Natural'Image (Check_Obs.Registered_Accounts));
                     Put_Line
                       ("  Open Issues          : " & Natural'Image (Check_Obs.Open_Issues));
                  end;
               elsif Cmd = "report" then
                  declare
                     Report_Day : HRA.Dates.Date := Local_Today;
                     Date_Status : HRA.Dates.Date_Status;
                  begin
                     if Length (Through_Text) > 0
                       and then not HRA.Dates.Parse
                         (To_String (Through_Text), Report_Day, Date_Status)
                     then
                        Put_Line
                          ("Error: invalid --through date: " &
                           To_String (Through_Text));
                        Set_Exit_Status (Failure);
                        return;
                     end if;

                     case Mode is
                        when Report_Book =>
                           declare
                              Household_Obs :
                                HRA.Household_Report_Observation.Report_Observation;
                           begin
                              if not HRA.Household_Report_Observation.Observe
                                (Report_Day, State, Household_Obs, Err)
                              then
                                 Put_Line
                                   ("Error observing Household report state: " &
                                    To_String (Err));
                                 Set_Exit_Status (Failure);
                                 return;
                              end if;

                              Put_Line
                                ("WARNING: presentation policy remains partial; " &
                                 "this report book is not canonical.");
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
                                    when HRA.Household_Report_Observation.Daily_Flow_Section =>
                                       Put (Render_Daily_Flow (Household_Obs.Daily_Flow));
                                    when HRA.Household_Report_Observation.Monthly_Accounts_Section =>
                                       Put
                                         (Render_Monthly_Accounts
                                            (Household_Obs.Monthly_Accounts));
                                    when HRA.Household_Report_Observation.Recent_Journal_Section =>
                                       Put
                                         (HRA.Recent_Journal_Render.Render
                                            (Household_Obs.Recent_Journal));
                                    when HRA.Household_Report_Observation.Planned_Payments_Section =>
                                       Put
                                         (HRA.Planned_Payments_Render.Render
                                            (Household_Obs.Planned_Payments));
                                    when HRA.Household_Report_Observation.Open_Issues_Section =>
                                       Put
                                         (Render_Household_Issues
                                            (Household_Obs.Open_Issues));
                                 end case;
                                 New_Line;
                              end loop;
                           end;

                        when Envelope_Change_Report =>
                           declare
                              procedure Render_Change
                                (Baseline : HRA.Household_Envelope_Change.Baseline_Request)
                              is
                                 Change : HRA.Household_Envelope_Change.Change_Observation;
                                 Diag : HRA.Household_Temporal.Observe_Diagnostic;
                                 Previous : constant
                                   HRA.Household_Envelope_Change.Previous_Observation_Context :=
                                     (Kind => HRA.Household_Envelope_Change.No_Previous_Observation);
                              begin
                                 if not HRA.Household_Temporal.Observe_Envelope_Change
                                   (Report_Day, Previous, Baseline, State, Change, Diag)
                                 then
                                    Put_Line
                                      ("Error observing Envelope Change: " &
                                       HRA.Household_Temporal.Observe_Status'Image
                                         (Diag.Status));
                                    Set_Exit_Status (Failure);
                                 else
                                    Put (HRA.Envelope_Report_Render.Render (Change));
                                 end if;
                              end Render_Change;

                              From_Text   : constant String := To_String (Change_From);
                              From_Day    : HRA.Dates.Date;
                              From_Status : HRA.Dates.Date_Status;
                           begin
                              if From_Text = "cycle-start" then
                                 Render_Change
                                   ((Kind => HRA.Household_Envelope_Change.Cycle_Start));
                              elsif From_Text = "previous-day" then
                                 Render_Change
                                   ((Kind => HRA.Household_Envelope_Change.Previous_Day));
                              elsif HRA.Dates.Parse (From_Text, From_Day, From_Status) then
                                 Render_Change
                                   ((Kind          => HRA.Household_Envelope_Change.Explicit_Day,
                                     Requested_Day => From_Day));
                              else
                                 Put_Line
                                   ("Error: invalid --from value: " & From_Text &
                                    " (expected cycle-start, previous-day, or YYYY-MM-DD)");
                                 Set_Exit_Status (Failure);
                              end if;
                           end;

                        when Envelope_Previous_Cycle_Report =>
                           declare
                              Comparison :
                                HRA.Household_Envelope_Cycle_Comparison.Comparison_Observation;
                              Diag : HRA.Household_Temporal.Cycle_Comparison_View_Diagnostic;
                           begin
                              if not HRA.Household_Temporal.Observe_Envelope_Aligned_Previous_Cycle
                                (Report_Day, State, Comparison, Diag)
                              then
                                 Put_Line
                                   ("Error observing aligned previous-cycle Envelope report: " &
                                    HRA.Household_Temporal.Cycle_Comparison_View_Status'Image
                                      (Diag.Status));
                                 Set_Exit_Status (Failure);
                              else
                                 Put (HRA.Envelope_Report_Render.Render (Comparison));
                              end if;
                           end;
                     end case;
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
