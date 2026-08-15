with Ada.Command_Line;       use Ada.Command_Line;
with Ada.Directories;        use Ada.Directories;
with Ada.Environment_Variables;
with Ada.Strings.Unbounded;  use Ada.Strings.Unbounded;
with Ada.Calendar;
with Ada.Calendar.Formatting;
with ALedger;
with ALedger.Account;        use ALedger.Account;
with ALedger.Ledger;         use ALedger.Ledger;
with ALedger.Household;      use ALedger.Household;
with ALedger.Render;         use ALedger.Render;
with ALedger.Report_Plan;    use ALedger.Report_Plan;
with ALedger.Planned_Payments;
with ALedger.Planned_Payments_Render;
with ALedger.Canonical_Source;
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
      Put_Line ("  report   Render P&L, Balance Sheet, Planned Payments, open Issues, and Budget status");
      Put_Line ("  tui      Launch the experimental native terminal UI");
      Put_Line ("  version  Show version information");
      Put_Line ("  help     Show this help message");
      New_Line;
      Put_Line ("Household root precedence:");
      Put_Line ("  --base, LEDGER_DATA_DIR, HKERNEL_LEDGER_DATA_DIR, ./ledger-data, .");
      New_Line;
      Put_Line ("WARNING: report policy is not yet fully applied; report output is not canonical.");
   end Print_Help;

   function Resolve_Household_Root return String is
   begin
      --  1. Check command line arguments for --base <path>
      if Argument_Count >= 2 then
         for I in 1 .. Argument_Count - 1 loop
            if Argument (I) = "--base" then
               return Argument (I + 1);
            end if;
         end loop;
      end if;

      --  2. Check environment variable LEDGER_DATA_DIR or HKERNEL_LEDGER_DATA_DIR
      if Ada.Environment_Variables.Exists ("LEDGER_DATA_DIR") then
         return Ada.Environment_Variables.Value ("LEDGER_DATA_DIR");
      elsif Ada.Environment_Variables.Exists ("HKERNEL_LEDGER_DATA_DIR") then
         return Ada.Environment_Variables.Value ("HKERNEL_LEDGER_DATA_DIR");
      end if;

      --  3. Default to current working directory or ./ledger-data
      if Exists ("ledger-data") and then Kind ("ledger-data") = Directory then
         return "ledger-data";
      else
         return ".";
      end if;
   end Resolve_Household_Root;

   function Local_Today return String is
      Stamp : constant String :=
        Ada.Calendar.Formatting.Image (Ada.Calendar.Clock);
   begin
      return Stamp (Stamp'First .. Stamp'First + 9);
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
                  Report_Day   : constant String := Local_Today;
                  Plan         : Resolved_Report_Plan;
                  Status       : Resolve_Status;
                  Payments     : ALedger.Planned_Payments.Observation;
                  Payment_Diag : ALedger.Planned_Payments.Admission_Diagnostic;
               begin
                  if not Resolve
                    (Report_Day,
                     State.Combined_Ledger,
                     State.Report_Policy.Plan,
                     Plan,
                     Status)
                  then
                     Put_Line
                       ("Error resolving report.toml query plan: " &
                        Resolve_Status'Image (Status));
                     Set_Exit_Status (Failure);
                     return;
                  end if;

                  if not ALedger.Planned_Payments.Observe
                    (State.Plan_Ledger,
                     ALedger.Canonical_Source.Text_For
                       (State.Sources, ALedger.Canonical_Source.Plan_Source),
                     State.Actual_Ledger,
                     ALedger.Canonical_Source.Text_For
                       (State.Sources, ALedger.Canonical_Source.Actual_Source),
                     State.Registry,
                     Report_Day,
                     Payments,
                     Payment_Diag)
                  then
                     Put_Line
                       ("Error observing Planned Payments: " &
                        ALedger.Planned_Payments.Admission_Status'Image
                          (Payment_Diag.Status) &
                        (if Length (Payment_Diag.Message) > 0
                         then ": " & To_String (Payment_Diag.Message)
                         else ""));
                     Set_Exit_Status (Failure);
                     return;
                  end if;

                  Put_Line ("WARNING: report policy is only partially applied; this report is not canonical.");
                  Put_Line ("==================================================");
                  Put_Line ("   ALedger Financial Statements");
                  Put_Line ("   Canonical Root: " & Root_Dir);
                  Put_Line ("==================================================");
                  New_Line;
                  Put
                    (Render_Profit_And_Loss
                       (State.Combined_Ledger,
                        To_String (Plan.Profit_And_Loss.From_Date),
                        To_String (Plan.Profit_And_Loss.Through_Date)));
                  New_Line;
                  Put
                    (Render_Balance_Sheet
                       (State.Combined_Ledger,
                        To_String (Plan.Balance_Sheet_As_Of)));
                  New_Line;
                  Put (ALedger.Planned_Payments_Render.Render (Payments));
                  New_Line;
                  Put (Render_Household_Issues (State.Issues));
                  New_Line;
                  Put (Render_Budget_Status (State));
               end;
            end if;
         end;
      else
         Put_Line ("Unknown command: " & Cmd);
         Set_Exit_Status (Failure);
      end if;
   end;
end ALedger_Main;
