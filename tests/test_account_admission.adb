with Ada.Directories;       use Ada.Directories;
with Ada.Strings.Fixed;      use Ada.Strings.Fixed;
with Ada.Strings.Unbounded;  use Ada.Strings.Unbounded;
with Ada.Text_IO;            use Ada.Text_IO;
with HRA.Account;        use HRA.Account;
with HRA.Household;      use HRA.Household;
with HRA.Journal;        use HRA.Journal;
with HRA.Journal_Loader;
with HRA.Ledger;         use HRA.Ledger;

procedure Test_Account_Admission is
   Passed_Count : Natural := 0;
   Failed_Count : Natural := 0;
   Quote        : constant Character := Character'Val (34);

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

   procedure Write_File (Path : String; Text : String) is
      F : File_Type;
   begin
      Create (F, Out_File, Path);
      Put (F, Text);
      Close (F);
   end Write_File;

begin
   Put_Line ("--- Testing HRA Account admission laws ---");

   declare
      Reg        : Account_Registry := Empty_Registry;
      Status     : Registry_Status;
      Decl       : Account_Declaration;
      Zeta       : constant Account := Make_Account ("expenses:zeta");
      Alpha      : constant Account := Make_Account ("assets:alpha");
      Middle     : constant Account := Make_Account ("income:middle");
      Undeclared : constant Account := Make_Account ("income:undeclared");
   begin
      Assert
        (Register_Account (Reg, Declare_Account (Zeta, Expense), Status),
         "register first declaration");
      Assert
        (Register_Account (Reg, Declare_Account (Alpha, Asset), Status),
         "register second declaration");
      Assert
        (Register_Account (Reg, Declare_Account (Middle, Income), Status),
         "register third declaration");

      declare
         Items : constant Declaration_Array := Declarations (Reg);
      begin
         Assert
           (Items'Length = 3
              and then Name (Items (1).Acc) = "expenses:zeta"
              and then Name (Items (2).Acc) = "assets:alpha"
              and then Name (Items (3).Acc) = "income:middle",
            "Declarations preserves admission order rather than key order");
      end;

      Assert
        (Lookup_Declaration (Reg, Alpha, Decl)
           and then Decl.Acc_Type = Asset,
         "name lookup resolves the declaration through the private index");
      Assert
        (not Lookup_Declaration (Reg, Undeclared, Decl),
         "undeclared prefixed Account does not infer a declaration");
      Assert
        (not Register_Account
           (Reg, Declare_Account (Alpha, Asset), Status)
           and then Status = Duplicate_Account_Declaration,
         "duplicate registry declaration fails closed");
   end;

   declare
      Text : constant String :=
        "account expenses:zeta" & ASCII.LF &
        "  ; type: Expense" & ASCII.LF &
        "account assets:alpha" & ASCII.LF &
        "  ; type: Asset" & ASCII.LF &
        "account income:middle" & ASCII.LF &
        "  ; type: Income" & ASCII.LF;
      L   : Ledger;
      Err : Unbounded_String;
   begin
      Assert
        (Parse_Journal_Text (Text, L, Err),
         "Journal admits explicit Account declarations");
      if Declarations (L.Registry)'Length = 3 then
         declare
            Items : constant Declaration_Array := Declarations (L.Registry);
         begin
            Assert
              (Name (Items (1).Acc) = "expenses:zeta"
                 and then Name (Items (2).Acc) = "assets:alpha"
                 and then Name (Items (3).Acc) = "income:middle",
               "Journal admission preserves physical declaration order");
         end;
      else
         Assert (False, "Journal admission preserves physical declaration order");
      end if;
   end;

   declare
      Missing_Type : constant String :=
        "account income:implicit" & ASCII.LF;
      L   : Ledger;
      Err : Unbounded_String;
   begin
      Assert
        (not Parse_Journal_Text (Missing_Type, L, Err)
           and then Index (To_String (Err), "requires explicit type or role") > 0,
         "AccountType is not inferred from the Account name");
   end;

   declare
      Duplicate : constant String :=
        "account assets:cash" & ASCII.LF &
        "  ; type: Asset" & ASCII.LF &
        "account assets:cash" & ASCII.LF &
        "  ; type: Asset" & ASCII.LF;
      L   : Ledger;
      Err : Unbounded_String;
   begin
      Assert
        (not Parse_Journal_Text (Duplicate, L, Err)
           and then Index (To_String (Err), "Duplicate account declaration") > 0,
         "duplicate Journal declaration fails admission");
   end;

   declare
      Tmp_Dir    : constant String := "/tmp/hra_account_admission";
      Root_Path  : constant String := Tmp_Dir & "/accounts.journal";
      Child_Path : constant String := Tmp_Dir & "/child.journal";
      Root_Text  : constant String :=
        "account expenses:root-first" & ASCII.LF &
        "  ; type: Expense" & ASCII.LF &
        "include child.journal" & ASCII.LF &
        "account assets:root-last" & ASCII.LF &
        "  ; type: Asset" & ASCII.LF;
      Child_Text : constant String :=
        "account income:included" & ASCII.LF &
        "  ; type: Income" & ASCII.LF;
      Obs : HRA.Journal_Loader.Journal_Observation;
      Err : Unbounded_String;
   begin
      if Exists (Tmp_Dir) then
         Delete_Tree (Tmp_Dir);
      end if;
      Create_Path (Tmp_Dir);
      Write_File (Root_Path, Root_Text);
      Write_File (Child_Path, Child_Text);

      Assert
        (HRA.Journal_Loader.Load_From_Root_Source
           (Root_Path, Root_Text, Obs, Err),
         "include graph admits Account declarations");

      declare
         Items : constant Declaration_Array := Declarations (Obs.Value.Registry);
      begin
         Assert
           (Items'Length = 3
              and then Name (Items (1).Acc) = "expenses:root-first"
              and then Name (Items (2).Acc) = "income:included"
              and then Name (Items (3).Acc) = "assets:root-last",
            "include expansion preserves source-admitted Account order");
      end;

      Delete_Tree (Tmp_Dir);
   end;

   --  A declaration in Actual is parser-local evidence only. It cannot expand
   --  the canonical Account universe owned by accounts.journal.
   declare
      Tmp_Dir : constant String := "/tmp/hra_account_authority";
      Paths   : constant Source_Paths := Resolve_Source_Paths (Tmp_Dir);
      State   : Household_State;
      Err     : Unbounded_String;
   begin
      if Exists (Tmp_Dir) then
         Delete_Tree (Tmp_Dir);
      end if;
      Create_Path (Tmp_Dir);

      Write_File
        (To_String (Paths.Accounts_Journal),
         "account assets:wallet" & ASCII.LF &
         "  ; type: Asset" & ASCII.LF &
         "account expenses:coffee" & ASCII.LF &
         "  ; type: Expense" & ASCII.LF &
         "account income:salary" & ASCII.LF &
         "  ; type: Income" & ASCII.LF &
         "account budget:coffee" & ASCII.LF &
         "  ; type: Budget" & ASCII.LF &
         "account budget:unassigned" & ASCII.LF &
         "  ; type: Budget" & ASCII.LF &
         "account budget:opening" & ASCII.LF &
         "  ; type: Budget" & ASCII.LF);

      Write_File
        (To_String (Paths.Actual_Journal),
         "account expenses:actual-only" & ASCII.LF &
         "  ; type: Expense" & ASCII.LF &
         "2026-08-13 Actual-only Account" & ASCII.LF &
         "    expenses:actual-only       500 JPY" & ASCII.LF &
         "    assets:wallet             -500 JPY" & ASCII.LF);

      Write_File (To_String (Paths.Plan_Journal), "");
      Write_File (To_String (Paths.Budget_Journal), "");

      Write_File
        (To_String (Paths.Budget_TOML),
         "[[backing-pools]]" & ASCII.LF &
         "id = " & Quote & "liquid" & Quote & ASCII.LF &
         "asset-accounts = [" & Quote & "assets:wallet" & Quote & "]" & ASCII.LF &
         "[[envelopes]]" & ASCII.LF &
         "id = " & Quote & "coffee" & Quote & ASCII.LF &
         "label = " & Quote & "Coffee" & Quote & ASCII.LF &
         "pacing = " & Quote & "daily" & Quote & ASCII.LF &
         "backing-pool = " & Quote & "liquid" & Quote & ASCII.LF);

      Write_File
        (To_String (Paths.Household_TOML),
         "[cycle]" & ASCII.LF &
         "mode = " & Quote & "income-anchor" & Quote & ASCII.LF &
         "income-account = " & Quote & "income:salary" & Quote & ASCII.LF &
         "[money]" & ASCII.LF &
         "primary-commodity = " & Quote & "JPY" & Quote & ASCII.LF &
         "[budget]" & ASCII.LF &
         "opening-accounts = [" & Quote & "budget:opening" & Quote & "]" & ASCII.LF &
         "unassigned-accounts = [" & Quote & "budget:unassigned" & Quote & "]" & ASCII.LF &
         "[[budget.envelopes]]" & ASCII.LF &
         "id = " & Quote & "coffee" & Quote & ASCII.LF &
         "allocation-account = " & Quote & "budget:coffee" & Quote & ASCII.LF &
         "[envelope-history]" & ASCII.LF &
         "identities = [" & Quote & "coffee" & Quote & "]" & ASCII.LF &
         "expense-routing = []" & ASCII.LF);

      Write_File
        (To_String (Paths.Report_TOML),
         "[reports.trial-balance]" & ASCII.LF &
         "as-of = " & Quote & "latest" & Quote & ASCII.LF &
         "[reports.balance-sheet]" & ASCII.LF &
         "as-of = " & Quote & "latest" & Quote & ASCII.LF &
         "[reports.profit-and-loss]" & ASCII.LF &
         "from = " & Quote & "beginning" & Quote & ASCII.LF &
         "through = " & Quote & "latest" & Quote & ASCII.LF &
         "[reports.daily-flow]" & ASCII.LF &
         "from = " & Quote & "beginning" & Quote & ASCII.LF &
         "through = " & Quote & "latest" & Quote & ASCII.LF &
         "[reports.monthly-accounts]" & ASCII.LF &
         "from = " & Quote & "beginning" & Quote & ASCII.LF &
         "through = " & Quote & "latest" & Quote & ASCII.LF &
         "[reports.recent-transactions]" & ASCII.LF &
         "through = " & Quote & "latest" & Quote & ASCII.LF &
         "count = 10" & ASCII.LF);

      Write_File
        (To_String (Paths.Issues_TSV),
         "issue_id" & ASCII.HT & "status" & ASCII.HT & "date" & ASCII.HT &
         "due" & ASCII.HT & "closed" & ASCII.HT & "category" & ASCII.HT &
         "title" & ASCII.HT & "amount" & ASCII.HT & "currency" & ASCII.HT &
         "details" & ASCII.LF);

      Assert
        (not Load_Canonical_Household (Tmp_Dir, State, Err)
           and then Index
             (To_String (Err),
              "actual.journal: Account is not declared in accounts.journal: " &
              "expenses:actual-only") > 0,
         "Actual declaration cannot expand canonical Account authority");

      Delete_Tree (Tmp_Dir);
   end;

   Put_Line
     (Natural'Image (Passed_Count) & " passed, " &
      Natural'Image (Failed_Count) & " failed");

   if Failed_Count > 0 then
      raise Program_Error with "account admission tests failed";
   end if;
end Test_Account_Admission;
