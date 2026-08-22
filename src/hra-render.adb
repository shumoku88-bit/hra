with Ada.Strings;           use Ada.Strings;
with Ada.Strings.Fixed;     use Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA.Account;           use HRA.Account;
with HRA.Dates;
with HRA.Issues;
with HRA.Money;             use HRA.Money;
with HRA.Report_Flow;
with HRA.Terminal_Layout;

package body HRA.Render is

   function Render_Amount_Or_Paren
     (Q : Quantity; Comm_Code : String) return String
   is
   begin
      if Is_Zero (Q) then
         return "0";
      elsif Q < Zero_Quantity then
         return "(" & Render_Quantity (-Q) & " " & Comm_Code & ")";
      else
         return Render_Quantity (Q) & " " & Comm_Code;
      end if;
   end Render_Amount_Or_Paren;

   function Render_Multi_Balance (B : Balance) return String is
      Ents : constant Balance_Entry_Array := Entries (B);
      Buf  : Unbounded_String;
   begin
      if Ents'Length = 0 then
         return "0";
      end if;

      for I in Ents'Range loop
         if I > Ents'First then
            Append (Buf, ", ");
         end if;
         Append
           (Buf,
            Render_Amount_Or_Paren
              (Ents (I).Val, Code (Ents (I).Comm)));
      end loop;

      return To_String (Buf);
   end Render_Multi_Balance;

   function Render_Account_Balances
     (Value :
        HRA.Household_Report_Observation.Account_Balances_Report_Observation)
      return String
   is
      Buf : Unbounded_String;
   begin
      Append (Buf, "== Account Balances (hra Engine) ==" & ASCII.LF);
      Append (Buf, "As of: " & HRA.Dates.Image (Value.As_Of) & ASCII.LF);
      Append (Buf, ASCII.LF);
      Append
        (Buf,
         HRA.Terminal_Layout.Pad_Right ("Account", 15) & " | " &
         HRA.Terminal_Layout.Pad_Left ("Balance", 12) & ASCII.LF);
      Append (Buf, "------------------------------" & ASCII.LF);

      for Line of Value.Display_Lines loop
         Append
           (Buf,
            HRA.Terminal_Layout.Pad_Right (Name (Line.Acc), 15) & " | " &
            HRA.Terminal_Layout.Pad_Left
              (Render_Multi_Balance (Line.Bal), 12) & ASCII.LF);
      end loop;

      Append (Buf, ASCII.LF);
      Append
        (Buf,
         "Balance delta: " & Render_Multi_Balance (Value.Value.Total) &
         ASCII.LF);
      return To_String (Buf);
   end Render_Account_Balances;

   function Render_Balance_Sheet
     (Value : HRA.Household_Report_Observation.Balance_Sheet_Report_Observation)
      return String
   is
      Buf : Unbounded_String;
   begin
      Append (Buf, "== Balance Sheet (hra Engine) ==" & ASCII.LF);
      Append (Buf, "As of: " & HRA.Dates.Image (Value.As_Of) & ASCII.LF);
      Append (Buf, ASCII.LF & "Assets" & ASCII.LF);
      Append
        (Buf,
         HRA.Terminal_Layout.Pad_Right ("Account", 12) & " | " &
         HRA.Terminal_Layout.Pad_Left ("Balance", 10) & ASCII.LF);
      Append (Buf, "-------------------------" & ASCII.LF);
      for Line of Value.Value.Asset_Lines loop
         Append
           (Buf,
            HRA.Terminal_Layout.Pad_Right (Name (Line.Acc), 12) & " | " &
            HRA.Terminal_Layout.Pad_Left
              (Render_Multi_Balance (Line.Bal), 10) & ASCII.LF);
      end loop;
      Append
        (Buf,
         HRA.Terminal_Layout.Pad_Right ("Total assets", 12) & " | " &
         HRA.Terminal_Layout.Pad_Left
           (Render_Multi_Balance (Value.Value.Total_Assets), 10) &
         ASCII.LF & ASCII.LF);

      Append (Buf, "Liabilities" & ASCII.LF);
      Append
        (Buf,
         HRA.Terminal_Layout.Pad_Right ("Account", 17) & " | " &
         HRA.Terminal_Layout.Pad_Left ("Balance", 7) & ASCII.LF);
      Append (Buf, "---------------------------" & ASCII.LF);
      for Line of Value.Value.Liability_Lines loop
         Append
           (Buf,
            HRA.Terminal_Layout.Pad_Right (Name (Line.Acc), 17) & " | " &
            HRA.Terminal_Layout.Pad_Left
              (Render_Multi_Balance (Line.Bal), 7) & ASCII.LF);
      end loop;
      Append
        (Buf,
         HRA.Terminal_Layout.Pad_Right ("Total liabilities", 17) & " | " &
         HRA.Terminal_Layout.Pad_Left
           (Render_Multi_Balance (Value.Value.Total_Liabilities), 7) &
         ASCII.LF & ASCII.LF);

      Append (Buf, "Equity" & ASCII.LF);
      Append
        (Buf,
         HRA.Terminal_Layout.Pad_Right ("Account", 16) & " | " &
         HRA.Terminal_Layout.Pad_Left ("Balance", 10) & ASCII.LF);
      Append (Buf, "-----------------------------" & ASCII.LF);
      for Line of Value.Value.Equity_Lines loop
         Append
           (Buf,
            HRA.Terminal_Layout.Pad_Right (Name (Line.Acc), 16) & " | " &
            HRA.Terminal_Layout.Pad_Left
              (Render_Multi_Balance (Line.Bal), 10) & ASCII.LF);
      end loop;
      Append
        (Buf,
         HRA.Terminal_Layout.Pad_Right ("Total equity", 16) & " | " &
         HRA.Terminal_Layout.Pad_Left
           (Render_Multi_Balance (Value.Value.Total_Equity), 10) &
         ASCII.LF & ASCII.LF);
      Append
        (Buf,
         HRA.Terminal_Layout.Pad_Right ("Current earnings", 16) & " | " &
         HRA.Terminal_Layout.Pad_Left
           (Render_Multi_Balance (Value.Value.Current_Earnings), 10) &
         ASCII.LF);
      Append
        (Buf,
         "Accounting Equation delta (Assets - Liabilities - Equity): " &
         Render_Multi_Balance (Value.Value.Accounting_Equation_Delta) &
         ASCII.LF);
      return To_String (Buf);
   end Render_Balance_Sheet;

   function Render_Profit_And_Loss
     (Value :
        HRA.Household_Report_Observation.Profit_And_Loss_Report_Observation)
      return String
   is
      Buf : Unbounded_String;
   begin
      Append (Buf, "== Profit & Loss Statement (hra Engine) ==" & ASCII.LF);
      Append
        (Buf,
         "Period: " & HRA.Dates.Image (HRA.Dates.First (Value.Period)) & ".." &
         HRA.Dates.Image (HRA.Dates.Last (Value.Period)) & ASCII.LF & ASCII.LF);

      Append (Buf, "Income" & ASCII.LF);
      Append
        (Buf,
         HRA.Terminal_Layout.Pad_Right ("Account", 13) & " | " &
         HRA.Terminal_Layout.Pad_Left ("Amount", 9) & ASCII.LF);
      Append (Buf, "-------------------------" & ASCII.LF);
      for Line of Value.Value.Income_Lines loop
         Append
           (Buf,
            HRA.Terminal_Layout.Pad_Right (Name (Line.Acc), 13) & " | " &
            HRA.Terminal_Layout.Pad_Left
              (Render_Multi_Balance (Line.Bal), 9) & ASCII.LF);
      end loop;
      Append
        (Buf,
         HRA.Terminal_Layout.Pad_Right ("Total Income", 13) & " | " &
         HRA.Terminal_Layout.Pad_Left
           (Render_Multi_Balance (Value.Value.Total_Income), 9) &
         ASCII.LF & ASCII.LF);

      Append (Buf, "Expenses" & ASCII.LF);
      Append
        (Buf,
         HRA.Terminal_Layout.Pad_Right ("Account", 30) & " | " &
         HRA.Terminal_Layout.Pad_Left ("Amount", 9) & ASCII.LF);
      Append (Buf, "------------------------------------------" & ASCII.LF);
      for Line of Value.Value.Expense_Lines loop
         Append
           (Buf,
            HRA.Terminal_Layout.Pad_Right (Name (Line.Acc), 30) & " | " &
            HRA.Terminal_Layout.Pad_Left
              (Render_Multi_Balance (Line.Bal), 9) & ASCII.LF);
      end loop;
      Append
        (Buf,
         HRA.Terminal_Layout.Pad_Right ("Total Expenses", 30) & " | " &
         HRA.Terminal_Layout.Pad_Left
           (Render_Multi_Balance (Value.Value.Total_Expenses), 9) & ASCII.LF);
      Append (Buf, "------------------------------------------" & ASCII.LF);
      Append
        (Buf,
         HRA.Terminal_Layout.Pad_Right
           ("Net Profit (Income - Expenses)", 30) & " | " &
         HRA.Terminal_Layout.Pad_Left
           (Render_Multi_Balance (Value.Value.Net_Income), 9) & ASCII.LF);
      return To_String (Buf);
   end Render_Profit_And_Loss;

   function Render_Daily_Flow
     (Value : HRA.Report_Flow.Daily_Flow_Observation) return String
   is
      Buf            : Unbounded_String;
      Date_Width     : Natural := HRA.Terminal_Layout.Display_Width ("Date");
      Income_Width   : Natural := HRA.Terminal_Layout.Display_Width ("Income");
      Expenses_Width : Natural := HRA.Terminal_Layout.Display_Width ("Expenses");
      Net_Width      : Natural := HRA.Terminal_Layout.Display_Width ("Net");

      procedure Append_Row (Date, Income, Expenses, Net : String) is
      begin
         Append
           (Buf,
            HRA.Terminal_Layout.Pad_Right (Date, Date_Width) & " | " &
            HRA.Terminal_Layout.Pad_Left (Income, Income_Width) & " | " &
            HRA.Terminal_Layout.Pad_Left (Expenses, Expenses_Width) & " | " &
            HRA.Terminal_Layout.Pad_Left (Net, Net_Width) & ASCII.LF);
      end Append_Row;
   begin
      for Line of Value.Lines loop
         Date_Width := Natural'Max
           (Date_Width,
            HRA.Terminal_Layout.Display_Width (HRA.Dates.Image (Line.Day)));
         Income_Width := Natural'Max
           (Income_Width,
            HRA.Terminal_Layout.Display_Width
              (Render_Multi_Balance (Line.Income)));
         Expenses_Width := Natural'Max
           (Expenses_Width,
            HRA.Terminal_Layout.Display_Width
              (Render_Multi_Balance (Line.Expenses)));
         Net_Width := Natural'Max
           (Net_Width,
            HRA.Terminal_Layout.Display_Width
              (Render_Multi_Balance (HRA.Report_Flow.Net (Line))));
      end loop;
      Income_Width := Natural'Max
        (Income_Width,
         HRA.Terminal_Layout.Display_Width
           (Render_Multi_Balance (HRA.Report_Flow.Total_Income (Value))));
      Expenses_Width := Natural'Max
        (Expenses_Width,
         HRA.Terminal_Layout.Display_Width
           (Render_Multi_Balance (HRA.Report_Flow.Total_Expenses (Value))));
      Net_Width := Natural'Max
        (Net_Width,
         HRA.Terminal_Layout.Display_Width
           (Render_Multi_Balance (HRA.Report_Flow.Total_Net (Value))));

      Append (Buf, "== Daily Flow (Account x Day) ==" & ASCII.LF);
      Append
        (Buf,
         "Period: " & HRA.Dates.Image (HRA.Dates.First (Value.Period)) &
         ".." & HRA.Dates.Image (HRA.Dates.Last (Value.Period)) &
         ASCII.LF & ASCII.LF);
      Append_Row ("Date", "Income", "Expenses", "Net");
      Append
        (Buf,
         [1 .. Date_Width + Income_Width + Expenses_Width + Net_Width + 9 => '-'] &
         ASCII.LF);
      for Line of Value.Lines loop
         Append_Row
           (HRA.Dates.Image (Line.Day),
            Render_Multi_Balance (Line.Income),
            Render_Multi_Balance (Line.Expenses),
            Render_Multi_Balance (HRA.Report_Flow.Net (Line)));
      end loop;
      Append_Row
        ("Total",
         Render_Multi_Balance (HRA.Report_Flow.Total_Income (Value)),
         Render_Multi_Balance (HRA.Report_Flow.Total_Expenses (Value)),
         Render_Multi_Balance (HRA.Report_Flow.Total_Net (Value)));

      if not Value.Expense_Rows.Is_Empty then
         Append (Buf, ASCII.LF & "Expense accounts by day" & ASCII.LF);
         for Row of Value.Expense_Rows loop
            Append (Buf, Name (Row.Acc) & ASCII.LF);
            for Cell of Row.Cells loop
               Append
                 (Buf,
                  "  " & HRA.Dates.Image (Cell.Day) & " | " &
                  Render_Multi_Balance (Cell.Value) & ASCII.LF);
            end loop;
         end loop;
      end if;

      return To_String (Buf);
   end Render_Daily_Flow;

   function Render_Monthly_Accounts
     (Value : HRA.Report_Flow.Monthly_Accounts_Observation) return String
   is
      Buf            : Unbounded_String;
      Month_Width    : Natural := HRA.Terminal_Layout.Display_Width ("Month");
      Income_Width   : Natural := HRA.Terminal_Layout.Display_Width ("Income");
      Expenses_Width : Natural := HRA.Terminal_Layout.Display_Width ("Expenses");
      Net_Width      : Natural := HRA.Terminal_Layout.Display_Width ("Net");

      procedure Append_Summary_Row (Month, Income, Expenses, Net : String) is
      begin
         Append
           (Buf,
            HRA.Terminal_Layout.Pad_Right (Month, Month_Width) & " | " &
            HRA.Terminal_Layout.Pad_Left (Income, Income_Width) & " | " &
            HRA.Terminal_Layout.Pad_Left (Expenses, Expenses_Width) & " | " &
            HRA.Terminal_Layout.Pad_Left (Net, Net_Width) & ASCII.LF);
      end Append_Summary_Row;

      procedure Render_Rows
        (Label : String;
         Rows  : HRA.Report_Flow.Monthly_Account_Row_Vectors.Vector)
      is
      begin
         Append (Buf, ASCII.LF & Label & ASCII.LF);
         for Row of Rows loop
            Append (Buf, Name (Row.Acc));
            for Month of Value.Months loop
               Append
                 (Buf,
                  " | " & HRA.Report_Flow.Image (Month) & "=" &
                  Render_Multi_Balance
                    (HRA.Report_Flow.Balance_For (Row, Month)));
            end loop;
            Append
              (Buf,
               " | Period total=" &
               Render_Multi_Balance (HRA.Report_Flow.Row_Total (Row)) &
               ASCII.LF);
         end loop;
      end Render_Rows;
   begin
      for Month of Value.Months loop
         Month_Width := Natural'Max
           (Month_Width,
            HRA.Terminal_Layout.Display_Width
              (HRA.Report_Flow.Image (Month)));
         Income_Width := Natural'Max
           (Income_Width,
            HRA.Terminal_Layout.Display_Width
              (Render_Multi_Balance
                 (HRA.Report_Flow.Income_For (Value, Month))));
         Expenses_Width := Natural'Max
           (Expenses_Width,
            HRA.Terminal_Layout.Display_Width
              (Render_Multi_Balance
                 (HRA.Report_Flow.Expenses_For (Value, Month))));
         Net_Width := Natural'Max
           (Net_Width,
            HRA.Terminal_Layout.Display_Width
              (Render_Multi_Balance
                 (HRA.Report_Flow.Net_For (Value, Month))));
      end loop;

      Append (Buf, "== Monthly Accounts (Account x Month) ==" & ASCII.LF);
      Append
        (Buf,
         "Period: " & HRA.Dates.Image (HRA.Dates.First (Value.Period)) &
         ".." & HRA.Dates.Image (HRA.Dates.Last (Value.Period)) &
         " | Displayed months: " &
         Trim (Natural'Image (Natural (Value.Months.Length)), Both) &
         ASCII.LF & ASCII.LF);
      Append_Summary_Row ("Month", "Income", "Expenses", "Net");
      Append
        (Buf,
         [1 .. Month_Width + Income_Width + Expenses_Width + Net_Width + 9 => '-'] &
         ASCII.LF);
      for Month of Value.Months loop
         Append_Summary_Row
           (HRA.Report_Flow.Image (Month),
            Render_Multi_Balance (HRA.Report_Flow.Income_For (Value, Month)),
            Render_Multi_Balance (HRA.Report_Flow.Expenses_For (Value, Month)),
            Render_Multi_Balance (HRA.Report_Flow.Net_For (Value, Month)));
      end loop;

      Render_Rows ("Income accounts", Value.Income_Rows);
      Render_Rows ("Expense accounts", Value.Expense_Rows);
      return To_String (Buf);
   end Render_Monthly_Accounts;

   function Render_Household_Issues
     (Value : HRA.Household_Report_Observation.Issues_Report_Observation)
      return String
   is
      Buf        : Unbounded_String;
      Open_Array : constant HRA.Issues.Issue_Array :=
        HRA.Issues.All_Issues (Value.Open_Items);
   begin
      Append (Buf, "== Household Issues ==" & ASCII.LF);
      Append
        (Buf,
         "Open issues only | Displayed: " &
         Trim (Natural'Image (Open_Array'Length), Both) &
         " | Resolved hidden: " &
         Trim (Natural'Image (Value.Resolved_Count), Both) & ASCII.LF);
      Append
        (Buf,
         "Issues do not change accounting or budget values" &
         ASCII.LF & ASCII.LF);

      for Issue of Open_Array loop
         Append
           (Buf,
            "+- OPEN -------------------------------------------------------------------------------+" &
            ASCII.LF);
         Append (Buf, "| ID       : " & HRA.Issues.Text (Issue.ID) & ASCII.LF);
         Append (Buf, "| Recorded : " & HRA.Dates.Image (Issue.Recorded_On) & ASCII.LF);
         if Issue.Amt.Has_Amount then
            Append
              (Buf,
               "| Amount   : " & Render_Quantity (Issue.Amt.Value.Val) & " " &
               Code (Issue.Amt.Value.Comm) & ASCII.LF);
         end if;
         Append (Buf, "| Title    : " & To_String (Issue.Title) & ASCII.LF);
         Append
           (Buf,
            "| Details  : [" & To_String (Issue.Category) & "] " &
            To_String (Issue.Details) & ASCII.LF);
         Append
           (Buf,
            "+--------------------------------------------------------------------------------------+" &
            ASCII.LF & ASCII.LF);
      end loop;

      return To_String (Buf);
   end Render_Household_Issues;

end HRA.Render;
