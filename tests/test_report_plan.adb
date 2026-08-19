with Ada.Text_IO;          use Ada.Text_IO;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA.Dates;
with HRA.Journal;       use HRA.Journal;
with HRA.Ledger;        use HRA.Ledger;
with HRA.Report_Config;
with HRA.Report_Plan;   use HRA.Report_Plan;
with HRA.Config_Support;

procedure Test_Report_Plan is
   Passed_Count : Natural := 0;
   Failed_Count : Natural := 0;

   procedure Assert (Condition : Boolean; Test_Name : String) is
   begin
      if Condition then
         Put_Line ("[PASS] " & Test_Name);
         Passed_Count := Passed_Count + 1;
      else
         Put_Line ("[FAIL] " & Test_Name);
         Failed_Count := Failed_Count + 1;
      end if;
   end Assert;

   function D (S : String) return HRA.Dates.Date is
      Val    : HRA.Dates.Date;
      Status : HRA.Dates.Date_Status;
   begin
      if not HRA.Dates.Parse (S, Val, Status) then
         raise Program_Error with "Invalid date in test: " & S;
      end if;
      return Val;
   end D;

   Journal_Text : constant String :=
     "2026-06-10 First" & ASCII.LF &
     "    expenses:food       100 JPY" & ASCII.LF &
     "    assets:cash        -100 JPY" & ASCII.LF &
     "" & ASCII.LF &
     "2026-07-20 Second" & ASCII.LF &
     "    expenses:food       200 JPY" & ASCII.LF &
     "    assets:cash        -200 JPY" & ASCII.LF;

   Report_Text : constant String :=
     "[reports.trial-balance]" & ASCII.LF &
     "as-of = ""latest""" & ASCII.LF &
     "[reports.balance-sheet]" & ASCII.LF &
     "as-of = ""latest""" & ASCII.LF &
     "[reports.profit-and-loss]" & ASCII.LF &
     "from = ""beginning""" & ASCII.LF &
     "through = ""latest""" & ASCII.LF &
     "[reports.daily-flow]" & ASCII.LF &
     "from = ""beginning""" & ASCII.LF &
     "through = ""latest""" & ASCII.LF &
     "max-date-columns = 14" & ASCII.LF &
     "[reports.monthly-accounts]" & ASCII.LF &
     "from = ""beginning""" & ASCII.LF &
     "through = ""latest""" & ASCII.LF &
     "[reports.recent-transactions]" & ASCII.LF &
     "through = ""latest""" & ASCII.LF &
     "count = 7" & ASCII.LF;

   Symbolic_Report_Text : constant String :=
     "[reports.trial-balance]" & ASCII.LF &
     "as-of = ""latest""" & ASCII.LF &
     "[reports.balance-sheet]" & ASCII.LF &
     "as-of = ""latest""" & ASCII.LF &
     "[reports.profit-and-loss]" & ASCII.LF &
     "range = ""current-cycle-to-date""" & ASCII.LF &
     "[reports.daily-flow]" & ASCII.LF &
     "range = ""current-cycle-to-date""" & ASCII.LF &
     "max-date-columns = 7" & ASCII.LF &
     "[reports.monthly-accounts]" & ASCII.LF &
     "from = ""beginning""" & ASCII.LF &
     "through = ""latest""" & ASCII.LF &
     "[reports.recent-transactions]" & ASCII.LF &
     "through = ""latest""" & ASCII.LF &
     "count = 5" & ASCII.LF;

   Mixed_Report_Text : constant String :=
     "[reports.trial-balance]" & ASCII.LF &
     "as-of = ""latest""" & ASCII.LF &
     "[reports.balance-sheet]" & ASCII.LF &
     "as-of = ""latest""" & ASCII.LF &
     "[reports.profit-and-loss]" & ASCII.LF &
     "range = ""current-cycle-to-date""" & ASCII.LF &
     "from = ""2026-08-01""" & ASCII.LF &
     "through = ""latest""" & ASCII.LF &
     "[reports.daily-flow]" & ASCII.LF &
     "range = ""current-cycle-to-date""" & ASCII.LF &
     "[reports.monthly-accounts]" & ASCII.LF &
     "from = ""beginning""" & ASCII.LF &
     "through = ""latest""" & ASCII.LF &
     "[reports.recent-transactions]" & ASCII.LF &
     "through = ""latest""" & ASCII.LF &
     "count = 5" & ASCII.LF;

   Monthly_Symbolic_Text : constant String :=
     "[reports.trial-balance]" & ASCII.LF &
     "as-of = ""latest""" & ASCII.LF &
     "[reports.balance-sheet]" & ASCII.LF &
     "as-of = ""latest""" & ASCII.LF &
     "[reports.profit-and-loss]" & ASCII.LF &
     "range = ""current-cycle-to-date""" & ASCII.LF &
     "[reports.daily-flow]" & ASCII.LF &
     "range = ""current-cycle-to-date""" & ASCII.LF &
     "[reports.monthly-accounts]" & ASCII.LF &
     "range = ""current-cycle-to-date""" & ASCII.LF &
     "[reports.recent-transactions]" & ASCII.LF &
     "through = ""latest""" & ASCII.LF &
     "count = 5" & ASCII.LF;

   L      : HRA.Ledger.Ledger;
   Err    : Unbounded_String;
   Config : HRA.Report_Config.Report_Configuration;
   Diag   : HRA.Config_Support.Config_Diagnostic;
   Result : Resolved_Report_Plan;
   Status : Resolve_Status;

begin
   Put_Line ("--- Testing HRA.Report_Plan ---");

   Assert
     (Parse_Journal_Text (Journal_Text, L, Err),
      "Setup: parse dated journal");
   Assert
     (HRA.Report_Config.Parse_Report_Configuration
        (Report_Text, Config, Diag),
      "Setup: parse symbolic boundary report plan");

   Assert
     (Resolve (D ("2026-08-15"), L, Config.Plan, Result, Status),
      "Resolve explicit-range report plan");
   Assert
     (HRA.Dates.Image (Result.Trial_Balance_As_Of) = "2026-08-15"
        and then HRA.Dates.Image (Result.Balance_Sheet_As_Of) = "2026-08-15",
      "latest resolves to application date");
   Assert
     (HRA.Dates.Image (HRA.Dates.First (Result.Profit_And_Loss)) = "2026-06-10"
        and then HRA.Dates.Image (HRA.Dates.Last (Result.Profit_And_Loss)) = "2026-08-15",
      "beginning resolves to earliest transaction through end date");
   Assert
     (HRA.Dates.Image (Result.Recent_Transactions_Through) = "2026-08-15"
        and then Result.Recent_Transactions_Count = 7,
      "recent report keeps resolved through date and configured count");

   Config.Plan.Balance_Sheet.Value :=
     (Kind  => HRA.Report_Config.Exact_Date,
      Value => D ("2026-07-31"));
   Assert
     (Resolve (D ("2026-08-15"), L, Config.Plan, Result, Status)
        and then HRA.Dates.Image (Result.Balance_Sheet_As_Of) = "2026-07-31",
      "exact as-of date survives resolution");

   Config.Plan.Profit_And_Loss.From :=
     (Kind  => HRA.Report_Config.Exact_Date,
      Value => D ("2026-09-01"));
   Assert
     (not Resolve (D ("2026-08-15"), L, Config.Plan, Result, Status)
        and then Status = Invalid_Profit_And_Loss_Range,
      "reject resolved range whose start is after through date");

   declare
      Symbolic_Config : HRA.Report_Config.Report_Configuration;
      Cycle           : HRA.Dates.Half_Open_Period;
      Symbolic_Result : Resolved_Report_Plan;
      Symbolic_Status : Resolve_Status;
   begin
      Assert
        (HRA.Report_Config.Parse_Report_Configuration
           (Symbolic_Report_Text, Symbolic_Config, Diag),
         "Admit current-cycle-to-date for P&L and Daily Flow");
      Assert
        (Needs_Current_Cycle (Symbolic_Config.Plan),
         "Symbolic report plan declares current Cycle dependency");
      Assert
        (not Resolve
           (D ("2026-08-15"), L, Symbolic_Config.Plan,
            Symbolic_Result, Symbolic_Status)
           and then Symbolic_Status = Current_Cycle_Context_Required,
         "Pure Journal resolution fails closed without current Cycle context");
      Assert
        (HRA.Dates.Make_Half_Open_Period
           (D ("2026-08-01"), D ("2026-09-01"), Cycle),
         "Setup: make current Cycle period");
      Assert
        (Resolve_With_Current_Cycle
           (D ("2026-08-15"), L, Cycle, Symbolic_Config.Plan,
            Symbolic_Result, Symbolic_Status),
         "Resolve current-cycle-to-date with typed Period context");
      Assert
        (HRA.Dates.Image
           (HRA.Dates.First (Symbolic_Result.Profit_And_Loss)) = "2026-08-01"
           and then HRA.Dates.Image
             (HRA.Dates.Last (Symbolic_Result.Profit_And_Loss)) = "2026-08-15"
           and then HRA.Dates.Image
             (HRA.Dates.First (Symbolic_Result.Daily_Flow)) = "2026-08-01"
           and then HRA.Dates.Image
             (HRA.Dates.Last (Symbolic_Result.Daily_Flow)) = "2026-08-15",
         "Current Cycle start through observation resolves both daily ranges");
      Assert
        (not Resolve_With_Current_Cycle
           (D ("2026-09-01"), L, Cycle, Symbolic_Config.Plan,
            Symbolic_Result, Symbolic_Status)
           and then Symbolic_Status = Current_Cycle_Observation_Outside_Period,
         "Reject observation at half-open current Cycle limit");
   end;

   declare
      Rejected : HRA.Report_Config.Report_Configuration;
   begin
      Assert
        (not HRA.Report_Config.Parse_Report_Configuration
           (Mixed_Report_Text, Rejected, Diag),
         "Reject symbolic range mixed with from/through");
      Assert
        (not HRA.Report_Config.Parse_Report_Configuration
           (Monthly_Symbolic_Text, Rejected, Diag),
         "Monthly Accounts remains explicit-range only");
   end;

   Put_Line
     (Natural'Image (Passed_Count) & " passed, " &
      Natural'Image (Failed_Count) & " failed");

   if Failed_Count > 0 then
      raise Program_Error with "report plan tests failed";
   end if;
end Test_Report_Plan;
