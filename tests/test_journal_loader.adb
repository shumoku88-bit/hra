with Ada.Directories;       use Ada.Directories;
with Ada.Streams;           use Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Strings.Fixed;     use Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO;           use Ada.Text_IO;
with HRA.Journal_Loader;
with HRA.Ledger;        use HRA.Ledger;
with HRA.Plan_Admission;

procedure Test_Journal_Loader is
   use type HRA.Journal_Loader.Source_Kind;

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

   procedure Write_Exact (Path : String; Text : String) is
      package SIO renames Ada.Streams.Stream_IO;
      File : SIO.File_Type;
   begin
      SIO.Create (File, SIO.Out_File, Path);
      if Text'Length > 0 then
         declare
            Bytes : Stream_Element_Array
              (1 .. Stream_Element_Offset (Text'Length));
         begin
            for I in Text'Range loop
               Bytes (Stream_Element_Offset (I - Text'First + 1)) :=
                 Stream_Element (Character'Pos (Text (I)));
            end loop;
            SIO.Write (File, Bytes);
         end;
      end if;
      SIO.Close (File);
   exception
      when others =>
         if SIO.Is_Open (File) then
            SIO.Close (File);
         end if;
         raise;
   end Write_Exact;

   Temp_Dir   : constant String := ".hra-test-journal-loader";
   Sub_Dir    : constant String := Compose (Temp_Dir, "sub");
   Root_Path  : constant String := Compose (Temp_Dir, "root.journal");
   Child_Path : constant String := Compose (Sub_Dir, "child.journal");
   Grand_Path : constant String := Compose (Temp_Dir, "grand.journal");
   Cycle_Path : constant String := Compose (Sub_Dir, "cycle.journal");
   Bad_Path   : constant String := Compose (Sub_Dir, "bad.journal");

   Root_Source : constant String :=
     "2026-08-01 Root Before" & ASCII.LF &
     "    ; plan-id: root-before" & ASCII.LF &
     "    expenses:root       100 JPY" & ASCII.LF &
     "    assets:cash        -100 JPY" & ASCII.LF &
     ASCII.LF &
     "include sub/child.journal" & ASCII.LF &
     ASCII.LF &
     "2026-08-04 Root After" & ASCII.LF &
     "    ; plan-id: root-after" & ASCII.LF &
     "    expenses:root       400 JPY" & ASCII.LF &
     "    assets:cash        -400 JPY" & ASCII.LF;

   Child_Source : constant String :=
     "2026-08-02 Child" & ASCII.LF &
     "    ; plan-id: child-plan" & ASCII.LF &
     "    expenses:child      200 JPY" & ASCII.LF &
     "    assets:cash        -200 JPY" & ASCII.LF &
     ASCII.LF &
     "include ../grand.journal" & ASCII.LF;

   Grand_Source : constant String :=
     "2026-08-03 Grand" & ASCII.LF &
     "    ; plan-id: grand-plan" & ASCII.LF &
     "    expenses:grand      300 JPY" & ASCII.LF &
     "    assets:cash        -300 JPY" & ASCII.LF;

   L   : HRA.Ledger.Ledger;
   Err : Unbounded_String;

begin
   Put_Line ("--- Testing HRA.Journal_Loader ---");

   if Exists (Temp_Dir) then
      Delete_Tree (Temp_Dir);
   end if;
   Create_Directory (Temp_Dir);
   Create_Directory (Sub_Dir);

   --  Exact-source assertions use exact binary fixtures. The root file keeps a
   --  sentinel because its bytes must never replace the caller-supplied source.
   Write_Exact (Root_Path, "THIS ON-DISK ROOT MUST NOT BE READ" & ASCII.LF);
   Write_Exact (Child_Path, Child_Source);
   Write_Exact (Grand_Path, Grand_Source);

   declare
      Obs : HRA.Journal_Loader.Journal_Observation;
   begin
      Assert
        (HRA.Journal_Loader.Load_From_Root_Source
           (Root_Path, Root_Source, Obs, Err),
         "load nested document-relative include graph from supplied root bytes");

      L := Obs.Value;
      Assert
        (Natural (L.Transactions.Length) = 4,
         "resolved graph retains all four transactions");
      Assert
        (To_String (L.Transactions.Element (1).Code_Or_Payee) = "Root Before"
           and then To_String (L.Transactions.Element (2).Code_Or_Payee) = "Child"
           and then To_String (L.Transactions.Element (3).Code_Or_Payee) = "Grand"
           and then To_String (L.Transactions.Element (4).Code_Or_Payee) = "Root After",
         "include substitution preserves source order");

      Assert
        (Natural (Obs.Sources.Length) = 3,
         "graph observation retains one exact source witness per physical document");

      declare
         Root_Witness  : constant HRA.Journal_Loader.Source_Observation :=
           Obs.Sources.Element (1);
         Child_Witness : constant HRA.Journal_Loader.Source_Observation :=
           Obs.Sources.Element (2);
         Grand_Witness : constant HRA.Journal_Loader.Source_Observation :=
           Obs.Sources.Element (3);
      begin
         Assert
           (Root_Witness.Kind = HRA.Journal_Loader.Supplied_Root
            and then Simple_Name (To_String (Root_Witness.Path)) = "root.journal"
            and then To_String (Root_Witness.Text) = Root_Source,
            "root witness retains supplied bytes rather than rereading on-disk root");
         Assert
           (Child_Witness.Kind = HRA.Journal_Loader.Included_File
            and then Simple_Name (To_String (Child_Witness.Path)) = "child.journal"
            and then To_String (Child_Witness.Text) = Child_Source
            and then Grand_Witness.Kind = HRA.Journal_Loader.Included_File
            and then Simple_Name (To_String (Grand_Witness.Path)) = "grand.journal"
            and then To_String (Grand_Witness.Text) = Grand_Source,
            "included source witnesses retain exact bytes used by the same graph admission");
      end;

      Assert
        (Natural (Obs.Evidence.Transactions.Length) = 4,
         "graph observation retains one source evidence row per transaction");
      Assert
        (Simple_Name
           (To_String (Obs.Evidence.Transactions.Element (1).Source_Path)) =
           "root.journal"
           and then Simple_Name
             (To_String (Obs.Evidence.Transactions.Element (2).Source_Path)) =
             "child.journal"
           and then Simple_Name
             (To_String (Obs.Evidence.Transactions.Element (3).Source_Path)) =
             "grand.journal"
           and then Simple_Name
             (To_String (Obs.Evidence.Transactions.Element (4).Source_Path)) =
             "root.journal",
         "transaction evidence retains physical source ownership");
      Assert
        (Obs.Evidence.Transactions.Element (1).Header_Line = 1
           and then Obs.Evidence.Transactions.Element (2).Header_Line = 1
           and then Obs.Evidence.Transactions.Element (3).Header_Line = 1
           and then Obs.Evidence.Transactions.Element (4).Header_Line = 8,
         "transaction evidence retains physical line coordinates");
      Assert
        (Natural (Obs.Evidence.Transactions.Element (2).Metadata.Length) = 1
           and then To_String
             (Obs.Evidence.Transactions.Element (2).Metadata.Element (1).Key) =
             "plan-id"
           and then To_String
             (Obs.Evidence.Transactions.Element (2).Metadata.Element (1).Value) =
             "child-plan",
         "included transaction metadata stays attached to its source evidence");

      declare
         Journal : HRA.Plan_Admission.Plan_Journal;
         Diag    : HRA.Plan_Admission.Admission_Diagnostic;
      begin
         Assert
           (HRA.Plan_Admission.Admit
              (Obs.Value, Obs.Evidence, Journal, Diag)
              and then HRA.Plan_Admission.Transaction_Count (Journal) = 4,
            "native Plan admission consumes resolved graph evidence directly");
      end;
   end;

   declare
      Duplicate_Source : constant String :=
        "include sub/child.journal" & ASCII.LF &
        "include sub/child.journal" & ASCII.LF;
   begin
      Assert
        (not HRA.Journal_Loader.Load_From_Root_Source
           (Root_Path, Duplicate_Source, L, Err)
           and then Index (To_String (Err), "already loaded") > 0,
         "reject duplicate include load with explicit diagnostic");
   end;

   declare
      Cycle_Root  : constant String := "include sub/cycle.journal" & ASCII.LF;
      Cycle_Child : constant String := "include ../root.journal" & ASCII.LF;
   begin
      Write_Exact (Root_Path, Cycle_Root);
      Write_Exact (Cycle_Path, Cycle_Child);
      Assert
        (not HRA.Journal_Loader.Load_From_Root_Source
           (Root_Path, Cycle_Root, L, Err)
           and then Index (To_String (Err), "include cycle") > 0,
         "reject recursive include cycle");
   end;

   declare
      Missing_Source : constant String :=
        "include sub/does-not-exist.journal" & ASCII.LF;
   begin
      Assert
        (not HRA.Journal_Loader.Load_From_Root_Source
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
      Write_Exact (Bad_Path, Bad_Source);
      Assert
        (not HRA.Journal_Loader.Load_From_Root_Source
           (Root_Path, Root_With_Bad, L, Err)
           and then Index (To_String (Err), "bad.journal:") > 0,
         "included parse failure retains included source path");
   end;

   declare
      Empty_Include : constant String := "include ; no path" & ASCII.LF;
   begin
      Assert
        (not HRA.Journal_Loader.Load_From_Root_Source
           (Root_Path, Empty_Include, L, Err)
           and then Index (To_String (Err), "requires a path") > 0,
         "reject empty include path instead of silently ignoring it");
   end;

   declare
      Malformed_Include : constant String :=
        "includeXYZ sub/child.journal" & ASCII.LF;
   begin
      Assert
        (not HRA.Journal_Loader.Load_From_Root_Source
           (Root_Path, Malformed_Include, L, Err)
           and then Index (To_String (Err), "invalid include directive") > 0,
         "reject malformed include token boundary");
   end;

   declare
      Comma_Source : constant String :=
        "2026-08-06 Comma Amount" & ASCII.LF &
        "    expenses:household  12,345 JPY" & ASCII.LF &
        "    assets:cash        -12,345 JPY" & ASCII.LF;
   begin
      Assert
        (not HRA.Journal_Loader.Load_From_Root_Source
           (Root_Path, Comma_Source, L, Err),
         "reject thousands grouping comma in canonical Journal amounts");
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
