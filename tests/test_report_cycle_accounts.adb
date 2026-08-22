with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with Ada.Text_IO;       use Ada.Text_IO;
with HRA.Account;
with HRA.Cycle_Accounts_Observation;
with HRA.Cycle_Accounts_Render;
with HRA.Cycle_Observation;
with HRA.Dates;
with HRA.Journal;
with HRA.Ledger;
with HRA.Money;
with HRA.Report_Cycle_Accounts;
with HRA.Terminal_Layout;
with HRA.Terminal_UTF8;

procedure Test_Report_Cycle_Accounts is
   use type HRA.Dates.Date;
   use type HRA.Money.Quantity;
   use type HRA.Report_Cycle_Accounts.Comparison_Status;

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

   function Window (First, Limit : String)
      return HRA.Cycle_Observation.Cycle_Window
   is
      Result : HRA.Dates.Half_Open_Period;
   begin
      if not HRA.Dates.Make_Half_Open_Period
        (D (First), D (Limit), Result)
      then
         raise Program_Error with "invalid test cycle";
      end if;
      return Result;
   end Window;

   function U
     (Text : String;
      Code : HRA.Terminal_UTF8.Unicode_Code_Point) return String is
     (HRA.Terminal_UTF8.Append_Code_Point (Text, Code));

   Food_Account : constant String :=
     "expenses:" & U (U ("", 16#98DF#), 16#8CBB#);

   function Line_Containing (Text, Needle : String) return String is
      Match_At : constant Natural := Index (Text, Needle);
      Start_At : Natural := Match_At;
      Stop_At  : Natural;
   begin
      if Match_At = 0 then
         raise Program_Error with "missing rendered test line: " & Needle;
      end if;
      while Start_At > Text'First
        and then Text (Start_At - 1) /= ASCII.LF
      loop
         Start_At := Start_At - 1;
      end loop;
      Stop_At := Index (Text (Start_At .. Text'Last), String'(1 => ASCII.LF));
      if Stop_At = 0 then
         return Text (Start_At .. Text'Last);
      end if;
      return Text (Start_At .. Stop_At - 1);
   end Line_Containing;

   function Separator_Column
     (Text : String; Occurrence : Positive) return Natural
   is
      Seen : Natural := 0;
   begin
      for Index in Text'Range loop
         if Text (Index) = '|' then
            Seen := Seen + 1;
            if Seen = Occurrence then
               return HRA.Terminal_Layout.Display_Width
                 (Text (Text'First .. Index - 1));
            end if;
         end if;
      end loop;
      raise Program_Error with "missing rendered separator";
   end Separator_Column;

   function JPY (Value : HRA.Money.Balance) return HRA.Money.Quantity is
   begin
      return HRA.Money.Lookup_Balance
        (Value, HRA.Money.Make_Commodity ("JPY"));
   end JPY;

   function USD (Value : HRA.Money.Balance) return HRA.Money.Quantity is
   begin
      return HRA.Money.Lookup_Balance
        (Value, HRA.Money.Make_Commodity ("USD"));
   end USD;

   Journal_Text : constant String :=
     "account assets:cash" & ASCII.LF &
     "  ; type: Asset" & ASCII.LF &
     "account liabilities:card" & ASCII.LF &
     "  ; type: Liability" & ASCII.LF &
     "account equity:opening" & ASCII.LF &
     "  ; type: Equity" & ASCII.LF &
     "account income:salary" & ASCII.LF &
     "  ; type: Income" & ASCII.LF &
     "account " & Food_Account & ASCII.LF &
     "  ; type: Expense" & ASCII.LF & ASCII.LF &
     "2026-01-01 Previous salary" & ASCII.LF &
     "    assets:cash             100 JPY" & ASCII.LF &
     "    income:salary          -100 JPY" & ASCII.LF & ASCII.LF &
     "2026-01-02 Previous food" & ASCII.LF &
     "    " & Food_Account & "            20 JPY" & ASCII.LF &
     "    assets:cash             -20 JPY" & ASCII.LF & ASCII.LF &
     "2026-02-01 Current salary" & ASCII.LF &
     "    assets:cash             100 JPY" & ASCII.LF &
     "    income:salary          -100 JPY" & ASCII.LF & ASCII.LF &
     "2026-02-02 Current food" & ASCII.LF &
     "    " & Food_Account & "            30 JPY" & ASCII.LF &
     "    assets:cash             -30 JPY" & ASCII.LF & ASCII.LF &
     "2026-02-03 Food refund" & ASCII.LF &
     "    " & Food_Account & "            -5 JPY" & ASCII.LF &
     "    assets:cash               5 JPY" & ASCII.LF & ASCII.LF &
     "2026-02-03 USD transfer" & ASCII.LF &
     "    assets:cash              10 USD" & ASCII.LF &
     "    liabilities:card        -10 USD" & ASCII.LF & ASCII.LF &
     "2026-02-20 Future current-cycle food" & ASCII.LF &
     "    expenses:food            99 JPY" & ASCII.LF &
     "    assets:cash             -99 JPY" & ASCII.LF;

   L          : HRA.Ledger.Ledger;
   Parse_Diag : HRA.Journal.Parse_Diagnostic;
   Current    : HRA.Cycle_Accounts_Observation.Observation;
   Current_Diag : HRA.Cycle_Accounts_Observation.Observe_Diagnostic;
   Comparison : HRA.Report_Cycle_Accounts.Cycle_Comparison_Observation;
   Comparison_Diag : HRA.Report_Cycle_Accounts.Comparison_Diagnostic;

begin
   HRA.Terminal_UTF8.Initialize;
   Put_Line ("--- Testing typed Cycle Accounts report ---");

   Assert
     (HRA.Journal.Parse_Journal_Text
        (Journal_Text, "cycle-accounts.journal", L, Parse_Diag),
      "setup parses typed multi-Commodity Actual journal");

   Assert
     (HRA.Cycle_Accounts_Observation.Observe
        (L,
         Window ("2026-02-01", "2026-03-01"),
         D ("2026-02-03"),
         Current,
         Current_Diag),
      "current Cycle Accounts observes one explicit cycle through one day");

   Assert
     (Natural (Current.Rows.Length) = 5
      and then HRA.Account.Name (Current.Rows.Element (1).Acc) = "assets:cash"
      and then HRA.Account.Name (Current.Rows.Element (2).Acc) = "liabilities:card"
      and then HRA.Account.Name (Current.Rows.Element (3).Acc) = "equity:opening"
      and then HRA.Account.Name (Current.Rows.Element (4).Acc) = "income:salary"
      and then HRA.Account.Name (Current.Rows.Element (5).Acc) = Food_Account,
      "current Cycle Accounts preserves every declared Account in declaration order");

   Assert
     (JPY (Current.Rows.Element (1).Opening) = 80.0
      and then JPY (Current.Rows.Element (1).Debit) = 105.0
      and then JPY (Current.Rows.Element (1).Credit) = -30.0
      and then JPY
        (HRA.Cycle_Accounts_Observation.Movement (Current.Rows.Element (1))) = 75.0
      and then JPY
        (HRA.Cycle_Accounts_Observation.Closing (Current.Rows.Element (1))) = 155.0,
      "Asset row keeps opening, signed debit-credit movement, and derived closing");

   Assert
     (JPY (Current.Rows.Element (5).Debit) = 30.0
      and then JPY (Current.Rows.Element (5).Credit) = -5.0
      and then JPY
        (HRA.Cycle_Accounts_Observation.Movement (Current.Rows.Element (5))) = 25.0,
      "Expense refund stays in the signed Credit lane");

   Assert
     (USD (Current.Rows.Element (1).Debit) = 10.0
      and then USD (Current.Rows.Element (2).Credit) = -10.0
      and then USD (HRA.Cycle_Accounts_Observation.Movement_Total (Current)) = 0.0,
      "Cycle Accounts preserves Commodity identity through exact aggregation");

   Assert
     (HRA.Money.Is_Zero_Balance
        (HRA.Cycle_Accounts_Observation.Opening_Total (Current))
      and then HRA.Money.Is_Zero_Balance
        (HRA.Cycle_Accounts_Observation.Movement_Total (Current))
      and then HRA.Money.Is_Zero_Balance
        (HRA.Cycle_Accounts_Observation.Closing_Total (Current))
      and then HRA.Cycle_Accounts_Observation.Is_Balanced (Current),
      "opening, movement, and closing retain double-entry balance laws");

   Assert
     (JPY (HRA.Cycle_Accounts_Observation.Movement (Current.Rows.Element (5))) = 25.0,
      "future in-cycle Actual after observation day is excluded");

   Assert
     (HRA.Report_Cycle_Accounts.Observe_Aligned
        (L,
         Window ("2026-01-01", "2026-02-01"),
         Current,
         Comparison,
         Comparison_Diag),
      "aligned comparison derives previous-cycle same elapsed day");

   Assert
     (Comparison.Baseline.Observed_Through = D ("2026-01-03")
      and then Natural (Comparison.Rows.Length) = 5,
      "comparison retains explicit baseline date and the same Account axis");

   Assert
     (JPY (Comparison.Rows.Element (1).Current_Movement) = 75.0
      and then JPY (Comparison.Rows.Element (1).Baseline_Movement) = 80.0
      and then JPY
        (HRA.Report_Cycle_Accounts.Difference (Comparison.Rows.Element (1))) = -5.0
      and then JPY
        (HRA.Report_Cycle_Accounts.Difference (Comparison.Rows.Element (5))) = 5.0,
      "comparison publishes movement difference without replacing either observation");

   Assert
     (HRA.Report_Cycle_Accounts.Is_Balanced (Comparison),
      "current, baseline, and difference movement totals remain balanced");

   declare
      Short_Result : HRA.Report_Cycle_Accounts.Cycle_Comparison_Observation;
      Short_Diag   : HRA.Report_Cycle_Accounts.Comparison_Diagnostic;
   begin
      Assert
        (not HRA.Report_Cycle_Accounts.Observe_Aligned
           (L,
            Window ("2026-01-01", "2026-01-03"),
            Current,
            Short_Result,
            Short_Diag)
         and then Short_Diag.Status =
           HRA.Report_Cycle_Accounts.Baseline_Elapsed_Outside_Cycle,
         "short previous cycle rejects only the aligned comparison projection");
   end;

   declare
      Report_Value : constant HRA.Report_Cycle_Accounts.Report_Observation :=
        (Current    => Current,
         Comparison =>
           (Status => HRA.Report_Cycle_Accounts.Comparison_Available,
            Value  => Comparison));
      Text : constant String := HRA.Cycle_Accounts_Render.Render (Report_Value);
      Header : constant String := Line_Containing (Text, "Account ");
      Japanese_Row : constant String := Line_Containing (Text, Food_Account);
      Zero_Row : constant String := Line_Containing (Text, "equity:opening");
   begin
      Assert
        (Index (Text, "== Current Cycle Accounts ==") > 0
         and then Index (Text, "Opening") > 0
         and then Index (Text, "Debit") > 0
         and then Index (Text, "Movement") > 0
         and then Index (Text, "Closing") > 0
         and then Index (Text, "== Cycle Comparison (Aligned Elapsed) ==") > 0
         and then Index (Text, "Previous same-day") > 0,
         "renderer consumes typed current and comparison observations only");
      for Separator in 1 .. 5 loop
         Assert
           (Separator_Column (Header, Separator) =
              Separator_Column (Japanese_Row, Separator),
            "UTF-8 Account row keeps separator" & Separator'Image &
            " in the header column");
      end loop;
      Assert
        (Index (Zero_Row, "|") > 0
         and then Zero_Row (Index (Zero_Row, "|") + 2) = ' ',
         "numeric Cycle Account cells are right aligned");
   end;

   Put_Line
     (Natural'Image (Passed_Count) & " passed, " &
      Natural'Image (Failed_Count) & " failed");
   if Failed_Count > 0 then
      raise Program_Error with "Cycle Accounts report tests failed";
   end if;
end Test_Report_Cycle_Accounts;
