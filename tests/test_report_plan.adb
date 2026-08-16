with Ada.Text_IO;          use Ada.Text_IO;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with ALedger.Dates;
with ALedger.Journal;       use ALedger.Journal;
with ALedger.Ledger;        use ALedger.Ledger;
with ALedger.Report_Config;
with ALedger.Report_Plan;   use ALedger.Report_Plan;
with ALedger.Config_Support;

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

   function D (S : String) return ALedger.Dates.Date is
      Val    : ALedger.Dates.Date;
      Status : ALedger.Dates.Date_Status;
   begin
      if not ALedger.Dates.Parse (S, Val, Status) then
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

   L      : ALedger.Ledger.Ledger;
   Err    : Unbounded_String;
   Config : ALedger.Report_Config.Report_Configuration;
   Diag   : ALedger.Config_Support.Config_Diagnostic;
   Result : Resolved_Report_Plan;
   Status : Resolve_Status;

begin
   Put_Line ("--- Testing ALedger.Report_Plan ---");

   Assert
     (Parse_Journal_Text (Journal_Text, L, Err),
      "Setup: parse dated journal");
   Assert
     (ALedger.Report_Config.Parse_Report_Configuration
        (Report_Text, Config, Diag),
      "Setup: parse symbolic report plan");

   Assert
     (Resolve (D ("2026-08-15"), L, Config.Plan, Result, Status),
      "Resolve symbolic report plan");
   Assert
     (ALedger.Dates.Image (Result.Trial_Balance_As_Of) = "2026-08-15"
        and then ALedger.Dates.Image (Result.Balance_Sheet_As_Of) = "2026-08-15",
      "latest resolves to application date");
   Assert
     (ALedger.Dates.Image (ALedger.Dates.First (Result.Profit_And_Loss)) = "2026-06-10"
        and then ALedger.Dates.Image (ALedger.Dates.Last (Result.Profit_And_Loss)) = "2026-08-15",
      "beginning resolves to earliest transaction through end date");
   Assert
     (ALedger.Dates.Image (Result.Recent_Transactions_Through) = "2026-08-15"
        and then Result.Recent_Transactions_Count = 7,
      "recent report keeps resolved through date and configured count");

   Config.Plan.Balance_Sheet.Value :=
     (Kind  => ALedger.Report_Config.Exact_Date,
      Value => D ("2026-07-31"));
   Assert
     (Resolve (D ("2026-08-15"), L, Config.Plan, Result, Status)
        and then ALedger.Dates.Image (Result.Balance_Sheet_As_Of) = "2026-07-31",
      "exact as-of date survives resolution");

   Config.Plan.Profit_And_Loss.From :=
     (Kind  => ALedger.Report_Config.Exact_Date,
      Value => D ("2026-09-01"));
   Assert
     (not Resolve (D ("2026-08-15"), L, Config.Plan, Result, Status)
        and then Status = Invalid_Profit_And_Loss_Range,
      "reject resolved range whose start is after through date");

   Put_Line
     (Natural'Image (Passed_Count) & " passed, " &
      Natural'Image (Failed_Count) & " failed");

   if Failed_Count > 0 then
      raise Program_Error with "report plan tests failed";
   end if;
end Test_Report_Plan;
