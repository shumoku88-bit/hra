with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with Ada.Text_IO; use Ada.Text_IO;
with HRA.Account;
with HRA.Dates;
with HRA.Journal;
with HRA.Ledger;
with HRA.Money;
with HRA.Render;
with HRA.Report_Flow;

procedure Test_Report_Flow is
   use type HRA.Dates.Date;
   use type HRA.Money.Quantity;
   use type HRA.Report_Flow.Year_Month;

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

   function D (Text : String) return HRA.Dates.Date is
      Value  : HRA.Dates.Date;
      Status : HRA.Dates.Date_Status;
   begin
      if not HRA.Dates.Parse (Text, Value, Status) then
         raise Program_Error with "invalid test date: " & Text;
      end if;
      return Value;
   end D;

   function Period (First, Last : String) return HRA.Dates.Closed_Period is
      Result : HRA.Dates.Closed_Period;
   begin
      if not HRA.Dates.Make_Closed_Period (D (First), D (Last), Result) then
         raise Program_Error with "invalid test period";
      end if;
      return Result;
   end Period;

   function JPY (Value : HRA.Money.Balance) return HRA.Money.Quantity is
   begin
      return HRA.Money.Lookup_Balance
        (Value, HRA.Money.Make_Commodity ("JPY"));
   end JPY;

   Journal_Text : constant String :=
     "account assets:cash" & ASCII.LF &
     "  ; type: Asset" & ASCII.LF &
     "account income:salary" & ASCII.LF &
     "  ; type: Income" & ASCII.LF &
     "account expenses:food" & ASCII.LF &
     "  ; type: Expense" & ASCII.LF &
     "account expenses:rent" & ASCII.LF &
     "  ; type: Expense" & ASCII.LF & ASCII.LF &
     "2026-01-31 Salary" & ASCII.LF &
     "    assets:cash             100 JPY" & ASCII.LF &
     "    income:salary          -100 JPY" & ASCII.LF & ASCII.LF &
     "2026-02-01 Food" & ASCII.LF &
     "    expenses:food            20 JPY" & ASCII.LF &
     "    assets:cash             -20 JPY" & ASCII.LF & ASCII.LF &
     "2026-02-02 Food refund" & ASCII.LF &
     "    expenses:food            -5 JPY" & ASCII.LF &
     "    assets:cash               5 JPY" & ASCII.LF & ASCII.LF &
     "2026-02-10 Rent" & ASCII.LF &
     "    expenses:rent            40 JPY" & ASCII.LF &
     "    assets:cash             -40 JPY" & ASCII.LF & ASCII.LF &
     "2026-02-11 Move cash" & ASCII.LF &
     "    assets:cash              10 JPY" & ASCII.LF &
     "    assets:cash             -10 JPY" & ASCII.LF & ASCII.LF &
     "2026-03-01 After range salary" & ASCII.LF &
     "    assets:cash             500 JPY" & ASCII.LF &
     "    income:salary          -500 JPY" & ASCII.LF;

   L          : HRA.Ledger.Ledger;
   Parse_Diag : HRA.Journal.Parse_Diagnostic;
   Daily      : HRA.Report_Flow.Daily_Flow_Observation;
   Monthly    : HRA.Report_Flow.Monthly_Accounts_Observation;
   Flow_Diag  : HRA.Report_Flow.Observe_Diagnostic;
   Jan        : constant HRA.Report_Flow.Year_Month :=
     HRA.Report_Flow.Month_Of (D ("2026-01-01"));
   Feb        : constant HRA.Report_Flow.Year_Month :=
     HRA.Report_Flow.Month_Of (D ("2026-02-01"));

begin
   Put_Line ("--- Testing shared Daily/Monthly report flow ---");

   Assert
     (HRA.Journal.Parse_Journal_Text
        (Journal_Text, "flow.journal", L, Parse_Diag),
      "setup parses typed flow journal");

   Assert
     (HRA.Report_Flow.Observe
        (L,
         Period ("2026-01-31", "2026-02-02"),
         Period ("2026-01-15", "2026-02-20"),
         Daily,
         Monthly,
         Flow_Diag),
      "one observation builds Daily Flow and Monthly Accounts");

   Assert
     (Natural (Daily.Lines.Length) = 3
      and then Daily.Lines.Element (1).Day = D ("2026-01-31")
      and then Daily.Lines.Element (2).Day = D ("2026-02-01")
      and then Daily.Lines.Element (3).Day = D ("2026-02-02"),
      "Daily Flow publishes typed activity days in chronological order");
   Assert
     (JPY (Daily.Lines.Element (1).Income) = 100.0
      and then JPY (Daily.Lines.Element (1).Expenses) = 0.0
      and then JPY (HRA.Report_Flow.Net (Daily.Lines.Element (1))) = 100.0,
      "Income credit is sign-normalized to positive Daily income");
   Assert
     (JPY (Daily.Lines.Element (3).Expenses) = -5.0
      and then JPY (HRA.Report_Flow.Net (Daily.Lines.Element (3))) = 5.0,
      "Expense refund remains negative Expense and increases net flow");
   Assert
     (JPY (HRA.Report_Flow.Total_Income (Daily)) = 100.0
      and then JPY (HRA.Report_Flow.Total_Expenses (Daily)) = 15.0
      and then JPY (HRA.Report_Flow.Total_Net (Daily)) = 85.0,
      "Daily totals retain exact Income minus Expense law");
   Assert
     (Natural (Daily.Expense_Rows.Length) = 1
      and then HRA.Account.Name (Daily.Expense_Rows.Element (1).Acc) =
        "expenses:food"
      and then Natural (Daily.Expense_Rows.Element (1).Cells.Length) = 2,
      "Daily Account x Day detail retains only active Expense rows");

   Assert
     (Natural (Monthly.Months.Length) = 2
      and then Monthly.Months.Element (1) = Jan
      and then Monthly.Months.Element (2) = Feb,
      "Monthly Accounts retains every calendar month touched by period");
   Assert
     (Natural (Monthly.Income_Rows.Length) = 1
      and then HRA.Account.Name (Monthly.Income_Rows.Element (1).Acc) =
        "income:salary",
      "Monthly income rows follow declared Account identity");
   Assert
     (Natural (Monthly.Expense_Rows.Length) = 2
      and then HRA.Account.Name (Monthly.Expense_Rows.Element (1).Acc) =
        "expenses:food"
      and then HRA.Account.Name (Monthly.Expense_Rows.Element (2).Acc) =
        "expenses:rent",
      "Monthly Expense rows preserve declaration order");
   Assert
     (JPY (HRA.Report_Flow.Income_For (Monthly, Jan)) = 100.0
      and then JPY (HRA.Report_Flow.Expenses_For (Monthly, Jan)) = 0.0
      and then JPY (HRA.Report_Flow.Net_For (Monthly, Jan)) = 100.0,
      "partial starting month retains only in-period typed flow");
   Assert
     (JPY (HRA.Report_Flow.Income_For (Monthly, Feb)) = 0.0
      and then JPY (HRA.Report_Flow.Expenses_For (Monthly, Feb)) = 55.0
      and then JPY (HRA.Report_Flow.Net_For (Monthly, Feb)) = -55.0,
      "Monthly flow keeps refunds and later Expense activity exact");
   Assert
     (JPY (HRA.Report_Flow.Balance_For
        (Monthly.Expense_Rows.Element (1), Feb)) = 15.0,
      "Monthly Account cell preserves charge plus refund for one Expense");
   Assert
     (JPY (HRA.Report_Flow.Income_For (Monthly, Jan)) +
        JPY (HRA.Report_Flow.Income_For (Monthly, Feb)) = 100.0
      and then JPY (HRA.Report_Flow.Expenses_For (Monthly, Jan)) +
        JPY (HRA.Report_Flow.Expenses_For (Monthly, Feb)) = 55.0,
      "monthly grouping preserves period Income and Expense totals");

   declare
      Daily_Text   : constant String := HRA.Render.Render_Daily_Flow (Daily);
      Monthly_Text : constant String := HRA.Render.Render_Monthly_Accounts (Monthly);
   begin
      Assert
        (Index (Daily_Text, "== Daily Flow (Account x Day) ==") > 0
         and then Index (Daily_Text, "2026-02-02") > 0
         and then Index (Daily_Text, "expenses:food") > 0,
         "Daily renderer exposes typed day and Expense coordinates");
      Assert
        (Index (Daily_Text, "Date       |  Income | Expenses |      Net") > 0
         and then Index
           (Daily_Text, "2026-01-31 | 100 JPY |        0 |  100 JPY") > 0,
         "Daily header and body separators align with right-aligned numbers");
      Assert
        (Index (Monthly_Text, "== Monthly Accounts (Account x Month) ==") > 0
         and then Index (Monthly_Text, "2026-01") > 0
         and then Index (Monthly_Text, "2026-02") > 0
         and then Index (Monthly_Text, "expenses:rent") > 0,
         "Monthly renderer exposes explicit Account x Month coordinates");
      Assert
        (Index (Monthly_Text, "Month   |  Income | Expenses |      Net") > 0
         and then Index
           (Monthly_Text, "2026-01 | 100 JPY |        0 |  100 JPY") > 0,
         "Monthly header and body separators align with right-aligned numbers");
   end;

   Put_Line
     (Natural'Image (Passed_Count) & " passed, " &
      Natural'Image (Failed_Count) & " failed");
   if Failed_Count > 0 then
      raise Program_Error with "report flow tests failed";
   end if;
end Test_Report_Flow;
