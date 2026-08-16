with Ada.Directories;       use Ada.Directories;
with Ada.Strings.Fixed;     use Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO;           use Ada.Text_IO;
with ALedger.Journal_Loader;
with ALedger.Ledger;        use ALedger.Ledger;

procedure Test_Journal_Loader is
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

   procedure Write_Text (Path : String; Text : String) is
      File : File_Type;
   begin
      Create (File, Out_File, Path);
      Put (File, Text);
      Close (File);
   end Write_Text;

   Temp_Dir  : constant String := ".aledger-test-journal-loader";
   Sub_Dir   : constant String := Compose (Temp_Dir, "sub");
   Root_Path : constant String := Compose (Temp_Dir, "root.journal");
   Child_Path : constant String := Compose (Sub_Dir, "child.journal");
   Grand_Path : constant String := Compose (Temp_Dir, "grand.journal");
   Cycle_Path : constant String := Compose (Sub_Dir, "cycle.journal");
   Bad_Path   : constant String := Compose (Sub_Dir, "bad.journal");

   Root_Source : constant String :=
     "2026-08-01 Root Before" & ASCII.LF &
     "    expenses:root       100 JPY" & ASCII.LF &
     "    assets:cash        -100 JPY" & ASCII.LF &
     ASCII.LF &
     "include sub/child.journal" & ASCII.LF &
     ASCII.LF &
     "2026-08-04 Root After" & ASCII.LF &
     "    expenses:root       400 JPY" & ASCII.LF &
     "    assets:cash        -400 JPY" & ASCII.LF;

   Child_Source : constant String :=
     "2026-08-02 Child" & ASCII.LF &
     "    expenses:child      200 JPY" & ASCII.LF &
     "    assets:cash        -200 JPY" & ASCII.LF &
     ASCII.LF &
     "include ../grand.journal" & ASCII.LF;

   Grand_Source : constant String :=
     "2026-08-03 Grand" & ASCII.LF &
     "    expenses:grand      300 JPY" & ASCII.LF &
     "    assets:cash        -300 JPY" & ASCII.LF;

   L   : ALedger.Ledger.Ledger;
   Err : Unbounded_String;

begin
   Put_Line ("--- Testing ALedger.Journal_Loader ---");

   if Exists (Temp_Dir) then
      Delete_Tree (Temp_Dir);
   end if;
   Create_Directory (Temp_Dir);
   Create_Directory (Sub_Dir);

   Write_Text (Root_Path, "THIS ON-DISK ROOT MUST NOT BE READ" & ASCII.LF);
   Write_Text (Child_Path, Child_Source);
   Write_Text (Grand_Path, Grand_Source);

   Assert
     (ALedger.Journal_Loader.Load_From_Root_Source
        (Root_Path, Root_Source, L, Err),
      "load nested document-relative include graph from supplied root bytes");
   Assert
     (Natural (L.Transactions.Length) = 4,
      "resolved graph retains all four transactions");
   Assert
     (To_String (L.Transactions.Element (1).Code_Or_Payee) = "Root Before"
        and then To_String (L.Transactions.Element (2).Code_Or_Payee) = "Child"
        and then To_String (L.Transactions.Element (3).Code_Or_Payee) = "Grand"
        and then To_String (L.Transactions.Element (4).Code_Or_Payee) = "Root After",
      "include substitution preserves source order");

   declare
      Duplicate_Source : constant String :=
        "include sub/child.journal" & ASCII.LF &
        "include sub/child.journal" & ASCII.LF;
   begin
      Assert
        (not ALedger.Journal_Loader.Load_From_Root_Source
           (Root_Path, Duplicate_Source, L, Err)
           and then Index (To_String (Err), "already loaded") > 0,
         "reject duplicate include load with explicit diagnostic");
   end;

   declare
      Cycle_Root : constant String := "include sub/cycle.journal" & ASCII.LF;
      Cycle_Child : constant String := "include ../root.journal" & ASCII.LF;
   begin
      Write_Text (Root_Path, Cycle_Root);
      Write_Text (Cycle_Path, Cycle_Child);
      Assert
        (not ALedger.Journal_Loader.Load_From_Root_Source
           (Root_Path, Cycle_Root, L, Err)
           and then Index (To_String (Err), "include cycle") > 0,
         "reject recursive include cycle");
   end;

   declare
      Missing_Source : constant String :=
        "include sub/does-not-exist.journal" & ASCII.LF;
   begin
      Assert
        (not ALedger.Journal_Loader.Load_From_Root_Source
           (Root_Path, Missing_Source, L, Err)
           and then Index (To_String (Err), "missing or not a regular file") > 0,
         "reject missing included document");
   end;

   declare
      Bad_Source : constant String :=
        "2026-08-05 Broken" & ASCII.LF &
        "    expenses:broken     100 JPY" & ASCII.LF &
        "    assets:cash         -50 JPY" & ASCII.LF;
      Root_With_Bad : constant String := "include sub/bad.journal" & ASCII.LF;
   begin
      Write_Text (Bad_Path, Bad_Source);
      Assert
        (not ALedger.Journal_Loader.Load_From_Root_Source
           (Root_Path, Root_With_Bad, L, Err)
           and then Index (To_String (Err), "bad.journal:") > 0,
         "included parse failure retains included source path");
   end;

   declare
      Empty_Include : constant String := "include ; no path" & ASCII.LF;
   begin
      Assert
        (not ALedger.Journal_Loader.Load_From_Root_Source
           (Root_Path, Empty_Include, L, Err)
           and then Index (To_String (Err), "invalid include directive") > 0,
         "reject empty include path instead of silently ignoring it");
   end;

   Delete_Tree (Temp_Dir);

   Put_Line
     (Natural'Image (Passed_Count) & " passed, " &
      Natural'Image (Failed_Count) & " failed");

   if Failed_Count > 0 then
      raise Program_Error with "journal loader tests failed";
   end if;
exception
   when others =>
      if Exists (Temp_Dir) then
         Delete_Tree (Temp_Dir);
      end if;
      raise;
end Test_Journal_Loader;
