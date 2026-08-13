with Ada.Text_IO;          use Ada.Text_IO;
with Ada.Command_Line;       use Ada.Command_Line;
with Ada.Directories;        use Ada.Directories;
with Ada.Environment_Variables;
with Ada.Strings.Unbounded;  use Ada.Strings.Unbounded;
with ALedger;
with ALedger.Money;          use ALedger.Money;
with ALedger.Account;        use ALedger.Account;
with ALedger.Ledger;         use ALedger.Ledger;
with ALedger.Household;      use ALedger.Household;
with ALedger.Report;         use ALedger.Report;
with ALedger.Render;         use ALedger.Render;
with ALedger.Issues;         use ALedger.Issues;
with ALedger.TUI;            use ALedger.TUI;

procedure ALedger_Main is

   function Resolve_Household_Root return String is
   begin
      --  1. Check command line arguments for --base <path>
      if Argument_Count >= 3 and then Argument (2) = "--base" then
         return Argument (3);
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

begin
   if Argument_Count = 0 then
      Put_Line ("ALedger: Double-Entry Accounting Kernel (Ada 2012)");
      Put_Line ("Version: " & ALedger.Version);
      New_Line;
      Put_Line ("Usage: aledger [command] [options]");
      Put_Line ("  tui [--base <dir>]      Launch native interactive Terminal UI");
      Put_Line ("  check [--base <dir>]    Validate canonical household sources & balance laws");
      Put_Line ("  report [--base <dir>]   Generate P&L, Balance Sheet, Trial Balance, Envelope & Issues");
      Put_Line ("  version                 Show version information");
      Put_Line ("  help                    Show this help message");
      return;
   end if;

   declare
      Cmd      : constant String := Argument (1);
      Root_Dir : constant String := Resolve_Household_Root;
   begin
      if Cmd = "version" then
         Put_Line ("aledger " & ALedger.Version);
      elsif Cmd = "help" then
         Put_Line ("Usage: aledger [command] [--base <household_root_dir>]");
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
               Put_Line ("SUCCESS: Canonical household topology & balance laws verified for " & Root_Dir);
               Put_Line ("  Actual Transactions : " & Natural'Image (Natural (State.Actual_Ledger.Transactions.Length)));
               Put_Line ("  Plan Transactions   : " & Natural'Image (Natural (State.Plan_Ledger.Transactions.Length)));
               Put_Line ("  Budget Transactions : " & Natural'Image (Natural (State.Budget_Ledger.Transactions.Length)));
               Put_Line ("  Registered Accounts : " & Natural'Image (Declarations (State.Registry)'Length));
               Put_Line ("  Open Issues         : " & Natural'Image (Natural (Open_Issues (State.Issues).Length)));
            elsif Cmd = "report" then
               declare
                  PL : constant Profit_And_Loss := Generate_Profit_And_Loss (State.Combined_Ledger);
                  BS : constant Balance_Sheet := Generate_Balance_Sheet (State.Combined_Ledger);
                  TB : constant Trial_Balance := Generate_Trial_Balance (State.Combined_Ledger);
               begin
                  Put_Line ("==================================================");
                  Put_Line ("   ALedger Financial Statements");
                  Put_Line ("   Canonical Root: " & Root_Dir);
                  Put_Line ("==================================================");
                  New_Line;
                  Put_Line ("--- Profit and Loss Statement ---");
                  Put_Line ("  Total Income   : " & Render_Quantity (Lookup_Balance (PL.Total_Income, Make_Commodity ("JPY"))));
                  Put_Line ("  Total Expenses : " & Render_Quantity (Lookup_Balance (PL.Total_Expenses, Make_Commodity ("JPY"))));
                  Put_Line ("  Net Income     : " & Render_Quantity (Lookup_Balance (PL.Net_Income, Make_Commodity ("JPY"))));
                  New_Line;
                  Put_Line ("--- Balance Sheet ---");
                  Put_Line ("  Total Assets      : " & Render_Quantity (Lookup_Balance (BS.Total_Assets, Make_Commodity ("JPY"))));
                  Put_Line ("  Total Liabilities : " & Render_Quantity (Lookup_Balance (BS.Total_Liabilities, Make_Commodity ("JPY"))));
                  Put_Line ("  Total Equity      : " & Render_Quantity (Lookup_Balance (BS.Total_Equity, Make_Commodity ("JPY"))));
                  Put_Line ("  Accounting Delta  : " & Render_Quantity (Lookup_Balance (BS.Accounting_Equation_Delta, Make_Commodity ("JPY"))));
                  New_Line;
                  Put_Line ("--- Trial Balance Total ---");
                  Put_Line ("  Trial Balance Sum : " & Render_Quantity (Lookup_Balance (TB.Total, Make_Commodity ("JPY"))));
                  New_Line;
                  Put (Render_Household_Issues (State.Issues));
                  New_Line;
                  Put (Render_Budget_Status (State.Combined_Ledger));
               end;
            end if;
         end;
      else
         Put_Line ("Unknown command: " & Cmd);
         Set_Exit_Status (Failure);
      end if;
   end;
end ALedger_Main;
