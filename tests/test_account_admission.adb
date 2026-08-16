with Ada.Directories;       use Ada.Directories;
with Ada.Strings.Fixed;      use Ada.Strings.Fixed;
with Ada.Strings.Unbounded;  use Ada.Strings.Unbounded;
with Ada.Text_IO;            use Ada.Text_IO;
with ALedger.Account;        use ALedger.Account;
with ALedger.Journal;        use ALedger.Journal;
with ALedger.Journal_Loader;
with ALedger.Ledger;         use ALedger.Ledger;

procedure Test_Account_Admission is
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

   procedure Write_File (Path : String; Text : String) is
      F : File_Type;
   begin
      Create (F, Out_File, Path);
      Put (F, Text);
      Close (F);
   end Write_File;

begin
   Put_Line ("--- Testing ALedger Account admission laws ---");

   declare
      Reg       : Account_Registry := Empty_Registry;
      Status    : Registry_Status;
      Decl      : Account_Declaration;
      Zeta      : constant Account := Make_Account ("expenses:zeta");
      Alpha     : constant Account := Make_Account ("assets:alpha");
      Middle    : constant Account := Make_Account ("income:middle");
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
      if Natural (Declarations (L.Registry)'Length) = 3 then
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
        (not Parse_Journal_Text (Duplicate, "accounts.journal", L, Err)
           and then Index (To_String (Err), "Duplicate account declaration") > 0,
         "duplicate Journal declaration fails admission");
   end;

   declare
      Tmp_Dir   : constant String := "/tmp/aledger_account_admission";
      Root_Path : constant String := Tmp_Dir & "/accounts.journal";
      Child_Path : constant String := Tmp_Dir & "/child.journal";
      Root_Text : constant String :=
        "account expenses:root-first" & ASCII.LF &
        "  ; type: Expense" & ASCII.LF &
        "include child.journal" & ASCII.LF &
        "account assets:root-last" & ASCII.LF &
        "  ; type: Asset" & ASCII.LF;
      Child_Text : constant String :=
        "account income:included" & ASCII.LF &
        "  ; type: Income" & ASCII.LF;
      Obs : ALedger.Journal_Loader.Journal_Observation;
      Err : Unbounded_String;
   begin
      if Exists (Tmp_Dir) then
         Delete_Tree (Tmp_Dir);
      end if;
      Create_Path (Tmp_Dir);
      Write_File (Root_Path, Root_Text);
      Write_File (Child_Path, Child_Text);

      Assert
        (ALedger.Journal_Loader.Load_From_Root_Source
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

   Put_Line
     (Natural'Image (Passed_Count) & " passed, " &
      Natural'Image (Failed_Count) & " failed");

   if Failed_Count > 0 then
      raise Program_Error with "account admission tests failed";
   end if;
end Test_Account_Admission;
