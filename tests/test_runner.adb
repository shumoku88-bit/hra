with Ada.Text_IO;          use Ada.Text_IO;
with Ada.Command_Line;
with Ada.Directories;        use Ada.Directories;
with Ada.Strings.Fixed;      use Ada.Strings.Fixed;
with Ada.Strings.Unbounded;  use Ada.Strings.Unbounded;
with ALedger;
with ALedger.Dates;
with ALedger.Money;          use ALedger.Money;
with ALedger.Account;        use ALedger.Account;
with ALedger.Ledger;         use ALedger.Ledger;
with ALedger.Journal;        use ALedger.Journal;
with ALedger.Report;         use ALedger.Report;
with ALedger.Household;      use ALedger.Household;
with ALedger.Household_Config;
with ALedger.Canonical_Source; use ALedger.Canonical_Source;
with ALedger.Config_Support;
with ALedger.Budget_Config;
with ALedger.Report_Config;
with ALedger.Proof_Core;
with ALedger.Plan;           use ALedger.Plan;
with ALedger.Writer;         use ALedger.Writer;
with ALedger.Render;         use ALedger.Render;
with ALedger.Envelope;
with ALedger.Envelope_Routing;
with ALedger.Envelope_Entitlement;
with ALedger.Budget_Source_Adapter;
with ALedger.Envelope_Consumption;
with ALedger.Backing_Policy;

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

   function D (S : String) return ALedger.Dates.Date is
      Val    : ALedger.Dates.Date;
      Status : ALedger.Dates.Date_Status;
   begin
      if not ALedger.Dates.Parse (S, Val, Status) then
         raise Program_Error with "Invalid date in test: " & S;
      end if;
      return Val;
   end D;

   function P (S1, S2 : String) return ALedger.Dates.Closed_Period is
      Res : ALedger.Dates.Closed_Period;
   begin
      if not ALedger.Dates.Make_Closed_Period (D (S1), D (S2), Res) then
         raise Program_Error with "Invalid closed period: " & S1 & ".." & S2;
      end if;
      return Res;
   end P;

   procedure Test_Proof_Core is
      package Proof renames ALedger.Proof_Core;
      Original : constant Proof.Posting_Array :=
        [1 => (Account => 1, Commodity => 1, Quantity => 1_000),
         2 => (Account => 2, Commodity => 1, Quantity => -1_000),
         3 => (Account => 1, Commodity => 2, Quantity => 50),
         4 => (Account => 3, Commodity => 2, Quantity => -50)];
      Reversal : constant Proof.Posting_Array :=
        [1 => (Account => 1, Commodity => 1, Quantity => -1_000),
         2 => (Account => 2, Commodity => 1, Quantity => 1_000),
         3 => (Account => 1, Commodity => 2, Quantity => -50),
         4 => (Account => 3, Commodity => 2, Quantity => 50)];
      Unreserved : constant Proof.Atomic_Quanta :=
        Proof.Unreserved_Obligation
          ((Amount => 500, Already_Excluded => 150));
      Envelope : constant Proof.Envelope_Result := Proof.Evaluate_Envelope
        ((Entitlement => 1_000,
          Consumption => 400,
          Refunds => 100,
          Plan_Reserve => 200));
      Lines : constant Proof.Envelope_Result_Array :=
        [1 => Envelope,
         2 => (Remaining => -100, Post_Plan_Headroom => -100)];
      Backing : constant Proof.Backing_Result := Proof.Evaluate_Backing
        (Lines, (Funding_Balance => 1_200, Unassigned_Balance => 100));
   begin
      Put_Line ("--- Testing ALedger.Proof_Core contracts ---");
      Assert (Proof.Is_Balanced (Original), "Proof core balances each Commodity independently");
      Assert (Proof.Is_Ordered_Inverse (Original, Reversal), "Proof core recognizes exact ordered reversal");
      Assert
        (Unreserved = 350,
         "Proof core deducts only bounded exclusion from a Plan obligation");
      Assert
        (Envelope.Remaining = 700 and then Envelope.Post_Plan_Headroom = 500,
         "Proof core preserves Envelope remaining and Plan headroom equations");
      Assert
        (Backing.Signed_Total = 600 and then
         Backing.Backing_Required = 700 and then
         Backing.Backing_Surplus = 500 and then
         Backing.Reconciliation_Delta = 400 and then
         not Backing.Is_Under_Backed,
         "Proof core preserves Backing and reconciliation equations");
   end Test_Proof_Core;

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

      Assert (Render_Quantity (Q1) = "1,000", "Render quantity 1,000");
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
      Acc1, Acc2, Acc_Undeclared : ALedger.Account.Account;
      A_Status     : Account_Status;
      Reg          : Account_Registry := Empty_Registry;
      R_Status     : Registry_Status;
      Decl1, Decl2 : Account_Declaration;
   begin
      Put_Line ("--- Testing ALedger.Account ---");

      Assert (Create_Account ("assets:bank:checking", Acc1, A_Status), "Create Account assets:bank:checking");
      Assert (Create_Account ("expenses:food", Acc2, A_Status), "Create Account expenses:food");
      Assert (Create_Account ("income:freelance", Acc_Undeclared, A_Status), "Create Account income:freelance");

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
         Assert (not Account_Type_For (Reg, Acc_Undeclared, Found_AT),
                "Undeclared Account_Type lookup fails closed");
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

      Assert (Create_Transaction (D ("2026-08-13"), "Grocery Purchase", Postings, Tx, T_Status), "Create balanced transaction");
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

      --  Test flexible amount parsing
      declare
         Flex_Journal : constant String :=
           "2026-08-14 Multi Currency Flexible Formats" & ASCII.LF &
           "    expenses:groceries     JPY 2,500" & ASCII.LF &
           "    expenses:software      $50.00" & ASCII.LF &
           "    assets:bank:usd        -50 USD" & ASCII.LF &
           "    assets:cash            -2500 JPY" & ASCII.LF;
         L_Flex : Ledger;
      begin
         Assert (Parse_Journal_Text (Flex_Journal, L_Flex, Err), "Parse flexible currency & comma formats (JPY 2,500, $50.00)");
         Assert (Natural (L_Flex.Transactions.Length) = 1, "Parsed flexible transaction successfully");
      end;

      --  Test Parse_Diagnostic Tracing and Location formatting
      declare
         Invalid_Journal : constant String :=
           "; line 1 comment" & ASCII.LF &
           "2026-08-15 Unbalanced Tx" & ASCII.LF &
           "    expenses:food      1000 JPY" & ASCII.LF &
           "    assets:cash        -500 JPY" & ASCII.LF;
         L_Err : Ledger;
         Diag  : Parse_Diagnostic;
      begin
         Assert (not Parse_Journal_Text (Invalid_Journal, "actual.journal", L_Err, Diag), "Reject unbalanced transaction with diagnostic");
         Assert (To_String (Diag.File_Name) = "actual.journal", "Diagnostic captures correct File_Name");
         Assert (Diag.Line_Number > 0, "Diagnostic captures correct Line_Number");
         Assert (Index (Format_Diagnostic (Diag), "actual.journal:") > 0, "Format_Diagnostic renders file location trace");
      end;

      declare
         Invalid_Document : constant String := "THIS IS NOT A JOURNAL" & ASCII.LF;
         L_Err            : Ledger;
         Diag             : Parse_Diagnostic;
      begin
         Assert
           (not Parse_Journal_Text (Invalid_Document, "invalid.journal", L_Err, Diag),
            "Reject unsupported top-level journal content");
      end;
   end Test_Journal;

   procedure Test_TOML_Config_Admission is
      Diag   : ALedger.Config_Support.Config_Diagnostic;
      Policy : ALedger.Budget_Config.Budget_Policy;
      Report : ALedger.Report_Config.Report_Configuration;
      Food_UTF8 : constant String :=
        Character'Val (16#E9#) & Character'Val (16#A3#) & Character'Val (16#9F#) &
        Character'Val (16#E8#) & Character'Val (16#B2#) & Character'Val (16#BB#);
      Valid_Budget : constant String :=
        "[[backing-pools]]" & ASCII.LF &
        "id = ""liquid""" & ASCII.LF &
        "asset-accounts = [""assets:cash""]" & ASCII.LF &
        "[[envelopes]]" & ASCII.LF &
        "id = """ & Food_UTF8 & """" & ASCII.LF &
        "label = """ & Food_UTF8 & """" & ASCII.LF &
        "pacing = ""daily""" & ASCII.LF &
        "backing-pool = ""liquid""" & ASCII.LF &
        "expense-accounts = [""expenses:food""]" & ASCII.LF;
      Budget_With_History : constant String :=
        "[[backing-pools]]" & ASCII.LF &
        "id = ""liquid""" & ASCII.LF &
        "asset-accounts = [""assets:cash""]" & ASCII.LF &
        "[[envelopes]]" & ASCII.LF &
        "id = """ & Food_UTF8 & """" & ASCII.LF &
        "label = """ & Food_UTF8 & """" & ASCII.LF &
        "pacing = ""daily""" & ASCII.LF &
        "backing-pool = ""liquid""" & ASCII.LF &
        "expense-accounts = [""expenses:food""]" & ASCII.LF;
      Household_With_History : constant String :=
        "[cycle]" & ASCII.LF &
        "mode = ""income-anchor""" & ASCII.LF &
        "income-account = ""income:salary""" & ASCII.LF &
        "[budget]" & ASCII.LF &
        "unassigned-accounts = [""budget:unassigned""]" & ASCII.LF &
        "[[budget.envelopes]]" & ASCII.LF &
        "id = """ & Food_UTF8 & """" & ASCII.LF &
        "allocation-account = ""budget:" & Food_UTF8 & """" & ASCII.LF &
        "[envelope-history]" & ASCII.LF &
        "identities = [""" & Food_UTF8 & """]" & ASCII.LF &
        "[[envelope-history.expense-routing]]" & ASCII.LF &
        "effective-from = ""initial""" & ASCII.LF &
        "expense-account = ""expenses:food""" & ASCII.LF &
        "route = ""managed""" & ASCII.LF &
        "target = """ & Food_UTF8 & """" & ASCII.LF &
        "note = ""test routing""" & ASCII.LF;
      Invalid_Report : constant String :=
        "[reports.trial-balance]" & ASCII.LF &
        "as-of = ""2026-02-30""" & ASCII.LF &
        "[reports.balance-sheet]" & ASCII.LF &
        "as-of = ""latest""" & ASCII.LF &
        "[reports.profit-and-loss]" & ASCII.LF &
        "from = ""beginning""" & ASCII.LF &
        "through = ""latest""" & ASCII.LF &
        "[reports.daily-flow]" & ASCII.LF &
        "from = ""beginning""" & ASCII.LF &
        "through = ""latest""" & ASCII.LF &
        "[reports.monthly-accounts]" & ASCII.LF &
        "from = ""beginning""" & ASCII.LF &
        "through = ""latest""" & ASCII.LF &
        "[reports.recent-transactions]" & ASCII.LF &
        "through = ""latest""" & ASCII.LF &
        "count = 5" & ASCII.LF;
   begin
      Put_Line ("--- Testing typed canonical TOML admission ---");
      Assert
        (ALedger.Budget_Config.Parse_Budget_Policy
           (Valid_Budget, Policy, Diag) and then
         To_String (Policy.Envelopes.Element (1).ID) = Food_UTF8,
         "Admit UTF-8 Budget policy into typed values");
      Assert
        (not ALedger.Budget_Config.Parse_Budget_Policy
           (Valid_Budget & "unknown = true" & ASCII.LF, Policy, Diag),
         "Reject unknown Budget TOML key");
      Assert
        (not ALedger.Report_Config.Parse_Report_Configuration
           (Invalid_Report, Report, Diag),
         "Reject impossible Report date");

      --  Test envelope-history parsing in household_config
      declare
         use type ALedger.Household_Config.Effective_Date_Kind;
         use type ALedger.Household_Config.Expense_Route_Kind;
         History_Policy : ALedger.Budget_Config.Budget_Policy;
         History_Diag   : ALedger.Config_Support.Config_Diagnostic;
         Household_Diag : ALedger.Config_Support.Config_Diagnostic;
         Household_Cfg  : ALedger.Household_Config.Household_Configuration;
      begin
         --  First parse budget_config (needed for household_config)
         Assert
           (ALedger.Budget_Config.Parse_Budget_Policy
              (Budget_With_History, History_Policy, History_Diag),
            "Admit Budget policy with envelope-history section");

         --  Now parse household_config with envelope-history
         Assert
           (ALedger.Household_Config.Parse_Household_Configuration
              (Household_With_History, History_Policy, Household_Cfg, Household_Diag),
            "Admit Household configuration with envelope-history section");
         Assert
           (Natural (Household_Cfg.Envelope_History.Identities.Length) = 1,
            "Envelope-history parsed 1 identity");
         Assert
           (Household_Cfg.Envelope_History.Identities.Element (1) = Food_UTF8,
            "Envelope-history identity matches UTF-8 food name");
         Assert
           (Natural (Household_Cfg.Envelope_History.Expense_Routing.Length) = 1,
            "Envelope-history parsed 1 expense-routing entry");
         declare
            E : constant ALedger.Household_Config.Expense_Routing_Entry_Data :=
              Household_Cfg.Envelope_History.Expense_Routing.Element (1);
         begin
            Assert
              (E.Effective.Kind = ALedger.Household_Config.Initial,
               "Expense-routing effective-from is 'initial'");
            Assert
              (To_String (E.Expense_Account) = "expenses:food",
               "Expense-routing expense-account is 'expenses:food'");
            Assert
              (E.Route.Kind = ALedger.Household_Config.Managed,
               "Expense-routing route is 'managed'");
            Assert
              (To_String (E.Route.Target) = Food_UTF8,
               "Expense-routing target matches UTF-8 food name");
            Assert
              (To_String (E.Note) = "test routing",
               "Expense-routing note is preserved");
         end;
      end;
   end Test_TOML_Config_Admission;

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
      Paths   : constant ALedger.Household.Source_Paths :=
        ALedger.Household.Resolve_Source_Paths (Tmp_Dir);
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
      Put_Line (F, "account income:salary");
      Put_Line (F, "  ; type: Income");
      Put_Line (F, "account budget:coffee");
      Put_Line (F, "  ; type: Budget");
      Put_Line (F, "account budget:unassigned");
      Put_Line (F, "  ; type: Budget");
      Close (F);

      --  Write actual.journal
      Create (F, Out_File, To_String (Paths.Actual_Journal));
      Put_Line (F, "2026-08-13 Coffee Purchase");
      Put_Line (F, "    expenses:coffee         500 JPY");
      Put_Line (F, "    assets:wallet          -500 JPY");
      Close (F);

      --  A partial root must never be accepted as the canonical topology.
      Assert
        (not Load_Canonical_Household (Tmp_Dir, State, Err),
         "Reject incomplete canonical Household root");

      --  Complete the fixed eight-source topology.  TOML policy admission is
      --  intentionally a later chapter, but exact source observation starts now.
      Create (F, Out_File, To_String (Paths.Plan_Journal));
      Put_Line (F, "INVALID PLAN SOURCE");
      Close (F);
      Create (F, Out_File, To_String (Paths.Budget_Journal));
      Close (F);
      Create (F, Out_File, To_String (Paths.Budget_TOML));
      Put_Line (F, "[[backing-pools]]");
      Put_Line (F, "id = ""liquid""");
      Put_Line (F, "asset-accounts = [""assets:wallet""]");
      Put_Line (F, "[[envelopes]]");
      Put_Line (F, "id = ""coffee""");
      Put_Line (F, "label = ""Coffee""");
      Put_Line (F, "pacing = ""daily""");
      Put_Line (F, "backing-pool = ""liquid""");
      Put_Line (F, "expense-accounts = [""expenses:coffee""]");
      Close (F);
      Create (F, Out_File, To_String (Paths.Household_TOML));
      Put_Line (F, "[cycle]");
      Put_Line (F, "mode = ""income-anchor""");
      Put_Line (F, "income-account = ""income:salary""");
      Put_Line (F, "[money]");
      Put_Line (F, "primary-commodity = ""JPY""");
      Put_Line (F, "[budget]");
      Put_Line (F, "unassigned-accounts = [""budget:unassigned""]");
      Put_Line (F, "[[budget.envelopes]]");
      Put_Line (F, "id = ""coffee""");
      Put_Line (F, "allocation-account = ""budget:coffee""");
      Close (F);
      Create (F, Out_File, To_String (Paths.Report_TOML));
      Put_Line (F, "[presentation.amounts]");
      Put_Line (F, "negative-style = ""parentheses""");
      Put_Line (F, "[reports.trial-balance]");
      Put_Line (F, "as-of = ""latest""");
      Put_Line (F, "[reports.balance-sheet]");
      Put_Line (F, "as-of = ""latest""");
      Put_Line (F, "[reports.profit-and-loss]");
      Put_Line (F, "from = ""beginning""");
      Put_Line (F, "through = ""latest""");
      Put_Line (F, "[reports.daily-flow]");
      Put_Line (F, "from = ""beginning""");
      Put_Line (F, "through = ""latest""");
      Put_Line (F, "max-date-columns = 7");
      Put_Line (F, "[reports.monthly-accounts]");
      Put_Line (F, "from = ""beginning""");
      Put_Line (F, "through = ""latest""");
      Put_Line (F, "[reports.recent-transactions]");
      Put_Line (F, "through = ""latest""");
      Put_Line (F, "count = 10");
      Close (F);
      Create (F, Out_File, To_String (Paths.Issues_TSV));
      Put_Line (F, "issue_id" & ASCII.HT & "status");
      Close (F);

      Assert
        (not Load_Canonical_Household (Tmp_Dir, State, Err),
         "Reject malformed source instead of silently dropping it");
      Create (F, Out_File, To_String (Paths.Plan_Journal));
      Close (F);

      Assert (Load_Canonical_Household (Tmp_Dir, State, Err), "Load complete canonical Household root from fixed 8-source topology");
      Assert (Natural (State.Actual_Ledger.Transactions.Length) = 1, "Canonical actual.journal loaded 1 transaction");
      Assert
        (State.Household_Policy.Has_Primary_Commodity and then
         Code (State.Household_Policy.Primary_Commodity) = "JPY" and then
         Natural (State.Budget_Policy.Envelopes.Length) = 1 and then
         State.Report_Policy.Presentation.Daily_Date_Columns = 7,
         "Canonical TOML sources admit typed policy values");
      Assert
        (Text_For (State.Sources, Actual_Source) =
           "2026-08-13 Coffee Purchase" & ASCII.LF &
           "    expenses:coffee         500 JPY" & ASCII.LF &
           "    assets:wallet          -500 JPY" & ASCII.LF,
         "Canonical observation retains exact actual.journal source bytes");

      declare
         PL : constant Profit_And_Loss := Generate_Profit_And_Loss (State.Combined_Ledger);
         JPY : constant Commodity := Make_Commodity ("JPY");
         Q_500 : Quantity;
         BS_Text : constant String := Render_Budget_Status (State);
      begin
         Assert (Parse_Quantity ("500", Q_500), "Parse 500");
         Assert (Lookup_Balance (PL.Total_Expenses, JPY) = Q_500, "Combined household P&L Expenses = 500 JPY");
         Assert (Index (BS_Text, "== Envelope & Backing ==") > 0, "Render Envelope & Backing header");
         Assert (Index (BS_Text, "coffee") > 0, "Render Envelope coffee line");
         Assert (Index (BS_Text, "Funding balance (liquid)") > 0, "Render liquid pool backing evidence");
      end;

      Open (F, Append_File, To_String (Paths.Report_TOML));
      Put_Line (F, "unknown-coordinate = true");
      Close (F);
      Assert
        (not Load_Canonical_Household (Tmp_Dir, State, Err) and then
         Index (To_String (Err), "unknown key") > 0,
         "Reject unknown TOML coordinates instead of silently ignoring them");

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
      Assert (Create_Plan_Entry ("plan-2026-08-001", D ("2026-08-25"), "Rent Payment August", Make_Amount (JPY, Q_80k), Acc_Bank, Acc_Rent, PE), "Create Plan_Entry");
      Assert (PE.Status = Pending, "New plan entry status is Pending");

      --  Complete Plan (converts plan to actual transaction linking plan-id)
      Assert (Complete_Plan (PE, D ("2026-08-25"), Actual_Tx), "Complete Plan -> Actual Transaction conversion");
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

         Assert (not Append_Transaction_Safely (Target_File, Unbalanced_Invalid_Tx, W_Stat, Err_Msg) and then (W_Stat = Pre_Admission_Failed or else W_Stat = Post_Admission_Failed), "Pre/Post-admission validation fails on unbalanced candidate");

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
        "    assets:cash          -300 JPY" & ASCII.LF &
        "" & ASCII.LF &
        "2026-08-01 After contract as-of" & ASCII.LF &
        "    expenses:food          50 JPY" & ASCII.LF &
        "    assets:cash           -50 JPY" & ASCII.LF;

      L   : Ledger;
      Err : Unbounded_String;
   begin
      Put_Line ("--- Testing ALedger & h-kernel Cross-Engine Equivalence ---");

      Assert (Parse_Journal_Text (Golden_Journal_Text, L, Err), "Parse h-kernel report contract journal text");

      declare
         Bal_Report : constant String := Render_Account_Balances (L, D ("2026-07-31"));
         BS_Report  : constant String := Render_Balance_Sheet (L, D ("2026-07-31"));
         PL_Report  : constant String := Render_Profit_And_Loss (L, P ("2026-07-01", "2026-07-31"));

         BS_Obj     : constant Balance_Sheet := Generate_Balance_Sheet_As_Of (L, D ("2026-07-31"));
         PL_Obj     : constant Profit_And_Loss := Generate_Profit_And_Loss_Period (L, P ("2026-07-01", "2026-07-31"));
      begin
         --  Verify Account Balances as-of 2026-07-31 (excluding 2026-08-01 transaction)
         Assert (Index (Bal_Report, "assets:cash | 13,000 JPY") > 0, "Equivalence: assets:cash = 13,000 JPY as of 2026-07-31");
         Assert (Index (Bal_Report, "Balanced: YES") > 0, "Account Balances verified Balanced: YES");

         --  Verify Balance Sheet as-of 2026-07-31
         Assert (Index (BS_Report, "Total assets | 13,000 JPY") > 0, "Equivalence: Balance Sheet Total Assets = 13,000 JPY");
         Assert (Index (BS_Report, "Current earnings | 3,000 JPY") > 0, "Equivalence: Balance Sheet Current Earnings = 3,000 JPY");
         Assert (Index (BS_Report, "Total equity     | 13,000 JPY") > 0, "Equivalence: Balance Sheet Total Equity = 13,000 JPY");
         Assert (Is_Zero_Balance (BS_Obj.Accounting_Equation_Delta), "Equivalence: Accounting Equation Delta is strictly ZERO");

         --  Verify July Period Profit & Loss (2026-07-01 .. 2026-07-31)
         Assert (Index (PL_Report, "Total Income  | 5,100 JPY") > 0, "Equivalence: July Total Income = 5,100 JPY");
         Assert (Index (PL_Report, "Total Expenses                 | 900 JPY") > 0, "Equivalence: July Total Expenses = 900 JPY");
         Assert (Index (PL_Report, "Net Profit (Income - Expenses) | 4,200 JPY") > 0, "Equivalence: July Net Profit strictly matches h-kernel (4,200 JPY)");
         Assert (not Is_Zero_Balance (PL_Obj.Net_Income), "Equivalence: PL_Obj.Net_Income object is non-zero");
      end;
   end Test_Golden_Report_Verification;

   procedure Test_Envelope_Identity_And_Registry is
      use ALedger.Envelope;
      use ALedger.Config_Support;
      Id, Food_Id : Envelope_Id;
      Status   : Envelope_Id_Status;
      Reg      : Envelope_Registry;
      Diag     : Config_Diagnostic;
      Names    : String_Vectors.Vector;
   begin
      Put_Line ("--- Testing ALedger.Envelope (Identity & Registry) ---");

      --  Valid identity creation
      Assert (Create_Envelope_Id ("food", Id, Status)
              and then Status = Success,
              "Create Envelope_Id from valid identity ""food""");
      Assert (Image (Id) = "food",
              "Image returns original identity string ""food""");

      --  Reject empty identity
      Assert (not Create_Envelope_Id ("", Id, Status)
              and then Status = Empty_Identity,
              "Reject empty Envelope identity");

      --  Reject leading whitespace
      Assert (not Create_Envelope_Id (" food", Id, Status)
              and then Status = Leading_Or_Trailing_Whitespace,
              "Reject Envelope identity with leading whitespace");

      --  Reject trailing whitespace
      Assert (not Create_Envelope_Id ("food ", Id, Status)
              and then Status = Leading_Or_Trailing_Whitespace,
              "Reject Envelope identity with trailing whitespace");

      --  Reject control characters
      Assert (not Create_Envelope_Id ("fo" & ASCII.NUL & "od", Id, Status)
              and then Status = Identity_Contains_Control,
              "Reject Envelope identity containing control character");

      --  Internal colon is valid (sub-envelope identity)
      Assert (Create_Envelope_Id ("food:stock", Id, Status)
              and then Status = Success,
              "Accept sub-envelope identity with internal colon");
      Assert (Image (Id) = "food:stock",
              "Image preserves sub-envelope identity string");

      --  UTF-8 identity (same bytes as budget.toml 食費)
      declare
         Food_UTF8 : constant String :=
           Character'Val (16#E9#) & Character'Val (16#A3#) & Character'Val (16#9F#) &
           Character'Val (16#E8#) & Character'Val (16#B2#) & Character'Val (16#BB#);
      begin
         Assert (Create_Envelope_Id (Food_UTF8, Id, Status)
                 and then Status = Success,
                 "Accept UTF-8 multi-byte Envelope identity");
         Assert (Image (Id) = Food_UTF8,
                 "Image round-trips UTF-8 identity bytes exactly");
      end;

      --  Envelope Id equality
      declare
         A, B : Envelope_Id;
         S    : Envelope_Id_Status;
      begin
         Assert (Create_Envelope_Id ("x", A, S) and then S = Success,
                 "Create first Envelope_Id for equality test");
         Assert (Create_Envelope_Id ("x", B, S) and then S = Success,
                 "Create second Envelope_Id for equality test");
         Assert (A = B, "Two Envelope_Ids from same name are equal");
      end;

      --  Registry: empty admission fails
      Names.Clear;
      Assert (not Admit_Registry (Names, Reg, Diag),
              "Reject registry admission with zero identities");

      --  Registry: valid admission
      Names.Clear;
      Names.Append ("food");
      Names.Append ("tabaco");
      Names.Append ("food:stock");
      Assert (Admit_Registry (Names, Reg, Diag),
              "Admit registry with three distinct Envelope identities");

      --  Registry: Contains
      Assert (Contains (Reg, "food"),
              "Registry contains admitted identity ""food""");
      Assert (not Contains (Reg, "nonexistent"),
              "Registry does not contain unadmitted identity");

      --  Registry: Lookup
      Assert (Lookup (Reg, "food", Food_Id),
              "Lookup succeeds for admitted identity ""food""");
      Assert (Image (Food_Id) = "food",
              "Looked up identity has correct Image");
      Assert (not Lookup (Reg, "nonexistent", Food_Id),
              "Lookup fails for unadmitted identity");

      --  Registry: Length
      Assert (Length (Reg) = 3,
              "Registry length equals admitted identity count");

      --  Registry: All_Ids returns sorted array
      declare
         Ids : constant Envelope_Id_Array := All_Ids (Reg);
      begin
         Assert (Ids'Length = 3, "All_Ids returns array of correct length");
         Assert (Image (Ids (1)) = "food", "All_Ids first element in sort order");
         Assert (Image (Ids (2)) = "food:stock", "All_Ids second element in sort order");
         Assert (Image (Ids (3)) = "tabaco", "All_Ids third element in sort order");
      end;

      --  Registry: duplicate rejection
      Names.Clear;
      Names.Append ("food");
      Names.Append ("food");
      Assert (not Admit_Registry (Names, Reg, Diag),
              "Reject registry admission with duplicate identities");

      --  Registry: invalid identity rejection
      Names.Clear;
      Names.Append ("valid");
      Names.Append ("");
      Assert (not Admit_Registry (Names, Reg, Diag),
              "Reject registry admission containing invalid identity");

      --  Envelope Id is NOT an Account (type-level separation)
      declare
         Env : Envelope_Id;
         Acc : ALedger.Account.Account;
         S   : Envelope_Id_Status;
      begin
         Assert (Create_Envelope_Id ("food", Env, S) and then S = Success,
                 "Create Envelope_Id for type-separation test");
         Acc := ALedger.Account.Make_Account ("food");
         Assert (Image (Env) = ALedger.Account.Name (Acc),
                 "Envelope and Account can share the same surface string");
         --  But they are different types: Envelope_Id /= Account
         --  The type system prevents confusing them
      end;
   end Test_Envelope_Identity_And_Registry;

   procedure Test_Envelope_Routing is
      use ALedger.Envelope;
      use ALedger.Envelope_Routing;
      Food_Acc   : constant Account := Make_Account ("expenses:food");
      Rent_Acc   : constant Account := Make_Account ("expenses:rent");
      Reg      : Envelope_Registry;
      Reg_Diag : ALedger.Config_Support.Config_Diagnostic;
      Hist     : Routing_History;
      Status   : History_Status;
      Names    : ALedger.Config_Support.String_Vectors.Vector;
      Entries  : Routing_Entry_Vectors.Vector;
   begin
      Put_Line ("--- Testing ALedger.Envelope_Routing ---");

      --  Setup: create a registry with two envelopes
      Names.Append ("food");
      Names.Append ("tabaco");
      Assert (Admit_Registry (Names, Reg, Reg_Diag),
              "Setup: admit registry with food and tabaco");

      --  Valid routing entry (initial, managed)
      declare
         Food_Id : Envelope_Id;
         Id_Status : Envelope_Id_Status;
         E : Routing_Entry;
      begin
         Assert (Create_Envelope_Id ("food", Food_Id, Id_Status)
                 and then Id_Status = Success,
                 "Setup: create food Envelope_Id");
         E := (Effective => Initial_Effective_Date,
               Expense   => Food_Acc,
               Route     => Managed_Route (Food_Id),
               Note      => Null_Unbounded_String);
         Entries.Append (E);
      end;

      --  Valid routing entry (initial, not managed)
      declare
         E : Routing_Entry;
      begin
         E := (Effective => Initial_Effective_Date,
               Expense   => Rent_Acc,
               Route     => Not_Managed_Route,
               Note      => Null_Unbounded_String);
         Entries.Append (E);
      end;

      --  Admit valid history
      Assert (Admit (Entries, Reg, Hist, Status)
              and then Status = Success,
              "Admit routing history with two entries");
      Assert (Length (Hist) = 2, "History length is 2");

      --  Resolve: food should be managed
      declare
         R : constant Expense_Route := Resolve (Hist, Food_Acc, D ("2026-08-15"));
      begin
         Assert (R.Kind = Managed_By_Envelope, "Resolve food: managed");
         Assert (Image (R.Target) = "food", "Resolve food: target is food");
      end;

      --  Resolve: rent should be not managed
      declare
         R : constant Expense_Route := Resolve (Hist, Rent_Acc, D ("2026-08-15"));
      begin
         Assert (R.Kind = Not_Envelope_Managed, "Resolve rent: not managed");
      end;

      --  Resolve: unknown account should be not managed
      declare
         Unknown_Acc : constant Account := Make_Account ("expenses:unknown");
         R : constant Expense_Route := Resolve (Hist, Unknown_Acc, D ("2026-08-15"));
      begin
         Assert (R.Kind = Not_Envelope_Managed,
                 "Resolve unknown: not managed (no routing)");
      end;

      --  Has_Routing: food has routing
      Assert (Has_Routing (Hist, Food_Acc), "Has_Routing: food has routing");

      --  Has_Routing: unknown does not have routing
      declare
         Unknown_Acc : constant Account := Make_Account ("expenses:unknown");
      begin
         Assert (not Has_Routing (Hist, Unknown_Acc),
                 "Has_Routing: unknown has no routing");
      end;

      --  Reject: duplicate routing (same account, same effective date)
      declare
         Dup_Entries : Routing_Entry_Vectors.Vector;
         Food_Id : Envelope_Id;
         Id_Status : Envelope_Id_Status;
         E : Routing_Entry;
      begin
         Assert (Create_Envelope_Id ("food", Food_Id, Id_Status)
                 and then Id_Status = Success,
                 "Create food Envelope_Id for duplicate routing test");
         E := (Effective => Initial_Effective_Date,
               Expense   => Food_Acc,
               Route     => Managed_Route (Food_Id),
               Note      => Null_Unbounded_String);
         Dup_Entries.Append (E);
         Dup_Entries.Append (E);  -- duplicate
         declare
            Dup_Hist : Routing_History;
            Dup_Status : History_Status;
         begin
            Assert (not Admit (Dup_Entries, Reg, Dup_Hist, Dup_Status)
                    and then Dup_Status = Duplicate_Routing_Entry,
                    "Reject duplicate routing entry");
         end;
      end;

      --  Reject: unknown envelope in route
      declare
         Bad_Entries : Routing_Entry_Vectors.Vector;
         Fake_Id : Envelope_Id;
         Id_Status : Envelope_Id_Status;
         E : Routing_Entry;
      begin
         Assert (Create_Envelope_Id ("fake", Fake_Id, Id_Status)
                 and then Id_Status = Success,
                 "Setup: create fake Envelope_Id for unknown route test");
         E := (Effective => Initial_Effective_Date,
               Expense   => Food_Acc,
               Route     => Managed_Route (Fake_Id),
               Note      => Null_Unbounded_String);
         Bad_Entries.Append (E);
         declare
            Bad_Hist : Routing_History;
            Bad_Status : History_Status;
         begin
            Assert (not Admit (Bad_Entries, Reg, Bad_Hist, Bad_Status)
                    and then Bad_Status = Unknown_Envelope_In_Route,
                    "Reject routing with unknown envelope");
         end;
      end;

      --  Date precedence: dated entry beats initial
      declare
         Dated_Entries : Routing_Entry_Vectors.Vector;
         Food_Id, Tabaco_Id : Envelope_Id;
         Id_Status : Envelope_Id_Status;
         E : Routing_Entry;
         Dated_Hist : Routing_History;
         Dated_Status : History_Status;
      begin
         Assert (Create_Envelope_Id ("food", Food_Id, Id_Status)
                 and then Id_Status = Success,
                 "Setup: create food Envelope_Id for dated precedence test");
         Assert (Create_Envelope_Id ("tabaco", Tabaco_Id, Id_Status)
                 and then Id_Status = Success,
                 "Setup: create tabaco Envelope_Id for dated precedence test");

         --  Initial: food -> food
         E := (Effective => Initial_Effective_Date,
               Expense   => Food_Acc,
               Route     => Managed_Route (Food_Id),
               Note      => Null_Unbounded_String);
         Dated_Entries.Append (E);

         --  From 2026-09-01: food -> tabaco
         E := (Effective => Dated_Effective (D ("2026-09-01")),
               Expense   => Food_Acc,
               Route     => Managed_Route (Tabaco_Id),
               Note      => Null_Unbounded_String);
         Dated_Entries.Append (E);

         Assert (Admit (Dated_Entries, Reg, Dated_Hist, Dated_Status)
                 and then Dated_Status = Success,
                 "Admit history with initial + dated entries");

         --  Before 2026-09-01: should resolve to food
         declare
            R : constant Expense_Route := Resolve (Dated_Hist, Food_Acc, D ("2026-08-15"));
         begin
            Assert (R.Kind = Managed_By_Envelope
                    and then Image (R.Target) = "food",
                    "Resolve before date: initial wins (food)");
         end;

         --  On 2026-09-01: should resolve to tabaco
         declare
            R : constant Expense_Route := Resolve (Dated_Hist, Food_Acc, D ("2026-09-01"));
         begin
            Assert (R.Kind = Managed_By_Envelope
                    and then Image (R.Target) = "tabaco",
                    "Resolve on date: dated entry wins (tabaco)");
         end;

         --  After 2026-09-01: should still resolve to tabaco
         declare
            R : constant Expense_Route := Resolve (Dated_Hist, Food_Acc, D ("2026-12-31"));
         begin
            Assert (R.Kind = Managed_By_Envelope
                    and then Image (R.Target) = "tabaco",
                    "Resolve after date: dated entry still wins (tabaco)");
         end;
      end;
   end Test_Envelope_Routing;

   procedure Test_Reversal_Law is
      L : Ledger := Empty_Ledger;
      JPY : constant Commodity := Make_Commodity ("JPY");
      Acc_Asset : constant ALedger.Account.Account := Make_Account ("assets:cash");
      Acc_Expense : constant ALedger.Account.Account := Make_Account ("expenses:gadgets");
      Q_5000 : Quantity;
      Postings : Posting_Vectors.Vector;
      Orig_Tx, Rev_Tx : Transaction;
      Status : Transaction_Error;
   begin
      Put_Line ("--- Testing ALedger Reversal Law & Durable Identity ---");

      Assert (Parse_Quantity ("5000", Q_5000), "Parse 5000 for Reversal test");
      Postings.Append (Make_Posting (Acc_Expense, Make_Amount (JPY, Q_5000)));
      Postings.Append (Make_Posting (Acc_Asset, Make_Amount (JPY, -Q_5000)));

      Assert (Create_Transaction (D ("2026-08-10"), "Gadget Purchase [event-id: evt-2026-001]", Postings, Orig_Tx, Status), "Create original transaction");
      Orig_Tx.Event_ID := To_Unbounded_String ("evt-2026-001");
      Assert (Add_Transaction (L, Orig_Tx, Status), "Add original transaction to ledger");

      Assert (Create_Reversal_Transaction (Orig_Tx, "evt-2026-002", D ("2026-08-11"), "Return gadget", Rev_Tx, Status), "Create reversal transaction via Reversal Law");
      Assert (Is_Reversal_Of (Rev_Tx, Orig_Tx), "Verify Is_Reversal_Of relation");

      declare
         Bad_Rev : Transaction := Rev_Tx;
         P       : Posting := Bad_Rev.Postings.Element (1);
      begin
         P.Acc := Acc_Asset;
         Bad_Rev.Postings.Replace_Element (1, P);
         Assert
           (not Is_Reversal_Of (Bad_Rev, Orig_Tx),
            "Reject a balanced transaction that does not invert target postings");
      end;

      Assert (Add_Transaction (L, Rev_Tx, Status), "Add reversal transaction to ledger");

      declare
         Asset_Bal : constant Balance := Compute_Account_Balance (L, Acc_Asset);
         Exp_Bal   : constant Balance := Compute_Account_Balance (L, Acc_Expense);
         Tot_Bal   : constant Balance := Compute_Total_Balance (L);
      begin
         Assert (Is_Zero_Balance (Asset_Bal), "Asset balance returned to ZERO after reversal");
         Assert (Is_Zero_Balance (Exp_Bal), "Expense balance returned to ZERO after reversal");
         Assert (Is_Zero_Balance (Tot_Bal), "Total ledger balance remains strictly ZERO");
      end;

      --  Test Journal metadata extraction for event-id and reverses
      declare
         Rev_Journal_Text : constant String :=
           "2026-08-12 Store Refund [event-id: evt-2026-003] [reverses: evt-2026-001]" & ASCII.LF &
           "    assets:cash          5000 JPY" & ASCII.LF &
           "    expenses:gadgets    -5000 JPY" & ASCII.LF;
         L_Parsed : Ledger;
         Err : Unbounded_String;
      begin
         Assert (Parse_Journal_Text (Rev_Journal_Text, L_Parsed, Err), "Parse journal with event-id and reverses metadata");
         Assert (Natural (L_Parsed.Transactions.Length) = 1, "Parsed 1 reversal journal transaction");
         declare
            T : constant Transaction := L_Parsed.Transactions.Element (1);
         begin
            Assert (To_String (T.Event_ID) = "evt-2026-003", "Extracted Event_ID = evt-2026-003");
            Assert (To_String (T.Reverses_ID) = "evt-2026-001", "Extracted Reverses_ID = evt-2026-001");
         end;
      end;
   end Test_Reversal_Law;

   procedure Test_Envelope_Entitlement is
      use ALedger.Envelope_Entitlement;
      Food_UTF8 : constant String :=
        Character'Val (16#E9#) & Character'Val (16#A3#) & Character'Val (16#9F#) &
        Character'Val (16#E8#) & Character'Val (16#B2#) & Character'Val (16#BB#);
      Gen_UTF8 : constant String :=
        Character'Val (16#E4#) & Character'Val (16#B8#) & Character'Val (16#80#) &
        Character'Val (16#E8#) & Character'Val (16#88#) & Character'Val (16#AC#) &
        Character'Val (16#E7#) & Character'Val (16#94#) & Character'Val (16#9F#) &
        Character'Val (16#E6#) & Character'Val (16#B4#) & Character'Val (16#BB#);
      JPY     : constant Commodity := Make_Commodity ("JPY");
      USD     : constant Commodity := Make_Commodity ("USD");
      Food_Id : constant ALedger.Envelope.Envelope_Id :=
        ALedger.Envelope.Make_Envelope_Id (Food_UTF8);
      Gen_Id  : constant ALedger.Envelope.Envelope_Id :=
        ALedger.Envelope.Make_Envelope_Id (Gen_UTF8);
      Obs     : Entitlement_Observation := Empty_Observation;
   begin
      Put_Line ("--- Testing ALedger.Envelope_Entitlement ---");

      Assert
        (Is_Zero_Balance (Unallocated_Balance (Obs)),
         "Empty observation has zero unallocated");
      Assert
        (Is_Zero_Balance (Entitlement_For (Obs, Food_Id)),
         "Empty observation returns zero for Food");

      Obs := Fold_Movement
        (Obs,
         (Kind    => Grant_From_Unallocated,
          Tx_Date => D ("2026-06-07"),
          Amt     => Make_Amount (JPY, 1000.0),
          Target  => Food_Id));
      Assert
        (Lookup_Balance (Entitlement_For (Obs, Food_Id), JPY) = 1000.0,
         "After grant 1000 JPY: Food = 1000");
      Assert
        (Lookup_Balance (Unallocated_Balance (Obs), JPY) = -1000.0,
         "After grant: unallocated = -1000 (deficit)");

      Obs := Fold_Movement
        (Obs,
         (Kind    => Grant_From_Unallocated,
          Tx_Date => D ("2026-06-07"),
          Amt     => Make_Amount (USD, 500.0),
          Target  => Food_Id));
      Assert
        (Lookup_Balance (Entitlement_For (Obs, Food_Id), JPY) = 1000.0
           and then Lookup_Balance (Entitlement_For (Obs, Food_Id), USD) = 500.0,
         "Food has both JPY 1000 and USD 500");

      Obs := Fold_Movement
        (Obs,
         (Kind          => Transfer_Between_Envelopes,
          Tx_Date       => D ("2026-06-08"),
          Amt           => Make_Amount (JPY, 300.0),
          From_Envelope => Food_Id,
          To_Envelope   => Gen_Id));
      Assert
        (Lookup_Balance (Entitlement_For (Obs, Food_Id), JPY) = 700.0,
         "After transfer 300 JPY: Food = 700");
      Assert
        (Lookup_Balance (Entitlement_For (Obs, Gen_Id), JPY) = 300.0,
         "After transfer: Gen = 300");

      Obs := Fold_Movement
        (Obs,
         (Kind    => Return_To_Unallocated,
          Tx_Date => D ("2026-06-09"),
          Amt     => Make_Amount (JPY, 100.0),
          Source  => Food_Id));
      Assert
        (Lookup_Balance (Entitlement_For (Obs, Food_Id), JPY) = 600.0,
         "After return 100 JPY: Food = 600");
      Assert
        (Lookup_Balance (Unallocated_Balance (Obs), JPY) = -900.0,
         "After return: unallocated = -900 (deficit)");
   end Test_Envelope_Entitlement;

   procedure Test_Budget_Source_Adapter is
      use ALedger.Budget_Source_Adapter;
      use ALedger.Envelope;
      use ALedger.Envelope_Entitlement;
      use ALedger.Config_Support;

      Food_UTF8 : constant String :=
        Character'Val (16#E9#) & Character'Val (16#A3#) & Character'Val (16#9F#) &
        Character'Val (16#E8#) & Character'Val (16#B2#) & Character'Val (16#BB#);
      Daily_UTF8 : constant String :=
        Character'Val (16#E6#) & Character'Val (16#97#) & Character'Val (16#A5#) &
        Character'Val (16#E7#) & Character'Val (16#94#) & Character'Val (16#A8#) &
        Character'Val (16#E5#) & Character'Val (16#93#) & Character'Val (16#81#);

      JPY : constant Commodity := Make_Commodity ("JPY");

      Budget_TOML : constant String :=
        "[[backing-pools]]" & ASCII.LF &
        "id = ""liquid""" & ASCII.LF &
        "asset-accounts = [""assets:cash""]" & ASCII.LF &
        "[[envelopes]]" & ASCII.LF &
        "id = """ & Food_UTF8 & """" & ASCII.LF &
        "label = """ & Food_UTF8 & """" & ASCII.LF &
        "pacing = ""daily""" & ASCII.LF &
        "backing-pool = ""liquid""" & ASCII.LF &
        "expense-accounts = [""expenses:food""]" & ASCII.LF &
        "[[envelopes]]" & ASCII.LF &
        "id = """ & Daily_UTF8 & """" & ASCII.LF &
        "label = """ & Daily_UTF8 & """" & ASCII.LF &
        "pacing = ""daily""" & ASCII.LF &
        "backing-pool = ""liquid""" & ASCII.LF &
        "expense-accounts = [""expenses:daily""]" & ASCII.LF;

      Household_TOML : constant String :=
        "[cycle]" & ASCII.LF &
        "mode = ""income-anchor""" & ASCII.LF &
        "income-account = ""income:salary""" & ASCII.LF &
        "[budget]" & ASCII.LF &
        "unassigned-accounts = [""budget:unassigned""]" & ASCII.LF &
        "[[budget.envelopes]]" & ASCII.LF &
        "id = """ & Food_UTF8 & """" & ASCII.LF &
        "allocation-account = ""budget:" & Food_UTF8 & """" & ASCII.LF &
        "[[budget.envelopes]]" & ASCII.LF &
        "id = """ & Daily_UTF8 & """" & ASCII.LF &
        "allocation-account = ""budget:" & Daily_UTF8 & """" & ASCII.LF &
        "[envelope-history]" & ASCII.LF &
        "identities = [""" & Food_UTF8 & """, """ & Daily_UTF8 & """]" & ASCII.LF;

      Budget_Journal_Text : constant String :=
        "2026-08-01 Grant Initial Food" & ASCII.LF &
        "    budget:unassigned      -10000 JPY" & ASCII.LF &
        "    budget:" & Food_UTF8 & "   10000 JPY" & ASCII.LF &
        "" & ASCII.LF &
        "2026-08-02 Transfer Food to Daily" & ASCII.LF &
        "    budget:" & Food_UTF8 & "    -2000 JPY" & ASCII.LF &
        "    budget:" & Daily_UTF8 & "    2000 JPY" & ASCII.LF &
        "" & ASCII.LF &
        "2026-08-03 Return from Food" & ASCII.LF &
        "    budget:" & Food_UTF8 & "    -1000 JPY" & ASCII.LF &
        "    budget:unassigned        1000 JPY" & ASCII.LF &
        "" & ASCII.LF &
        "2026-08-04 Execution Movement (Spent)" & ASCII.LF &
        "    budget:" & Food_UTF8 & "    -5000 JPY" & ASCII.LF &
        "    budget:spent             5000 JPY" & ASCII.LF &
        "" & ASCII.LF &
        "2026-08-05 Negative Amount Return Daily" & ASCII.LF &
        "    budget:" & Daily_UTF8 & "  -1000 JPY" & ASCII.LF &
        "    budget:unassigned       1000 JPY" & ASCII.LF;

      B_Policy : ALedger.Budget_Config.Budget_Policy;
      H_Cfg    : ALedger.Household_Config.Household_Configuration;
      B_Diag   : ALedger.Config_Support.Config_Diagnostic;
      H_Diag   : ALedger.Config_Support.Config_Diagnostic;
      L        : Ledger;
      Err      : Unbounded_String;
      Reg      : Envelope_Registry;
      Reg_Diag : Config_Diagnostic;
      Ids      : String_Vectors.Vector;
      Movements: Movement_Vectors.Vector;
      Ad_Diag  : Adapter_Diagnostic;
      Obs      : Entitlement_Observation;
      Food_Id  : Envelope_Id;
      Daily_Id : Envelope_Id;
   begin
      Put_Line ("--- Testing ALedger.Budget_Source_Adapter ---");

      Assert
        (ALedger.Budget_Config.Parse_Budget_Policy (Budget_TOML, B_Policy, B_Diag),
         "Setup: Parse Budget Policy");
      Assert
        (ALedger.Household_Config.Parse_Household_Configuration (Household_TOML, B_Policy, H_Cfg, H_Diag),
         "Setup: Parse Household Configuration");

      Ids.Append (Food_UTF8);
      Ids.Append (Daily_UTF8);
      Assert
        (Admit_Registry (Ids, Reg, Reg_Diag),
         "Setup: Admit Envelope Registry");

      Assert
        (Lookup (Reg, Food_UTF8, Food_Id), "Lookup Food_Id");
      Assert
        (Lookup (Reg, Daily_UTF8, Daily_Id), "Lookup Daily_Id");

      Assert
        (Parse_Journal_Text (Budget_Journal_Text, L, Err),
         "Setup: Parse budget.journal text");
      Assert
        (Natural (L.Transactions.Length) = 5,
         "Parsed 5 budget transactions");

      Assert
        (Adapt_Budget_Journal (L.Transactions, H_Cfg, Reg, Movements, Ad_Diag),
         "Adapt budget.journal transactions to Entitlement_Movements");

      -- 4 movements adapted (1 spent execution ignored)
      Assert
        (Natural (Movements.Length) = 4,
         "Adapted 4 Entitlement_Movements (spent ignored)");

      -- Verify full fold via Observe_Entitlements
      Assert
        (Observe_Entitlements (L.Transactions, H_Cfg, Reg, Obs, Ad_Diag),
         "Observe_Entitlements successfully folds all movements");

      -- Food balance: 10000 - 2000 - 1000 = 7000 JPY
      Assert
        (Lookup_Balance (Entitlement_For (Obs, Food_Id), JPY) = 7000.0,
         "Food entitlement is 7,000 JPY");

      -- Daily balance: 2000 - 1000 (returned) = 1000 JPY
      Assert
        (Lookup_Balance (Entitlement_For (Obs, Daily_Id), JPY) = 1000.0,
         "Daily entitlement is 1,000 JPY");

      -- Unallocated deficit: -10000 + 1000 + 1000 = -8000 JPY
      Assert
        (Lookup_Balance (Unallocated_Balance (Obs), JPY) = -8000.0,
         "Unallocated entitlement is -8,000 JPY");

      -- Test rejection of unknown budget account
      declare
         Bad_Journal_Text : constant String :=
           "2026-08-01 Unknown Account" & ASCII.LF &
           "    budget:nonexistent    -1000 JPY" & ASCII.LF &
           "    budget:unassigned      1000 JPY" & ASCII.LF;
         Bad_L : Ledger;
         Bad_Movs : Movement_Vectors.Vector;
      begin
         Assert
           (Parse_Journal_Text (Bad_Journal_Text, Bad_L, Err),
            "Parse bad budget journal text");
         Assert
           (not Adapt_Budget_Journal (Bad_L.Transactions, H_Cfg, Reg, Bad_Movs, Ad_Diag),
            "Reject unknown budget account");
         Assert
           (Ad_Diag.Status = Unrecognized_Budget_Account,
            "Diagnostic status is Unrecognized_Budget_Account");
      end;
   end Test_Budget_Source_Adapter;

   procedure Test_Envelope_Consumption is
      use ALedger.Envelope_Consumption;
      use ALedger.Envelope;
      use ALedger.Envelope_Routing;
      use ALedger.Config_Support;

      Food_UTF8 : constant String :=
        Character'Val (16#E9#) & Character'Val (16#A3#) & Character'Val (16#9F#) &
        Character'Val (16#E8#) & Character'Val (16#B2#) & Character'Val (16#BB#);
      Tabaco_UTF8 : constant String :=
        Character'Val (16#E3#) & Character'Val (16#82#) & Character'Val (16#BF#) &
        Character'Val (16#E3#) & Character'Val (16#81#) & Character'Val (16#B0#) &
        Character'Val (16#E3#) & Character'Val (16#82#) & Character'Val (16#B3#);

      JPY : constant Commodity := Make_Commodity ("JPY");

      Reg       : Envelope_Registry;
      Reg_Diag  : Config_Diagnostic;
      Ids       : String_Vectors.Vector;
      Food_Id   : Envelope_Id;
      Tabaco_Id : Envelope_Id;

      R_Entries : Routing_Entry_Vectors.Vector;
      History   : Routing_History;
      H_Status  : History_Status;

      Actual_Journal_Text : constant String :=
        "account assets:cash" & ASCII.LF &
        "    type: asset" & ASCII.LF &
        "account expenses:food" & ASCII.LF &
        "    type: expense" & ASCII.LF &
        "account expenses:rent" & ASCII.LF &
        "    type: expense" & ASCII.LF &
        "account expenses:other" & ASCII.LF &
        "    type: expense" & ASCII.LF &
        "" & ASCII.LF &
        "2026-08-10 Grocery Store [event-id: evt-001]" & ASCII.LF &
        "    assets:cash        -3000 JPY" & ASCII.LF &
        "    expenses:food       3000 JPY" & ASCII.LF &
        "" & ASCII.LF &
        "2026-08-12 Partial Refund [event-id: evt-002] [reverses: evt-001]" & ASCII.LF &
        "    assets:cash          500 JPY" & ASCII.LF &
        "    expenses:food       -500 JPY" & ASCII.LF &
        "" & ASCII.LF &
        "2026-08-20 Convenience Store [event-id: evt-003]" & ASCII.LF &
        "    assets:cash        -2000 JPY" & ASCII.LF &
        "    expenses:food       2000 JPY" & ASCII.LF &
        "" & ASCII.LF &
        "2026-08-22 House Rent" & ASCII.LF &
        "    assets:cash       -80000 JPY" & ASCII.LF &
        "    expenses:rent      80000 JPY" & ASCII.LF &
        "" & ASCII.LF &
        "2026-08-25 Unrouted Expense" & ASCII.LF &
        "    assets:cash        -1500 JPY" & ASCII.LF &
        "    expenses:other      1500 JPY" & ASCII.LF;

      L   : Ledger;
      Err : Unbounded_String;
      Obs : Envelope_Consumption;
   begin
      Put_Line ("--- Testing ALedger.Envelope_Consumption ---");

      -- Setup Envelopes: Food and Tabaco
      Ids.Append (Food_UTF8);
      Ids.Append (Tabaco_UTF8);
      Assert (Admit_Registry (Ids, Reg, Reg_Diag), "Setup: Admit Registry for Consumption");
      Assert (Lookup (Reg, Food_UTF8, Food_Id), "Lookup Food_Id");
      Assert (Lookup (Reg, Tabaco_UTF8, Tabaco_Id), "Lookup Tabaco_Id");

      -- Setup Routing:
      -- expenses:food -> initial = Food, from 2026-08-15 = Tabaco
      -- expenses:rent -> Not_Envelope_Managed
      -- expenses:other -> (no routing)
      R_Entries.Append
        (Routing_Entry'
           (Effective => Initial_Effective_Date,
            Expense   => Make_Account ("expenses:food"),
            Route     => Managed_Route (Food_Id),
            Note      => To_Unbounded_String ("initial food")));
      R_Entries.Append
        (Routing_Entry'
           (Effective => Dated_Effective (D ("2026-08-15")),
            Expense   => Make_Account ("expenses:food"),
            Route     => Managed_Route (Tabaco_Id),
            Note      => To_Unbounded_String ("switched to tabaco")));
      R_Entries.Append
        (Routing_Entry'
           (Effective => Initial_Effective_Date,
            Expense   => Make_Account ("expenses:rent"),
            Route     => Not_Managed_Route,
            Note      => To_Unbounded_String ("rent unmanaged")));
      Assert
        (Admit (R_Entries, Reg, History, H_Status) and then H_Status = Success,
         "Setup: Admit Routing History for Consumption");

      Assert
        (Parse_Journal_Text (Actual_Journal_Text, L, Err),
         "Setup: Parse actual transactions for consumption");
      Assert
        (Natural (L.Transactions.Length) = 5,
         "Parsed 5 actual transactions");

      -- Observe Consumption across all transactions
      Obs := Observe_Consumption (L, History);

      -- Food consumption (2026-08-10 charge 3000, 2026-08-12 refund 500)
      declare
         Food_Amounts : constant Consumption_Amounts :=
           Consumption_For (Obs, Food_Id);
         Food_Net     : constant Balance :=
           Net_For (Obs, Food_Id);
      begin
         Assert
           (Lookup_Balance (Food_Amounts.Charges, JPY) = 3000.0,
            "Food Charges = 3,000 JPY");
         Assert
           (Lookup_Balance (Food_Amounts.Refunds, JPY) = 500.0,
            "Food Refunds = 500 JPY");
         Assert
           (Lookup_Balance (Food_Net, JPY) = 2500.0,
            "Food Net Consumption = 2,500 JPY");
      end;

      -- Tabaco consumption (2026-08-20 charge 2000 under dated routing)
      declare
         Tabaco_Amounts : constant Consumption_Amounts :=
           Consumption_For (Obs, Tabaco_Id);
      begin
         Assert
           (Lookup_Balance (Tabaco_Amounts.Charges, JPY) = 2000.0,
            "Tabaco Charges = 2,000 JPY");
         Assert
           (Is_Zero_Balance (Tabaco_Amounts.Refunds),
            "Tabaco Refunds = 0 JPY");
      end;

      -- Unmanaged check (rent = 80000 JPY)
      Assert
        (Obs.Unmanaged.Contains ("expenses:rent"),
         "Unmanaged contains expenses:rent");
      Assert
        (Lookup_Balance (Obs.Unmanaged.Element ("expenses:rent").Charges, JPY) = 80000.0,
         "Unmanaged rent charges = 80,000 JPY");

      -- Unrouted check (other = 1500 JPY attention evidence)
      Assert (Has_Unrouted (Obs), "Has_Unrouted is True");
      Assert
        (Obs.Unrouted.Contains ("expenses:other"),
         "Unrouted contains expenses:other");
      Assert
        (Lookup_Balance (Obs.Unrouted.Element ("expenses:other").Charges, JPY) = 1500.0,
         "Unrouted other charges = 1,500 JPY");

      -- Date filter test (Through 2026-08-15)
      declare
         Through_Obs : constant Envelope_Consumption :=
           Observe_Consumption (L, History, D ("2026-08-15"));
      begin
         Assert
           (Lookup_Balance (Consumption_For (Through_Obs, Food_Id).Charges, JPY) = 3000.0,
            "Through 2026-08-15: Food Charges = 3,000 JPY");
         Assert
           (Is_Zero_Balance (Consumption_For (Through_Obs, Tabaco_Id).Charges),
            "Through 2026-08-15: Tabaco Charges = 0 JPY (post-date excluded)");
      end;
   end Test_Envelope_Consumption;

   procedure Test_Backing_Policy is
      use ALedger.Backing_Policy;
      use ALedger.Envelope;
      use ALedger.Envelope_Entitlement;
      use ALedger.Envelope_Consumption;
      use ALedger.Config_Support;

      Food_UTF8 : constant String :=
        Character'Val (16#E9#) & Character'Val (16#A3#) & Character'Val (16#9F#) &
        Character'Val (16#E8#) & Character'Val (16#B2#) & Character'Val (16#BB#);
      Daily_UTF8 : constant String :=
        Character'Val (16#E6#) & Character'Val (16#97#) & Character'Val (16#A5#) &
        Character'Val (16#E7#) & Character'Val (16#94#) & Character'Val (16#A8#) &
        Character'Val (16#E5#) & Character'Val (16#93#) & Character'Val (16#81#);

      JPY : constant Commodity := Make_Commodity ("JPY");
      USD : constant Commodity := Make_Commodity ("USD");
   begin
      -- 1. Test Positive_Balance law
      declare
         Pos_Bal : constant Balance := Singleton_Balance (Make_Amount (JPY, 1000.0));
         Neg_Bal : constant Balance := Singleton_Balance (Make_Amount (JPY, -500.0));
         Mix_Bal : Balance := Pos_Bal;
      begin
         Mix_Bal := Add_Balance (Mix_Bal, Singleton_Balance (Make_Amount (USD, -500.0)));
         Assert
           (Lookup_Balance (Positive_Balance (Pos_Bal), JPY) = 1000.0,
            "Positive_Balance keeps positive 1,000 JPY");
         Assert
           (Is_Zero_Balance (Positive_Balance (Neg_Bal)),
            "Positive_Balance drops negative -500 JPY to zero");
         Assert
           (Lookup_Balance (Positive_Balance (Mix_Bal), JPY) = 1000.0
              and then Is_Zero (Lookup_Balance (Positive_Balance (Mix_Bal), USD)),
            "Positive_Balance keeps positive JPY and drops negative USD in mixed balance");
      end;

      -- 2. Test Policy Admission & Observation
      declare
         Budget_TOML : constant String :=
           "[[backing-pools]]" & ASCII.LF &
           "id = ""liquid""" & ASCII.LF &
           "asset-accounts = [""assets:cash""]" & ASCII.LF &
           "[[envelopes]]" & ASCII.LF &
           "id = """ & Food_UTF8 & """" & ASCII.LF &
           "label = """ & Food_UTF8 & """" & ASCII.LF &
           "pacing = ""daily""" & ASCII.LF &
           "backing-pool = ""liquid""" & ASCII.LF &
           "expense-accounts = [""expenses:food""]" & ASCII.LF &
           "[[envelopes]]" & ASCII.LF &
           "id = """ & Daily_UTF8 & """" & ASCII.LF &
           "label = """ & Daily_UTF8 & """" & ASCII.LF &
           "pacing = ""daily""" & ASCII.LF &
           "backing-pool = ""liquid""" & ASCII.LF &
           "expense-accounts = [""expenses:daily""]" & ASCII.LF;

         B_Policy : ALedger.Budget_Config.Budget_Policy;
         B_Diag   : ALedger.Config_Support.Config_Diagnostic;
         Reg      : Envelope_Registry;
         Reg_Diag : Config_Diagnostic;
         Ids      : String_Vectors.Vector;
         Policy   : ALedger.Backing_Policy.Backing_Policy;
         P_Status : Policy_Status;

         Food_Id  : Envelope_Id;
         Daily_Id : Envelope_Id;

         -- Synthetic Ledger with 50,000 JPY in assets:cash
         L        : Ledger;
         Err      : Unbounded_String;
         L_Text   : constant String :=
           "2026-08-01 Opening Cash" & ASCII.LF &
           "    equity:opening        -50000 JPY" & ASCII.LF &
           "    assets:cash            50000 JPY" & ASCII.LF;

         Ent_Obs  : Entitlement_Observation := Empty_Observation;
         Cons_Obs : Envelope_Consumption := Empty_Consumption;
         Back_Obs : Backing_Observation;
      begin
         Put_Line ("--- Testing ALedger.Backing_Policy ---");

         Assert
           (ALedger.Budget_Config.Parse_Budget_Policy (Budget_TOML, B_Policy, B_Diag),
            "Setup: Parse Budget Policy for Backing");

         Ids.Append (New_Item => Food_UTF8);
         Ids.Append (New_Item => Daily_UTF8);
         Assert
           (Admit_Registry (Ids, Reg, Reg_Diag),
            "Setup: Admit Registry for Backing");
         Assert (Lookup (Reg, Food_UTF8, Food_Id), "Lookup Food_Id");
         Assert (Lookup (Reg, Daily_UTF8, Daily_Id), "Lookup Daily_Id");

         Assert
           (Admit_Backing_Policy (B_Policy, Reg, Policy, P_Status)
              and then P_Status = Success,
            "Admit Backing Policy");

         Assert
           (Parse_Journal_Text (L_Text, L, Err),
            "Setup: Parse cash ledger");

         -- Food: Entitlement 10,000 JPY, Consumption 3,000 JPY -> Remaining = 7,000 JPY
         Ent_Obs := Fold_Movement
           (Ent_Obs,
            (Kind    => Grant_From_Unallocated,
             Tx_Date => D ("2026-08-01"),
             Amt     => Make_Amount (JPY, 10000.0),
             Target  => Food_Id));
         Cons_Obs.Managed :=
           ALedger.Envelope_Consumption.Envelope_Amounts_Maps.Empty_Map;
         Cons_Obs.Managed.Insert
           (Food_UTF8,
            Make_Amounts
              (Charges => Singleton_Balance (Make_Amount (JPY, 3000.0)),
               Refunds => Empty_Balance));

         -- Daily: Entitlement 5,000 JPY, Consumption 6,000 JPY -> Remaining = -1,000 JPY (deficit)
         Ent_Obs := Fold_Movement
           (Ent_Obs,
            (Kind    => Grant_From_Unallocated,
             Tx_Date => D ("2026-08-01"),
             Amt     => Make_Amount (JPY, 5000.0),
             Target  => Daily_Id));
         Cons_Obs.Managed.Insert
           (Daily_UTF8,
            Make_Amounts
              (Charges => Singleton_Balance (Make_Amount (JPY, 6000.0)),
               Refunds => Empty_Balance));

         -- Observe Backing
         Back_Obs := Observe_Backing (Policy, L, Ent_Obs, Cons_Obs);

         declare
            Liquid_Pos : constant Backing_Pool_Position :=
              Position_For (Back_Obs, "liquid");
         begin
            Assert
              (Lookup_Balance (Liquid_Pos.Funding_Balance, JPY) = 50000.0,
               "Liquid Funding Balance = 50,000 JPY");
            -- Gross required = Positive(7,000) + Positive(-1,000) = 7,000 JPY (deficit does not offset!)
            Assert
              (Lookup_Balance (Liquid_Pos.Gross_Envelope_Required, JPY) = 7000.0,
               "Liquid Gross Required = 7,000 JPY (overspending does not cancel claim)");
            -- Gross surplus = 50,000 - 7,000 = 43,000 JPY
            Assert
              (Lookup_Balance (Gross_Surplus (Liquid_Pos), JPY) = 43000.0,
               "Liquid Gross Surplus = 43,000 JPY");
            Assert
              (Lookup_Balance (Available_Surplus (Liquid_Pos), JPY) = 43000.0,
               "Liquid Available Surplus = 43,000 JPY");
         end;
      end;
   end Test_Backing_Policy;

begin
   Put_Line ("==================================================");
   Put_Line ("   ALedger Test Suite (v" & ALedger.Version & ")");
   Put_Line ("==================================================");

   Test_Proof_Core;
   Test_Money;
   Test_Account;
   Test_Ledger;
   Test_Journal;
   Test_TOML_Config_Admission;
   Test_Report_And_Budget;
   Test_Canonical_Household;
   Test_Plan_Lifecycle;
   Test_Safe_Writer;
   Test_Golden_Report_Verification;
   Test_Reversal_Law;
   Test_Envelope_Identity_And_Registry;
   Test_Envelope_Routing;
   Test_Envelope_Entitlement;
   Test_Budget_Source_Adapter;
   Test_Envelope_Consumption;
   Test_Backing_Policy;

   Put_Line ("--------------------------------------------------");
   Put_Line ("Summary: Passed =" & Natural'Image (Passed_Count) &
             ", Failed =" & Natural'Image (Failed_Count));
   if Failed_Count > 0 then
      Put_Line ("RESULT: FAIL");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   else
      Put_Line ("RESULT: SUCCESS");
   end if;
end Test_Runner;
