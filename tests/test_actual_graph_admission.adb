with Ada.Command_Line;
with Ada.Directories; use Ada.Directories;
with Ada.Streams; use Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO; use Ada.Text_IO;
with HRA.Account;
with HRA.Actual_Admission;
with HRA.Actual_Candidate;
with HRA.Actual_Graph_Admission;
with HRA.Actual_Root_Candidate;
with HRA.Dates;
with HRA.Journal_Loader;
with HRA.Ledger;
with HRA.Money;

procedure Test_Actual_Graph_Admission is
   use type HRA.Actual_Admission.Admission_Status;
   use type HRA.Actual_Graph_Admission.Admission_Status;
   use type HRA.Journal_Loader.Source_Kind;
   use type HRA.Money.Quantity;

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

   function D (Value : String) return HRA.Dates.Date is
      Result : HRA.Dates.Date;
      Status : HRA.Dates.Date_Status;
   begin
      if not HRA.Dates.Parse (Value, Result, Status) then
         raise Program_Error with "invalid test date: " & Value;
      end if;
      return Result;
   end D;

   function Actual_ID (Value : String) return HRA.Actual_Admission.Actual_Id is
      Result : HRA.Actual_Admission.Actual_Id;
      Status : HRA.Actual_Admission.Actual_Id_Status;
   begin
      if not HRA.Actual_Admission.Create_Actual_Id (Value, Result, Status) then
         raise Program_Error with "invalid test Actual id: " & Value;
      end if;
      return Result;
   end Actual_ID;

   function Transaction_For
     (Payee : String;
      Day   : String) return HRA.Ledger.Transaction
   is
      Posts  : HRA.Ledger.Posting_Vectors.Vector;
      Tx     : HRA.Ledger.Transaction;
      Status : HRA.Ledger.Transaction_Error;
      JPY    : constant HRA.Money.Commodity := HRA.Money.Make_Commodity ("JPY");
   begin
      Posts.Append
        (HRA.Ledger.Make_Posting
           (HRA.Account.Make_Account ("assets:cash"),
            HRA.Money.Make_Amount (JPY, -20_000.0)));
      Posts.Append
        (HRA.Ledger.Make_Posting
           (HRA.Account.Make_Account ("expenses:household"),
            HRA.Money.Make_Amount (JPY, 20_000.0)));

      if not HRA.Ledger.Create_Transaction
        (D (Day), Payee, Posts, Tx, Status)
      then
         raise Program_Error with "failed to create graph candidate transaction";
      end if;
      return Tx;
   end Transaction_For;

   Temp_Dir  : constant String := ".hra-test-actual-graph-admission";
   Root_Path : constant String := Compose (Temp_Dir, "actual.journal");
   Child_Path : constant String := Compose (Temp_Dir, "child.journal");

   Root_Source : constant String :=
     "2026-08-18 Root Existing" & ASCII.LF &
     "    ; event-id: root-existing" & ASCII.LF &
     "    assets:cash" & ASCII.HT & "-100 JPY" & ASCII.LF &
     "    expenses:household" & ASCII.HT & "100 JPY" & ASCII.LF &
     "include child.journal" & ASCII.LF;

   Child_Source : constant String :=
     "2026-08-19 Child Existing" & ASCII.LF &
     "    ; event-id: child-existing" & ASCII.LF &
     "    assets:cash" & ASCII.HT & "-200 JPY" & ASCII.LF &
     "    expenses:household" & ASCII.HT & "200 JPY" & ASCII.LF;

   Changed_Child_Source : constant String :=
     "2026-08-19 Child Changed" & ASCII.LF &
     "    ; event-id: child-existing" & ASCII.LF &
     "    assets:cash" & ASCII.HT & "-250 JPY" & ASCII.LF &
     "    expenses:household" & ASCII.HT & "250 JPY" & ASCII.LF;

   Existing : HRA.Actual_Admission.Actual_Observation;

   procedure Build_Root_Candidate
     (ID_Text : String;
      Payee   : String;
      Result  : out HRA.Actual_Root_Candidate.Candidate_Root)
   is
      Block      : HRA.Actual_Candidate.Candidate_Block;
      Block_Diag : HRA.Actual_Candidate.Candidate_Diagnostic;
      Root_Diag  : HRA.Actual_Root_Candidate.Candidate_Diagnostic;
   begin
      if not HRA.Actual_Candidate.Prepare_Identified
        (Transaction_For (Payee, "2026-08-20"),
         Actual_ID (ID_Text),
         Block,
         Block_Diag)
      then
         raise Program_Error with "failed to prepare Actual block for graph test";
      end if;

      if not HRA.Actual_Root_Candidate.Prepare
        (Root_Path,
         Root_Source,
         Block,
         Result,
         Root_Diag)
      then
         raise Program_Error with "failed to prepare Actual root candidate for graph test";
      end if;
   end Build_Root_Candidate;

   procedure Build_Ordinary_Root_Candidate
     (Payee  : String;
      Result : out HRA.Actual_Root_Candidate.Candidate_Root)
   is
      Block      : HRA.Actual_Candidate.Candidate_Block;
      Block_Diag : HRA.Actual_Candidate.Candidate_Diagnostic;
      Root_Diag  : HRA.Actual_Root_Candidate.Candidate_Diagnostic;
   begin
      if not HRA.Actual_Candidate.Prepare_Ordinary
        (Transaction_For (Payee, "2026-08-20"),
         Block,
         Block_Diag)
      then
         raise Program_Error with "failed to prepare ordinary Actual block for graph test";
      end if;

      if not HRA.Actual_Root_Candidate.Prepare
        (Root_Path,
         Root_Source,
         Block,
         Result,
         Root_Diag)
      then
         raise Program_Error with "failed to prepare ordinary root candidate for graph test";
      end if;
   end Build_Ordinary_Root_Candidate;

begin
   Put_Line ("--- Testing Actual candidate graph admission ---");

   if Exists (Temp_Dir) then
      Delete_Tree (Temp_Dir);
   end if;
   Create_Directory (Temp_Dir);

   --  Exact-source tests must create exact source bytes. The root still carries
   --  sentinel bytes because the typed candidate, not the file, owns root input.
   Write_Exact (Root_Path, "THIS ON-DISK ROOT MUST NOT BE READ" & ASCII.LF);
   Write_Exact (Child_Path, Child_Source);

   declare
      Graph       : HRA.Journal_Loader.Journal_Observation;
      Graph_Error : Unbounded_String;
      Actual_Diag : HRA.Actual_Admission.Admission_Diagnostic;
   begin
      if not HRA.Journal_Loader.Load_From_Root_Source
        (Root_Path, Root_Source, Graph, Graph_Error)
      then
         raise Program_Error with
           "failed to prepare existing graph authority: " & To_String (Graph_Error);
      end if;

      if not HRA.Actual_Admission.Admit
        (Graph.Value, Graph.Evidence, Existing, Actual_Diag)
      then
         raise Program_Error with "failed to admit existing Actual authority";
      end if;
   end;

   Assert
     (HRA.Actual_Admission.Transaction_Count (Existing) = 2,
      "Setup retains two Actual facts across root and included source");

   declare
      Root_Candidate  : HRA.Actual_Root_Candidate.Candidate_Root;
      Graph_Candidate : HRA.Actual_Graph_Admission.Candidate_Graph;
      Diag            : HRA.Actual_Graph_Admission.Admission_Diagnostic;
   begin
      Build_Root_Candidate ("chair-actual", "Chair", Root_Candidate);
      Assert
        (HRA.Actual_Graph_Admission.Admit_Candidate_Root
           (Existing,
            Root_Candidate,
            Graph_Candidate,
            Diag),
         "Candidate graph resolves includes from its bound root source and admits one new Actual");

      declare
         Bound_Root : constant HRA.Actual_Root_Candidate.Candidate_Root :=
           HRA.Actual_Graph_Admission.Root_Of (Graph_Candidate);
      begin
         Assert
           (HRA.Actual_Root_Candidate.Root_Path_Of (Bound_Root) = Root_Path
            and then HRA.Actual_Root_Candidate.Observed_Text (Bound_Root) = Root_Source
            and then HRA.Actual_Root_Candidate.Text (Bound_Root) =
              HRA.Actual_Root_Candidate.Text (Root_Candidate),
            "Candidate graph retains the root path, observed bytes, and candidate bytes that produced it");
      end;

      Assert
        (HRA.Actual_Graph_Admission.Source_Count (Graph_Candidate) = 2,
         "Candidate graph retains one supplied root witness and one included-file witness");

      declare
         Root_Witness : constant HRA.Journal_Loader.Source_Observation :=
           HRA.Actual_Graph_Admission.Source_At (Graph_Candidate, 1);
         Child_Witness : constant HRA.Journal_Loader.Source_Observation :=
           HRA.Actual_Graph_Admission.Source_At (Graph_Candidate, 2);
      begin
         Assert
           (Root_Witness.Kind = HRA.Journal_Loader.Supplied_Root
            and then To_String (Root_Witness.Path) = Full_Name (Root_Path)
            and then To_String (Root_Witness.Text) =
              HRA.Actual_Root_Candidate.Text (Root_Candidate)
            and then Child_Witness.Kind = HRA.Journal_Loader.Included_File
            and then To_String (Child_Witness.Path) = Full_Name (Child_Path)
            and then To_String (Child_Witness.Text) = Child_Source,
            "Graph source witness uses supplied candidate root bytes and exact included bytes from the same admission");
      end;

      declare
         Observation : constant HRA.Actual_Admission.Actual_Observation :=
           HRA.Actual_Graph_Admission.Observation_Of (Graph_Candidate);
      begin
         Assert
           (HRA.Actual_Admission.Transaction_Count (Observation) = 3,
            "Candidate graph is exactly one transaction longer than existing authority");

         declare
            Appended : constant HRA.Actual_Admission.Actual_Transaction_Entry :=
              HRA.Actual_Admission.Transaction_At (Observation, 3);
         begin
            Assert
              (Appended.Source_Durable_Identity.Present
               and then HRA.Actual_Admission.Text
                 (Appended.Source_Durable_Identity.Value) = "chair-actual"
               and then Simple_Name (To_String (Appended.Source.Source_Path)) =
                 "actual.journal"
               and then To_String (Appended.Tx.Code_Or_Payee) = "Chair",
               "New graph member retains root-owned durable identity and typed meaning");
         end;
      end;
   end;

   declare
      Root_Candidate  : HRA.Actual_Root_Candidate.Candidate_Root;
      Graph_Candidate : HRA.Actual_Graph_Admission.Candidate_Graph;
      Diag            : HRA.Actual_Graph_Admission.Admission_Diagnostic;
   begin
      Build_Root_Candidate ("child-existing", "Duplicate", Root_Candidate);
      Assert
        (not HRA.Actual_Graph_Admission.Admit_Candidate_Root
           (Existing,
            Root_Candidate,
            Graph_Candidate,
            Diag)
         and then Diag.Status =
           HRA.Actual_Graph_Admission.Candidate_Actual_Admission_Failed
         and then Diag.Actual.Status = HRA.Actual_Admission.Duplicate_Actual_Id,
         "Include-graph admission rejects durable identity collision hidden from root-local preparation");
   end;

   declare
      Root_Candidate  : HRA.Actual_Root_Candidate.Candidate_Root;
      Graph_Candidate : HRA.Actual_Graph_Admission.Candidate_Graph;
      Diag            : HRA.Actual_Graph_Admission.Admission_Diagnostic;
   begin
      Write_Exact (Child_Path, Changed_Child_Source);
      Build_Root_Candidate ("after-drift", "After Drift", Root_Candidate);
      Assert
        (not HRA.Actual_Graph_Admission.Admit_Candidate_Root
           (Existing,
            Root_Candidate,
            Graph_Candidate,
            Diag)
         and then Diag.Status = HRA.Actual_Graph_Admission.Existing_History_Changed,
         "Candidate graph rejects semantic drift in an included source relative to admitted authority");
   end;

   declare
      Root_Candidate  : HRA.Actual_Root_Candidate.Candidate_Root;
      Graph_Candidate : HRA.Actual_Graph_Admission.Candidate_Graph;
      Diag            : HRA.Actual_Graph_Admission.Admission_Diagnostic;
   begin
      Delete_File (Child_Path);
      Build_Root_Candidate ("missing-child", "Missing Child", Root_Candidate);
      Assert
        (not HRA.Actual_Graph_Admission.Admit_Candidate_Root
           (Existing,
            Root_Candidate,
            Graph_Candidate,
            Diag)
         and then Diag.Status = HRA.Actual_Graph_Admission.Candidate_Graph_Load_Failed,
         "Candidate graph fails closed when an included source disappears");
   end;

   --  Ordinary identity-free graph admission
   Write_Exact (Child_Path, Child_Source);
   declare
      Root_Candidate  : HRA.Actual_Root_Candidate.Candidate_Root;
      Graph_Candidate : HRA.Actual_Graph_Admission.Candidate_Graph;
      Diag            : HRA.Actual_Graph_Admission.Admission_Diagnostic;
   begin
      Build_Ordinary_Root_Candidate ("Ordinary Coffee", Root_Candidate);
      Assert
        (HRA.Actual_Graph_Admission.Admit_Candidate_Root
           (Existing,
            Root_Candidate,
            Graph_Candidate,
            Diag),
         "Identity-free ordinary Actual is admitted through the candidate graph");

      declare
         Observation : constant HRA.Actual_Admission.Actual_Observation :=
           HRA.Actual_Graph_Admission.Observation_Of (Graph_Candidate);
         Appended : constant HRA.Actual_Admission.Actual_Transaction_Entry :=
           HRA.Actual_Admission.Transaction_At (Observation, 3);
      begin
         Assert
           (not Appended.Identity.Present
            and then not Appended.Source_Durable_Identity.Present,
            "Ordinary appended Actual has no effective identity and no source-durable identity");
         Assert
           (To_String (Appended.Tx.Code_Or_Payee) = "Ordinary Coffee",
            "Ordinary appended Actual retains typed Transaction meaning");
      end;
   end;

   Delete_Tree (Temp_Dir);

   Put_Line
     ("Summary: Passed =" & Natural'Image (Passed_Count) &
      ", Failed =" & Natural'Image (Failed_Count));

   if Failed_Count > 0 then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   else
      Put_Line ("RESULT: SUCCESS");
   end if;
exception
   when others =>
      if Exists (Temp_Dir) then
         Delete_Tree (Temp_Dir);
      end if;
      raise;
end Test_Actual_Graph_Admission;
