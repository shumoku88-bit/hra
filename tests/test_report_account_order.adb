with Ada.Text_IO;          use Ada.Text_IO;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with ALedger.Account;       use ALedger.Account;
with ALedger.Dates;
with ALedger.Journal;       use ALedger.Journal;
with ALedger.Ledger;        use ALedger.Ledger;
with ALedger.Money;         use ALedger.Money;
with ALedger.Report;        use ALedger.Report;

procedure Test_Report_Account_Order is
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
      Value  : ALedger.Dates.Date;
      Status : ALedger.Dates.Date_Status;
   begin
      if not ALedger.Dates.Parse (S, Value, Status) then
         raise Program_Error with "invalid test date: " & S;
      end if;
      return Value;
   end D;

   function P (First_Day, Last_Day : String)
      return ALedger.Dates.Closed_Period
   is
      Period : ALedger.Dates.Closed_Period;
   begin
      if not ALedger.Dates.Make_Closed_Period
        (D (First_Day), D (Last_Day), Period)
      then
         raise Program_Error with
           "invalid test period: " & First_Day & ".." & Last_Day;
      end if;
      return Period;
   end P;

   Journal_Text : constant String :=
     "account expenses:zeta" & ASCII.LF &
     "  ; type: Expense" & ASCII.LF &
     "account assets:bank" & ASCII.LF &
     "  ; type: Asset" & ASCII.LF &
     "account expenses:alpha" & ASCII.LF &
     "  ; type: Expense" & ASCII.LF &
     "" & ASCII.LF &
     "2026-08-01 Zeta Expense" & ASCII.LF &
     "    expenses:zeta       100 JPY" & ASCII.LF &
     "    assets:bank         -100 JPY" & ASCII.LF &
     "" & ASCII.LF &
     "2026-08-02 Alpha Expense" & ASCII.LF &
     "    expenses:alpha       50 JPY" & ASCII.LF &
     "    assets:bank          -50 JPY" & ASCII.LF &
     "" & ASCII.LF &
     "2026-09-01 Later Zeta Expense" & ASCII.LF &
     "    expenses:zeta        25 JPY" & ASCII.LF &
     "    assets:bank          -25 JPY" & ASCII.LF;

   L     : Ledger;
   Error : Unbounded_String;
   JPY   : constant Commodity := Make_Commodity ("JPY");
   Q_100 : Quantity;
   Q_150 : Quantity;

begin
   Put_Line ("--- Testing admitted Account report order ---");

   Assert
     (Parse_Journal_Text (Journal_Text, L, Error),
      "Setup: parse journal with non-alphabetic declaration order");
   Assert (Parse_Quantity ("100", Q_100), "Setup: parse 100 JPY");
   Assert (Parse_Quantity ("150", Q_150), "Setup: parse 150 JPY");

   declare
      TB : constant Trial_Balance := Generate_Trial_Balance (L);
   begin
      Assert
        (Natural (TB.Lines.Length) = 3,
         "Trial Balance retains the three active admitted Accounts");
      Assert
        (Name (TB.Lines.Element (1).Acc) = "expenses:zeta"
           and then Name (TB.Lines.Element (2).Acc) = "assets:bank"
           and then Name (TB.Lines.Element (3).Acc) = "expenses:alpha",
         "Trial Balance follows source-admitted declaration order");
   end;

   declare
      August : constant ALedger.Dates.Closed_Period :=
        P ("2026-08-01", "2026-08-31");
      Zeta   : constant Account := Make_Account ("expenses:zeta");
      PL     : constant Profit_And_Loss :=
        Generate_Profit_And_Loss_Period (L, August);
   begin
      Assert
        (Lookup_Balance
           (Compute_Account_Movement_In (L, Zeta, August), JPY) = Q_100,
         "Typed Account period movement excludes later activity");
      Assert
        (Natural (PL.Expense_Lines.Length) = 2
           and then Name (PL.Expense_Lines.Element (1).Acc) = "expenses:zeta"
           and then Name (PL.Expense_Lines.Element (2).Acc) = "expenses:alpha",
         "Period P&L preserves admitted order within Expense lines");
      Assert
        (Lookup_Balance (PL.Total_Expenses, JPY) = Q_150,
         "Period P&L total remains exact after typed projection refactor");
   end;

   Put_Line
     (Natural'Image (Passed_Count) & " passed, " &
      Natural'Image (Failed_Count) & " failed");

   if Failed_Count > 0 then
      raise Program_Error with "report Account order tests failed";
   end if;
end Test_Report_Account_Order;
