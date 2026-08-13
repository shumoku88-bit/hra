with Ada.Text_IO;          use Ada.Text_IO;
with Ada.Directories;        use Ada.Directories;
with Ada.Strings.Fixed;      use Ada.Strings.Fixed;
with Ada.Strings.Unbounded;  use Ada.Strings.Unbounded;
with ALedger;
with ALedger.Money;          use ALedger.Money;
with ALedger.Account;        use ALedger.Account;
with ALedger.Ledger;         use ALedger.Ledger;
with ALedger.Journal;        use ALedger.Journal;
with ALedger.Report;         use ALedger.Report;
with ALedger.Household;      use ALedger.Household;
with ALedger.Plan;           use ALedger.Plan;
with ALedger.Writer;         use ALedger.Writer;
with ALedger.Render;         use ALedger.Render;

procedure Test_Runner is
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

   procedure Test_Money is
      JPY, USD : Commodity;
      C_Status : Commodity_Status;
      Q1, Q2   : Quantity;
      A1, A2   : Amount;
      B1, B2   : Balance;
   begin
      Put_Line ("--- Testing ALedger.Money ---");

      Assert (Create_Commodity ("JPY", JPY, C_Status) and then C_Status = Success, "Create JPY Commodity");
      Assert (Create_Commodity ("USD", USD, C_Status) and then C_Status = Success, "Create USD Commodity");

      Assert (not Create_Commodity ("", JPY, C_Status) and then C_Status = Empty_Commodity_Code, "Reject empty commodity");
      Assert (not Create_Commodity ("JP Y", JPY, C_Status) and then C_Status = Commodity_Contains_Whitespace, "Reject commodity with space");

      Assert (Parse_Quantity ("1000", Q1), "Parse quantity 1000");
      Assert (Parse_Quantity ("-500.50", Q2), "Parse quantity -500.50");

      Assert (Render_Quantity (Q1) = "1000", "Render quantity 1000");
      Assert (Render_Quantity (Q2) = "-500.5", "Render quantity -500.5");

      A1 := Make_Amount (JPY, Q1);
      A2 := Make_Amount (JPY, Q2);

      B1 := Singleton_Balance (A1);
      B2 := Singleton_Balance (A2);

      declare
         B_Sum : constant Balance := Add_Balance (B1, B2);
         Entries_Arr : constant Balance_Entry_Array := Entries (B_Sum);
      begin
         Assert (Entries_Arr'Length = 1, "Balance addition single entry count");
         Assert (Render_Quantity (Entries_Arr (1).Val) = "499.5", "Balance addition correct value 499.5");
      end;

      declare
         B_Cancel : constant Balance := Add_Balance (B1, Negate_Balance (B1));
      begin
         Assert (Is_Zero_Balance (B_Cancel), "Balance negation cancels to zero");
      end;
   end Test_Money;

   procedure Test_Account is
      Acc1, Acc2   : ALedger.Account.Account;
      A_Status     : Account_Status;
      Reg          : Account_Registry := Empty_Registry;
      R_Status     : Registry_Status;
      Decl1, Decl2 : Account_Declaration;
   begin
      Put_Line ("--- Testing ALedger.Account ---");

      Assert (Create_Account ("assets:bank:checking", Acc1, A_Status), "Create Account assets:bank:checking");
      Assert (Create_Account ("expenses:food", Acc2, A_Status), "Create Account expenses:food");

      Assert (not Create_Account ("  assets:bank  ", Acc1, A_Status) and then A_Status = Account_Has_Surrounding_Whitespace, "Reject space trimmed account");

      Decl1 := Declare_Account (Acc1, Asset);
      Decl2 := Declare_Account (Acc2, Expense);

      Assert (Register_Account (Reg, Decl1, R_Status), "Register Acc1");
      Assert (Register_Account (Reg, Decl2, R_Status), "Register Acc2");
      Assert (not Register_Account (Reg, Decl1, R_Status) and then R_Status = Duplicate_Account_Declaration, "Reject duplicate account registration");

      declare
         Found_AT : Account_Type;
      begin
         Assert (Account_Type_For (Reg, Acc1, Found_AT) and then Found_AT = Asset, "Lookup Account_Type for Acc1 = Asset");
         Assert (Account_Type_For (Reg, Acc2, Found_AT) and then Found_AT = Expense, "Lookup Account_Type for Acc2 = Expense");
      end;
   end Test_Account;

   procedure Test_Ledger is
      JPY      : constant Commodity := Make_Commodity ("JPY");
      Acc_Cash : constant ALedger.Account.Account := Make_Account ("assets:cash");
      Acc_Food : constant ALedger.Account.Account := Make_Account ("expenses:food");
      Q_1000   : Quantity;
      Q_M1000  : Quantity;
      Postings : Posting_Vectors.Vector;
      Tx       : Transaction;
      T_Status : Transaction_Error;
      L        : Ledger := Empty_Ledger;
   begin
      Put_Line ("--- Testing ALedger.Ledger & Balance Law ---");

      Assert (Parse_Quantity ("1000", Q_1000), "Parse 1000");
      Assert (Parse_Quantity ("-1000", Q_M1000), "Parse -1000");

      Postings.Append (Make_Posting (Acc_Food, Make_Amount (JPY, Q_1000)));
      Postings.Append (Make_Posting (Acc_Cash, Make_Amount (JPY, Q_M1000)));

      Assert (Create_Transaction ("2026-08-13", "Grocery Purchase", Postings, Tx, T_Status), "Create balanced transaction");
      Assert (Is_Balanced (Tx), "Verify transaction balance law (sum = 0)");

      Assert (Add_Transaction (L, Tx, T_Status), "Add balanced transaction to ledger");

      declare
         Cash_Bal : constant Balance := Compute_Account_Balance (L, Acc_Cash);
         Food_Bal : constant Balance := Compute_Account_Balance (L, Acc_Food);
         Tot_Bal  : constant Balance := Compute_Total_Balance (L);
      begin
         Assert (Lookup_Balance (Cash_Bal, JPY) = Q_M1000, "Cash account balance = -1000");
         Assert (Lookup_Balance (Food_Bal, JPY) = Q_1000, "Food account balance = 1000");
         Assert (Is_Zero_Balance (Tot_Bal), "Total ledger balance across all accounts is ZERO");
      end;
   end Test_Ledger;

   procedure Test_Journal is
      Sample_Journal_Text : constant String :=
        "; Sample Journal Document" & ASCII.LF &
        "account assets:bank:checking" & ASCII.LF &
        "  ; type: Asset" & ASCII.LF &
        "account expenses:food" & ASCII.LF &
        "  ; type: Expense" & ASCII.LF &
        "" & ASCII.LF &
        "2026-08-13 Supermarket Purchase" & ASCII.LF &
        "    expenses:food          1500 JPY" & ASCII.LF &
        "    assets:bank:checking" & ASCII.LF &   -- Elided amount! Should infer -1500 JPY
        "";

      L         : Ledger;
      Err       : Unbounded_String;
      Acc_Bank  : constant ALedger.Account.Account := Make_Account ("assets:bank:checking");
      Acc_Food  : constant ALedger.Account.Account := Make_Account ("expenses:food");
      JPY       : constant Commodity := Make_Commodity ("JPY");
      Q_M1500   : Quantity;
      Q_1500    : Quantity;
   begin
      Put_Line ("--- Testing ALedger.Journal Parser & Auto-Balancing ---");

      Assert (Parse_Quantity ("-1500", Q_M1500), "Parse -1500");
      Assert (Parse_Quantity ("1500", Q_1500), "Parse 1500");
      Assert (Parse_Journal_Text (Sample_Journal_Text, L, Err), "Parse Journal text with elided amount");
      Assert (Natural (L.Transactions.Length) = 1, "Journal parsed 1 transaction");

      declare
         Bank_Bal : constant Balance := Compute_Account_Balance (L, Acc_Bank);
         Food_Bal : constant Balance := Compute_Account_Balance (L, Acc_Food);
         Tot_Bal  : constant Balance := Compute_Total_Balance (L);
      begin
         Assert (Lookup_Balance (Bank_Bal, JPY) = Q_M1500, "Elided amount inferred bank balance = -1500 JPY");
         Assert (Lookup_Balance (Food_Bal, JPY) = Q_1500, "Food account balance = 1500 JPY");
         Assert (Is_Zero_Balance (Tot_Bal), "Parsed journal preserves strict ZERO balance law");
      end;
   end Test_Journal;

   procedure Test_Report_And_Budget is
      Journal_With_Income_And_Expense : constant String :=
        "account assets:bank" & ASCII.LF &
        "  ; type: Asset" & ASCII.LF &
        "account income:salary" & ASCII.LF &
        "  ; type: Income" & ASCII.LF &
        "account expenses:rent" & ASCII.LF &
        "  ; type: Expense" & ASCII.LF &
        "" & ASCII.LF &
        "2026-08-01 Monthly Salary Receive" & ASCII.LF &
        "    assets:bank           300000 JPY" & ASCII.LF &
        "    income:salary        -300000 JPY" & ASCII.LF &
        "" & ASCII.LF &
        "2026-08-05 Rent Payment" & ASCII.LF &
        "    expenses:rent          80000 JPY" & ASCII.LF &
        "    assets:bank           -80000 JPY" & ASCII.LF &
        "";

      L        : Ledger;
      Err      : Unbounded_String;
      JPY      : constant Commodity := Make_Commodity ("JPY");
      Q_220k   : Quantity;
      Q_80k    : Quantity;
      Q_300k   : Quantity;
   begin
      Put_Line ("--- Testing ALedger.Report & ALedger.Budget ---");

      Assert (Parse_Quantity ("220000", Q_220k), "Parse 220000");
      Assert (Parse_Quantity ("80000", Q_80k), "Parse 80000");
      Assert (Parse_Quantity ("300000", Q_300k), "Parse 300000");

      Assert (Parse_Journal_Text (Journal_With_Income_And_Expense, L, Err), "Parse multi-account journal");

      declare
         PL : constant Profit_And_Loss := Generate_Profit_And_Loss (L);
         BS : constant Balance_Sheet := Generate_Balance_Sheet (L);
         TB : constant Trial_Balance := Generate_Trial_Balance (L);
      begin
         Assert (Lookup_Balance (PL.Total_Income, JPY) = Q_300k, "P&L Total Income = 300,000 JPY");
         Assert (Lookup_Balance (PL.Total_Expenses, JPY) = Q_80k, "P&L Total Expenses = 80,000 JPY");
         Assert (Lookup_Balance (PL.Net_Income, JPY) = Q_220k, "P&L Net Income = 220,000 JPY");

         Assert (Is_Zero_Balance (TB.Total), "Trial Balance total = 0");
         Assert (Is_Zero_Balance (BS.Accounting_Equation_Delta), "Balance Sheet Accounting Equation (Assets = Liabilities + Equity) Delta = ZERO!");
      end;
   end Test_Report_And_Budget;

   procedure Test_Canonical_Household is
      Tmp_Dir : constant String := "/tmp/aledger_test_household";
      Paths   : constant Source_Paths := Resolve_Source_Paths (Tmp_Dir);
      State   : Household_State;
      Err     : Unbounded_String;
      F       : File_Type;
   begin
      Put_Line ("--- Testing ALedger.Household (Canonical 8-Source Topology) ---");

      --  Create temporary canonical household directory and source files
      if Exists (Tmp_Dir) then
         Delete_Tree (Tmp_Dir);
      end if;
      Create_Directory (Tmp_Dir);

      --  Write accounts.journal
      Create (F, Out_File, To_String (Paths.Accounts_Journal));
      Put_Line (F, "account assets:wallet");
      Put_Line (F, "  ; type: Asset");
      Put_Line (F, "account expenses:coffee");
      Put_Line (F, "  ; type: Expense");
      Close (F);

      --  Write actual.journal
      Create (F, Out_File, To_String (Paths.Actual_Journal));
      Put_Line (F, "2026-08-13 Coffee Purchase");
      Put_Line (F, "    expenses:coffee         500 JPY");
      Put_Line (F, "    assets:wallet          -500 JPY");
      Close (F);

      --  Load Canonical Household Root
      Assert (Load_Canonical_Household (Tmp_Dir, State, Err), "Load Canonical Household root from 8-source topology");
      Assert (Natural (State.Actual_Ledger.Transactions.Length) = 1, "Canonical actual.journal loaded 1 transaction");

      declare
         PL : constant Profit_And_Loss := Generate_Profit_And_Loss (State.Combined_Ledger);
         JPY : constant Commodity := Make_Commodity ("JPY");
         Q_500 : Quantity;
      begin
         Assert (Parse_Quantity ("500", Q_500), "Parse 500");
         Assert (Lookup_Balance (PL.Total_Expenses, JPY) = Q_500, "Combined household P&L Expenses = 500 JPY");
      end;

      --  Cleanup temporary directory
      Delete_Tree (Tmp_Dir);
   end Test_Canonical_Household;

   procedure Test_Plan_Lifecycle is
      PID      : Plan_Id;
      P_Stat   : Plan_Id_Status;
      PE       : Plan_Entry;
      Acc_Bank : constant ALedger.Account.Account := Make_Account ("assets:bank");
      Acc_Rent : constant ALedger.Account.Account := Make_Account ("expenses:rent");
      JPY      : constant Commodity := Make_Commodity ("JPY");
      Q_80k    : Quantity;
      Actual_Tx: Transaction;
      L        : Ledger := Empty_Ledger;
      L_Stat   : Transaction_Error;
   begin
      Put_Line ("--- Testing ALedger.Plan (plan-id & Lifecycle Completion) ---");

      Assert (Create_Plan_Id ("plan-2026-08-001", PID, P_Stat) and then P_Stat = Success, "Create valid plan-id plan-2026-08-001");
      Assert (not Create_Plan_Id ("plan 2026", PID, P_Stat) and then P_Stat = Plan_Id_Contains_Whitespace, "Reject plan-id with whitespace");

      Assert (Parse_Quantity ("80000", Q_80k), "Parse 80000");
      Assert (Create_Plan_Entry ("plan-2026-08-001", "2026-08-25", "Rent Payment August", Make_Amount (JPY, Q_80k), Acc_Bank, Acc_Rent, PE), "Create Plan_Entry");
      Assert (PE.Status = Pending, "New plan entry status is Pending");

      --  Complete Plan (converts plan to actual transaction linking plan-id)
      Assert (Complete_Plan (PE, "2026-08-25", Actual_Tx), "Complete Plan -> Actual Transaction conversion");
      Assert (PE.Status = Completed, "Completed plan status changes to Completed");
      Assert (Is_Balanced (Actual_Tx), "Generated actual transaction preserves strict balance law");

      Assert (Add_Transaction (L, Actual_Tx, L_Stat), "Add generated actual transaction to ledger");

      declare
         Rent_Bal : constant Balance := Compute_Account_Balance (L, Acc_Rent);
         Bank_Bal : constant Balance := Compute_Account_Balance (L, Acc_Bank);
      begin
         Assert (Lookup_Balance (Rent_Bal, JPY) = Q_80k, "Rent expense balance = 80,000 JPY from completed plan");
         Assert (Lookup_Balance (Bank_Bal, JPY) = -Q_80k, "Bank asset balance = -80,000 JPY from completed plan");
      end;
   end Test_Plan_Lifecycle;

   procedure Test_Safe_Writer is
      Target_File : constant String := "/tmp/aledger_test_writer.journal";
      Initial_Text: constant String :=
        "account assets:cash" & ASCII.LF &
        "  ; type: Asset" & ASCII.LF &
        "account expenses:food" & ASCII.LF &
        "  ; type: Expense" & ASCII.LF &
        "" & ASCII.LF &
        "2026-08-13 Lunch" & ASCII.LF &
        "    expenses:food          800 JPY" & ASCII.LF &
        "    assets:cash           -800 JPY" & ASCII.LF;

      New_Tx_Text : constant String :=
        "2026-08-14 Dinner" & ASCII.LF &
        "    expenses:food         1200 JPY" & ASCII.LF &
        "    assets:cash          -1200 JPY" & ASCII.LF;

      W_Stat  : Writer_Status;
      Err_Msg : Unbounded_String;
      F       : File_Type;
   begin
      Put_Line ("--- Testing ALedger.Writer (Safe Writer & Atomic Publication Laws) ---");

      --  1. Setup Initial File
      if Exists (Target_File) then
         Delete_File (Target_File);
      end if;

      Create (F, Out_File, Target_File);
      Put (F, Initial_Text);
      Close (F);

      --  2. Successful Safe Append (Stale check + Backup + Atomic Rename + Post-Admission)
      Assert (Append_Transaction_Safely (Target_File, New_Tx_Text, W_Stat, Err_Msg) and then W_Stat = Success, "Safely append transaction atomically");

      --  3. Test Stale Source Rejection
      Assert (not Atomic_Publish_Journal (Target_File, "WRONG_OLD_CONTENT", "NEW_CONTENT", W_Stat, Err_Msg) and then W_Stat = Stale_Source_Rejected, "Stale source rejection when on-disk content differs");

      --  4. Test Post-Admission Validation Failure & Automatic Restore from Backup
      declare
         Current_Content : Unbounded_String;
         F_Read : File_Type;
         Unbalanced_Invalid_Tx : constant String :=
           "2026-08-15 Unbalanced Invalid Transaction" & ASCII.LF &
           "    expenses:food         1000 JPY" & ASCII.LF &
           "    assets:cash          -500 JPY" & ASCII.LF;  -- Unbalanced!
      begin
         Open (F_Read, In_File, Target_File);
         Current_Content := Null_Unbounded_String;
         while not End_Of_File (F_Read) loop
            Append (Current_Content, Get_Line (F_Read));
            Append (Current_Content, ASCII.LF);
         end loop;
         Close (F_Read);

         Assert (not Append_Transaction_Safely (Target_File, Unbalanced_Invalid_Tx, W_Stat, Err_Msg) and then W_Stat = Post_Admission_Failed, "Post-admission validation fails on unbalanced candidate");

         --  Verify that target file was RESTORED 100% back to Current_Content!
         declare
            Restored_Content : Unbounded_String;
         begin
            Open (F_Read, In_File, Target_File);
            Restored_Content := Null_Unbounded_String;
            while not End_Of_File (F_Read) loop
               Append (Restored_Content, Get_Line (F_Read));
               Append (Restored_Content, ASCII.LF);
            end loop;
            Close (F_Read);

            Assert (To_String (Restored_Content) = To_String (Current_Content), "Target file restored 100% from backup after post-admission failure");
         end;
      end;

      --  Cleanup temporary test file
      if Exists (Target_File) then
         Delete_File (Target_File);
      end if;
   end Test_Safe_Writer;

   procedure Test_Golden_Report_Verification is
      Golden_Journal_Text : constant String :=
        "account assets:cash" & ASCII.LF &
        "  ; type: Asset" & ASCII.LF &
        "account equity:opening" & ASCII.LF &
        "  ; type: Equity" & ASCII.LF &
        "account income:salary" & ASCII.LF &
        "  ; type: Income" & ASCII.LF &
        "account income:refund" & ASCII.LF &
        "  ; type: Income" & ASCII.LF &
        "account expenses:food" & ASCII.LF &
        "  ; type: Expense" & ASCII.LF &
        "account expenses:travel" & ASCII.LF &
        "  ; type: Expense" & ASCII.LF &
        "" & ASCII.LF &
        "2026-04-01 Opening balance" & ASCII.LF &
        "    assets:cash          10000 JPY" & ASCII.LF &
        "    equity:opening      -10000 JPY" & ASCII.LF &
        "" & ASCII.LF &
        "2026-04-15 Spring food" & ASCII.LF &
        "    expenses:food         400 JPY" & ASCII.LF &
        "    assets:cash          -400 JPY" & ASCII.LF &
        "" & ASCII.LF &
        "2026-06-20 Travel" & ASCII.LF &
        "    expenses:travel       800 JPY" & ASCII.LF &
        "    assets:cash          -800 JPY" & ASCII.LF &
        "" & ASCII.LF &
        "2026-07-01 Salary" & ASCII.LF &
        "    assets:cash          5000 JPY" & ASCII.LF &
        "    income:salary       -5000 JPY" & ASCII.LF &
        "" & ASCII.LF &
        "2026-07-10 Food" & ASCII.LF &
        "    expenses:food         600 JPY" & ASCII.LF &
        "    assets:cash          -600 JPY" & ASCII.LF &
        "" & ASCII.LF &
        "2026-07-20 Refund" & ASCII.LF &
        "    assets:cash           100 JPY" & ASCII.LF &
        "    income:refund        -100 JPY" & ASCII.LF &
        "" & ASCII.LF &
        "2026-07-31 Month end food" & ASCII.LF &
        "    expenses:food         300 JPY" & ASCII.LF &
        "    assets:cash          -300 JPY" & ASCII.LF;

      L   : Ledger;
      Err : Unbounded_String;
   begin
      Put_Line ("--- Testing ALedger.Render & Golden Report Contract Conformance ---");

      Assert (Parse_Journal_Text (Golden_Journal_Text, L, Err), "Parse golden contract journal text");

      declare
         Bal_Report : constant String := Render_Account_Balances (L, "2026-07-31");
         BS_Report  : constant String := Render_Balance_Sheet (L, "2026-07-31");
         PL_Report  : constant String := Render_Profit_And_Loss (L, "2026-07-01", "2026-07-31");
      begin
         Assert (Index (Bal_Report, "Balanced: YES") > 0, "Account Balances report verified Balanced: YES");
         Assert (Index (BS_Report, "Balanced: YES (Net Check: 0)") > 0, "Balance Sheet report verified Balanced: YES (Net Check: 0)");
         Assert (Index (PL_Report, "Net Profit (Income - Expenses) | 3000") > 0, "P&L Net Profit strictly matches golden calculation (5,100 - 2,100 = 3,000 JPY)");
      end;
   end Test_Golden_Report_Verification;

begin
   Put_Line ("==================================================");
   Put_Line ("   ALedger Test Suite (v" & ALedger.Version & ")");
   Put_Line ("==================================================");

   Test_Money;
   Test_Account;
   Test_Ledger;
   Test_Journal;
   Test_Report_And_Budget;
   Test_Canonical_Household;
   Test_Plan_Lifecycle;
   Test_Safe_Writer;
   Test_Golden_Report_Verification;

   Put_Line ("--------------------------------------------------");
   Put_Line ("Summary: Passed =" & Natural'Image (Passed_Count) &
             ", Failed =" & Natural'Image (Failed_Count));
   if Failed_Count > 0 then
      Put_Line ("RESULT: FAIL");
   else
      Put_Line ("RESULT: SUCCESS");
   end if;
end Test_Runner;
