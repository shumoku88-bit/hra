with Ada.Text_IO;
with Ada.Strings.Unbounded;  use Ada.Strings.Unbounded;
with ALedger.Money;          use ALedger.Money;
with ALedger.Account;        use ALedger.Account;
with ALedger.Ledger;         use ALedger.Ledger;
with ALedger.Report;         use ALedger.Report;
with ALedger.Render;         use ALedger.Render;
with ALedger.Writer;         use ALedger.Writer;
with ALedger.Output;         use ALedger.Output;

package body ALedger.TUI is

   C_ESC : constant Character := Character'Val (27);

   function Reset return String is (C_ESC & "[0m");
   function Bold return String is (C_ESC & "[1m");
   function Cyan return String is (C_ESC & "[36m");
   function Green return String is (C_ESC & "[32m");
   function Yellow return String is (C_ESC & "[33m");
   function Red return String is (C_ESC & "[31m");
   function Header_Bar return String is (C_ESC & "[1;37;44m");

   procedure Clear_Screen is
   begin
      Put (C_ESC & "[2J" & C_ESC & "[H");
   end Clear_Screen;

   procedure Draw_Banner (Root_Path : String) is
   begin
      Put_Line (Header_Bar & "  ==============================================================  " & Reset);
      Put_Line (Header_Bar & "   ALedger Terminal UI (Ada 2022 Accounting Kernel)              " & Reset);
      Put_Line (Header_Bar & "  ==============================================================  " & Reset);
      Put_Line (Cyan & " Household Root: " & Reset & Bold & Root_Path & Reset);
      New_Line;
   end Draw_Banner;

   procedure Show_Dashboard_Summary (State : Household_State) is
      PL  : constant Profit_And_Loss := Generate_Profit_And_Loss (State.Combined_Ledger);
      BS  : constant Balance_Sheet := Generate_Balance_Sheet (State.Combined_Ledger);
      JPY : constant Commodity := Make_Commodity ("JPY");

      Ast : constant Quantity := Lookup_Balance (BS.Total_Assets, JPY);
      Lia : constant Quantity := Lookup_Balance (BS.Total_Liabilities, JPY);
      Net : constant Quantity := Lookup_Balance (PL.Net_Income, JPY);
   begin
      Put_Line (Yellow & "+-- Financial Summary ---------------------------------------+" & Reset);
      Put_Line ("| Total Assets      : " & Green & Render_Quantity (Ast) & " JPY" & Reset);
      Put_Line ("| Total Liabilities : " & Red & Render_Quantity (Lia) & " JPY" & Reset);
      Put_Line ("| Net Income        : " & Bold & Render_Quantity (Net) & " JPY" & Reset);
      if Is_Zero_Balance (BS.Accounting_Equation_Delta) then
         Put_Line ("| Accounting Equation: " & Green & "BALANCED (Assets = Liabilities + Equity)" & Reset);
      else
         Put_Line ("| Accounting Equation: " & Red & "UNBALANCED!" & Reset);
      end if;
      Put_Line (Yellow & "+------------------------------------------------------------+" & Reset);
      New_Line;
   end Show_Dashboard_Summary;

   procedure Pause_For_User is
      Dummy : String (1 .. 100);
      Last  : Natural;
   begin
      New_Line;
      Put (Cyan & "Press ENTER to return to Dashboard..." & Reset);
      Ada.Text_IO.Get_Line (Dummy, Last);
   end Pause_For_User;

   procedure Run_Interactive_TUI (State : in out Household_State) is
      Choice : String (1 .. 10);
      Last   : Natural;
   begin
      loop
         Clear_Screen;
         Draw_Banner (To_String (State.Root_Path));
         Show_Dashboard_Summary (State);

         Put_Line (Bold & "Select Action:" & Reset);
         Put_Line ("  [1] View Financial Statements (P&L, Balance Sheet, Trial Balance)");
         Put_Line ("  [2] View Account Balances");
         Put_Line ("  [3] Check Ledger Balance Laws & Admission Status");
         Put_Line ("  [4] Record New Transaction Safely (Safe Writer)");
         Put_Line ("  [Q] Quit TUI");
         New_Line;
         Put (Cyan & "Choice > " & Reset);

         Ada.Text_IO.Get_Line (Choice, Last);

         if Last > 0 then
            case Choice (1) is
               when '1' =>
                  Clear_Screen;
                  Put_Line (Bold & "--- Financial Statements ---" & Reset);
                  New_Line;
                  Put (Render_Profit_And_Loss (State.Combined_Ledger));
                  New_Line;
                  Put (Render_Balance_Sheet (State.Combined_Ledger));
                  Pause_For_User;

               when '2' =>
                  Clear_Screen;
                  Put_Line (Bold & "--- Account Balances ---" & Reset);
                  New_Line;
                  Put (Render_Account_Balances (State.Combined_Ledger));
                  Pause_For_User;

               when '3' =>
                  Clear_Screen;
                  Put_Line (Bold & "--- Ledger Verification Check ---" & Reset);
                  New_Line;
                  Put_Line (Green & "SUCCESS: Ledger balance law verified!" & Reset);
                  Put_Line ("  Actual Transactions : " & Natural'Image (Natural (State.Actual_Ledger.Transactions.Length)));
                  Put_Line ("  Plan Transactions   : " & Natural'Image (Natural (State.Plan_Ledger.Transactions.Length)));
                  Put_Line ("  Budget Transactions : " & Natural'Image (Natural (State.Budget_Ledger.Transactions.Length)));
                  Put_Line ("  Registered Accounts : " & Natural'Image (Declarations (State.Registry)'Length));
                  Pause_For_User;

               when '4' =>
                  Clear_Screen;
                  Put_Line (Bold & "--- Record New Transaction (Safe Writer) ---" & Reset);
                  New_Line;
                  declare
                     Date_Str, Payee_Str, From_Str, To_Str, Amt_Str : String (1 .. 100);
                     D_Last, P_Last, F_Last, T_Last, A_Last : Natural;
                  begin
                     Put ("Enter Date (YYYY-MM-DD) : ");
                     Ada.Text_IO.Get_Line (Date_Str, D_Last);
                     Put ("Enter Description       : ");
                     Ada.Text_IO.Get_Line (Payee_Str, P_Last);
                     Put ("From Account (Asset)   : ");
                     Ada.Text_IO.Get_Line (From_Str, F_Last);
                     Put ("To Account (Expense)   : ");
                     Ada.Text_IO.Get_Line (To_Str, T_Last);
                     Put ("Amount JPY              : ");
                     Ada.Text_IO.Get_Line (Amt_Str, A_Last);

                     if D_Last > 0 and P_Last > 0 and F_Last > 0 and T_Last > 0 and A_Last > 0 then
                        declare
                           Tx_Block : constant String :=
                             Date_Str (1 .. D_Last) & " " & Payee_Str (1 .. P_Last) & ASCII.LF &
                             "    " & To_Str (1 .. T_Last) & "          " & Amt_Str (1 .. A_Last) & " JPY" & ASCII.LF &
                             "    " & From_Str (1 .. F_Last) & "         -" & Amt_Str (1 .. A_Last) & " JPY" & ASCII.LF;

                           W_Stat  : Writer_Status;
                           Err_Msg : Unbounded_String;
                           Actual_Path : constant String := To_String (State.Paths.Actual_Journal);
                        begin
                           if Append_Transaction_Safely (Actual_Path, Tx_Block, W_Stat, Err_Msg) then
                              Put_Line (Green & "[SUCCESS] Transaction safely published via Safe Writer!" & Reset);
                           else
                              Put_Line (Red & "[ERROR] Publication failed: " & To_String (Err_Msg) & Reset);
                           end if;
                        end;
                     else
                        Put_Line (Yellow & "Transaction entry canceled (empty field)." & Reset);
                     end if;
                  end;
                  Pause_For_User;

               when 'q' | 'Q' =>
                  Clear_Screen;
                  Put_Line (Green & "Exiting ALedger TUI. Goodbye!" & Reset);
                  exit;

               when others =>
                  null;
            end case;
         end if;
      end loop;
   end Run_Interactive_TUI;

end ALedger.TUI;
