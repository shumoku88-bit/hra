with Ada.Command_Line;       use Ada.Command_Line;
with Ada.Directories;        use Ada.Directories;
with Ada.Environment_Variables;
with Ada.Strings.Unbounded;  use Ada.Strings.Unbounded;
with Ada.Calendar;
with Ada.Calendar.Formatting;
with Ada.Calendar.Time_Zones;
with ALedger;
with ALedger.Account;        use ALedger.Account;
with ALedger.Dates;
with ALedger.Ledger;         use ALedger.Ledger;
with ALedger.Household;      use ALedger.Household;
with ALedger.Household_Report_Observation;
with ALedger.Render;         use ALedger.Render;
with ALedger.Recent_Journal_Render;
with ALedger.Planned_Payments;
with ALedger.Planned_Payments_Render;
with ALedger.Envelope_Report_Render;
with ALedger.Issues;         use ALedger.Issues;
with ALedger.TUI;            use ALedger.TUI;
with ALedger.Output;         use ALedger.Output;

procedure ALedger_Main is

   procedure Print_Help is
   begin
      Put_Line ("Usage: aledger COMMAND [--base <household_root_dir>]");
      New_Line;
      Put_Line ("Commands:");
      Put_Line ("  check    Validate the fixed 8-source topology, typed policy, and balance laws");
      Put_Line ("  report   Render the currently admitted Household report portfolio");
      Put_Line ("  tui      Launch the experimental native terminal UI");
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

   function Resolve_Household_Root return String is
   begin
      if Argument_Count >= 2 then
         for I in 1 .. Argument_Count - 1 loop
            if Argument (I) = "--base" then
               return Argument (I + 1);
            end if;
         end loop;
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

   function Local_Today return ALedger.Dates.Date is
      Now_Time : constant Ada.Calendar.Time := Ada.Calendar.Clock;
      Offset   : constant Ada.Calendar.Time_Zones.Time_Offset :=
        Ada.Calendar.Time_Zones.Local_Time_Offset (Now_Time);
      Stamp    : constant String :=
        Ada.Calendar.Formatting.Image (Now_Time, Time_Zone => Offset);
      Date_Str : constant String := Stamp (Stamp'First .. Stamp'First + 9);
      D        : ALedger.Dates.Date;
      Status   : ALedger.Dates.Date_Status;
   begin
      if not ALedger.Dates.Parse (Date_Str, D, Status) then
         raise Program_Error with "failed to parse system clock date: " & Date_Str;
      end if;
      return D;
   end Local_Today;

begin
   if Argument_Count = 0 then
      Put_Line ("ALedger: Double-Entry Accounting Kernel (Ada 2022)");
      Put_Line ("Version: " & ALedger.Version);
      New_Line;
      Print_Help;
      return;
   end if;

   declare
      Cmd      : constant String := Argument (1);
      Root_Dir : constant String := Resolve_Household_Root;
   begin
      if Cmd = "version" then
         Put_Line ("aledger " & ALedger.Version);
      elsif Cmd = "help" then
         Print_Help;
      elsif Cmd = "tui" or Cmd = "check" or Cmd = "report" then
         declare
            State : Household_State;
            Err   : Unbounded_String;
         begin
            if not Load_Canonical_Household (Root_Dir, State, Err) then
               Put_Line ("Error loading canonical household from " & Root_Dir & ": " & To_String (Err));
               Set_Exit_Status (Failure);
               return;
            end if;

            if Cmd = "tui" then
               Run_Interactive_TUI (State);
            elsif Cmd = "check" then
               Put_Line ("SUCCESS: Fixed 8-source topology and currently supported admissions verified for " & Root_Dir);
               Put_Line ("  Configuration       : typed budget, household, and report policy admitted");
               Put_Line ("  Actual Transactions : " & Natural'Image (Natural (State.Actual_Ledger.Transactions.Length)));
               Put_Line ("  Plan Transactions   : " & Natural'Image (Natural (State.Plan_Ledger.Transactions.Length)));
               Put_Line ("  Budget Transactions : " & Natural'Image (Natural (State.Budget_Ledger.Transactions.Length)));
               Put_Line ("  Registered Accounts : " & Natural'Image (Declarations (State.Registry)'Length));
               Put_Line ("  Open Issues         : " & Natural'Image (Natural (Open_Issues (State.Issues).Length)));
            elsif Cmd = "report" then
               declare
                  Report_Day    : constant ALedger.Dates.Date := Local_Today;
                  Household_Obs : ALedger.Household_Report_Observation.Report_Observation;
                  Payments      : ALedger.Planned_Payments.Observation;
                  Payment_Diag  : ALedger.Planned_Payments.Admission_Diagnostic;
               begin
                  if not ALedger.Household_Report_Observation.Observe
                    (Report_Day, State, Household_Obs, Err)
                  then
                     Put_Line
                       ("Error observing Household report state: " & To_String (Err));
                     Set_Exit_Status (Failure);
                     return;
                  end if;

                  if not ALedger.Planned_Payments.Project
                    (Household_Obs.Open_Plans,
                     State.Registry,
                     Report_Day,
                     Payments,
                     Payment_Diag)
                  then
                     Put_Line
                       ("Error projecting Planned Payments: " &
                        ALedger.Planned_Payments.Admission_Status'Image
                          (Payment_Diag.Status) &
                        (if Length (Payment_Diag.Message) > 0
                         then ": " & To_String (Payment_Diag.Message)
                         else ""));
                     Set_Exit_Status (Failure);
                     return;
                  end if;

                  Put_Line
                    ("WARNING: daily-flow, monthly-accounts, and presentation " &
                     "policy remain partial; this report book is not canonical.");
                  Put_Line ("==================================================");
                  Put_Line ("   ALedger Household Reports");
                  Put_Line ("   Canonical Root: " & Root_Dir);
                  Put_Line ("==================================================");
                  New_Line;

                  --  Current renderable portfolio follows the shared report
                  --  order. Each section consumes an already admitted semantic
                  --  observation; no renderer selects source files or dates.
                  Put
                    (ALedger.Envelope_Report_Render.Render
                       (State, Household_Obs));
                  New_Line;
                  Put
                    (Render_Account_Balances
                       (State.Actual_Ledger,
                        Household_Obs.Query_Plan.Trial_Balance_As_Of));
                  New_Line;
                  Put
                    (Render_Balance_Sheet
                       (State.Actual_Ledger,
                        Household_Obs.Query_Plan.Balance_Sheet_As_Of));
                  New_Line;
                  Put
                    (Render_Profit_And_Loss
                       (State.Actual_Ledger,
                        Household_Obs.Query_Plan.Profit_And_Loss));
                  New_Line;
                  Put
                    (ALedger.Recent_Journal_Render.Render
                       (Household_Obs.Recent_Journal));
                  New_Line;
                  Put (ALedger.Planned_Payments_Render.Render (Payments));
                  New_Line;
                  Put (Render_Household_Issues (State.Issues));
               end;
            end if;
         end;
      else
         Put_Line ("Unknown command: " & Cmd);
         Set_Exit_Status (Failure);
      end if;
   end;
end ALedger_Main;
