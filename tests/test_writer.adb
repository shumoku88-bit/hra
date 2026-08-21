with Ada.Command_Line;
with Ada.Directories; use Ada.Directories;
with Ada.Streams; use Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO; use Ada.Text_IO;
with HRA.Writer; use HRA.Writer;
with HRA.Writer.Test_Hooks;

procedure Test_Writer is
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
   end Write_Exact;

   function Must_Observe (Path : String) return Expected_Source is
      Result : Expected_Source;
      Error  : Unbounded_String;
   begin
      if not Observe_Source (Path, Result, Error) then
         raise Program_Error with
           "failed to observe test source " & Path & ": " & To_String (Error);
      end if;
      return Result;
   end Must_Observe;

   function Exact_Text (Path : String) return String is
      Observed : constant Expected_Source := Must_Observe (Path);
   begin
      if Presence_Of (Observed) = Absent then
         raise Program_Error with "expected present test source: " & Path;
      end if;
      return Source_Text (Observed);
   end Exact_Text;

   procedure Remove_If_Present (Path : String) is
   begin
      if Exists (Path) then
         if Kind (Path) = Directory then
            Delete_Tree (Path);
         else
            Delete_File (Path);
         end if;
      end if;
   end Remove_If_Present;

   Base_Journal : constant String :=
     "account assets:cash" & ASCII.LF &
     "  ; type: Asset" & ASCII.LF &
     "account expenses:food" & ASCII.LF &
     "  ; type: Expense" & ASCII.LF & ASCII.LF &
     "2026-08-10 Initial" & ASCII.LF &
     "    expenses:food          100 JPY" & ASCII.LF &
     "    assets:cash           -100 JPY" & ASCII.LF;

   Target_File : constant String := "/tmp/hra_test_writer.journal";
   Initial_Text : constant String :=
     "account assets:cash" & ASCII.LF &
     "  ; type: Asset" & ASCII.LF &
     "account expenses:food" & ASCII.LF &
     "  ; type: Expense" & ASCII.LF & ASCII.LF &
     "2026-08-13 Lunch" & ASCII.LF &
     "    expenses:food          800 JPY" & ASCII.LF &
     "    assets:cash           -800 JPY" & ASCII.LF;
   New_Tx_Text : constant String :=
     "2026-08-14 Dinner" & ASCII.LF &
     "    expenses:food         1200 JPY" & ASCII.LF &
     "    assets:cash          -1200 JPY" & ASCII.LF;
   Invalid_Tx_Text : constant String :=
     "2026-08-15 Unbalanced" & ASCII.LF &
     "    expenses:food         1000 JPY" & ASCII.LF &
     "    assets:cash           -500 JPY" & ASCII.LF;

   Status : Writer_Status;
   Error  : Unbounded_String;

begin
   Put_Line ("--- Testing HRA.Writer & Typed Publication Coordinates ---");

   declare
      Exp_Str : constant Expected_Source :=
        Make_Expected_Source ("initial expected text");
      Exp_Unb : constant Expected_Source :=
        Make_Expected_Source (To_Unbounded_String ("unbounded expected"));
      Can_Str : constant Candidate_Source :=
        Make_Candidate_Source ("candidate text");
      Can_Unb : constant Candidate_Source :=
        Make_Candidate_Source (To_Unbounded_String ("unbounded candidate"));
   begin
      Assert
        (Presence_Of (Exp_Str) = Present
         and then Source_Text (Exp_Str) = "initial expected text",
         "Expected_Source from String is an explicit present premise");
      Assert
        (To_String (Unbounded_Text (Exp_Unb)) = "unbounded expected",
         "Expected_Source from Unbounded_String preserves exact text");
      Assert
        (Source_Text (Can_Str) = "candidate text",
         "Candidate_Source from String preserves proposed source text");
      Assert
        (To_String (Unbounded_Text (Can_Unb)) = "unbounded candidate",
         "Candidate_Source from Unbounded_String preserves text");
      Assert
        (Presence_Of (Make_Absent_Expected_Source) = Absent,
         "Absent publication premise is explicit");
   end;

   Remove_If_Present (Target_File);
   Write_Exact (Target_File, Initial_Text);

   Assert
     (Append_Transaction_Safely
        (Target_File, New_Tx_Text, Status, Error)
      and then Status = Success,
      "append valid transaction through checked publication");

   declare
      Expected_Snapshot : constant Expected_Source := Must_Observe (Target_File);
      Published         : constant String := Source_Text (Expected_Snapshot);
      Stale_Snapshot    : constant Expected_Source :=
        Make_Expected_Source ("stale source bytes");
      Valid_Candidate   : constant Candidate_Source :=
        Make_Candidate_Source
          (Published & ASCII.LF &
           "2026-08-16 Coffee" & ASCII.LF &
           "    expenses:food          400 JPY" & ASCII.LF &
           "    assets:cash           -400 JPY" & ASCII.LF);
      Invalid_Candidate : constant Candidate_Source :=
        Make_Candidate_Source
          (Published & ASCII.LF &
           "2026-08-16 Bad Leg" & ASCII.LF &
           "    expenses:food          400 JPY" & ASCII.LF);
   begin
      Assert
        (not Atomic_Publish_Journal
           (Target_Path => Target_File,
            Expected    => Stale_Snapshot,
            Candidate   => Valid_Candidate,
            Status      => Status,
            Error_Msg   => Error)
         and then Status = Stale_Source_Rejected,
         "reject stale publication expectation");

      Assert
        (not Atomic_Publish_Journal
           (Target_Path => Target_File,
            Expected    => Expected_Snapshot,
            Candidate   => Invalid_Candidate,
            Status      => Status,
            Error_Msg   => Error)
         and then
           (Status = Pre_Admission_Failed or else
            Status = Post_Admission_Failed),
         "reject unbalanced candidate before publication becomes durable");

      Assert
        (Exact_Text (Target_File) = Published,
         "failed publication leaves exact source bytes unchanged");

      Assert
        (Atomic_Publish_Journal
           (Target_Path => Target_File,
            Expected    => Expected_Snapshot,
            Candidate   => Valid_Candidate,
            Status      => Status,
            Error_Msg   => Error)
         and then Status = Success,
         "atomic publish succeeds from an observed source premise");

      Assert
        (Exact_Text (Target_File) = Source_Text (Valid_Candidate),
         "atomic publish replaces source with candidate bytes exactly");

      Assert
        (not Append_Transaction_Safely
           (Target_File, Invalid_Tx_Text, Status, Error)
         and then
           (Status = Pre_Admission_Failed or else
            Status = Post_Admission_Failed),
         "Append_Transaction_Safely rejects unbalanced candidate");
   end;

   declare
      Target_3 : constant String := "/tmp/hra_test_staging.journal";
      Cand_3   : constant String :=
        Base_Journal & ASCII.LF &
        "2026-08-11 Second" & ASCII.LF &
        "    expenses:food          200 JPY" & ASCII.LF &
        "    assets:cash           -200 JPY" & ASCII.LF;
      Captured_Stage : Unbounded_String := Null_Unbounded_String;
      Seen_Directory : Unbounded_String := Null_Unbounded_String;
      Seen_Exists    : Boolean := False;
      Seen_Content   : Unbounded_String := Null_Unbounded_String;

      procedure Inspect_Staging (Staged_Path : String) is
      begin
         Captured_Stage := To_Unbounded_String (Staged_Path);
         Seen_Directory := To_Unbounded_String (Containing_Directory (Staged_Path));
         Seen_Exists := Exists (Staged_Path);
         if Seen_Exists then
            Seen_Content := To_Unbounded_String (Exact_Text (Staged_Path));
         end if;
      end Inspect_Staging;
   begin
      Remove_If_Present (Target_3);
      Write_Exact (Target_3, Base_Journal);
      declare
         Expected_3 : constant Expected_Source := Must_Observe (Target_3);
      begin
         HRA.Writer.Test_Hooks.Set_After_Stage_Hook (Inspect_Staging'Address);
         Assert
           (Atomic_Publish_Journal
              (Target_Path => Target_3,
               Expected    => Expected_3,
               Candidate   => Make_Candidate_Source (Cand_3),
               Status      => Status,
               Error_Msg   => Error)
            and then Status = Success,
            "publish with staging hook succeeds from observed premise");
         HRA.Writer.Test_Hooks.Clear_After_Stage_Hook;
      end;

      Assert
        (Length (Captured_Stage) > 0
         and then To_String (Captured_Stage) /= Target_3 & ".tmp",
         "staging path is a unique sibling path");
      Assert
        (To_String (Seen_Directory) = Containing_Directory (Target_3),
         "staging path is sibling in the same containing directory");
      Assert (Seen_Exists, "staging file existed during candidate staging");
      Assert
        (To_String (Seen_Content) = Cand_3,
         "staging file contained candidate source bytes exactly");
      Assert
        (Length (Captured_Stage) > 0
         and then not Exists (To_String (Captured_Stage)),
         "staging file is cleaned after successful publication");
      Remove_If_Present (Target_3);
   end;

   declare
      Target_4 : constant String := "/tmp/hra_test_second_stale.journal";
      Cand_4   : constant String :=
        Base_Journal & ASCII.LF &
        "2026-08-11 Candidate Mutation" & ASCII.LF &
        "    expenses:food          200 JPY" & ASCII.LF &
        "    assets:cash           -200 JPY" & ASCII.LF;
      External_Mod : constant String :=
        Base_Journal & ASCII.LF &
        "2026-08-11 Process B Mutation" & ASCII.LF &
        "    expenses:food          500 JPY" & ASCII.LF &
        "    assets:cash           -500 JPY" & ASCII.LF;
      Captured_Stage : Unbounded_String := Null_Unbounded_String;

      procedure Simulate_Process_B (Staged_Path : String) is
      begin
         Captured_Stage := To_Unbounded_String (Staged_Path);
         Write_Exact (Target_4, External_Mod);
      end Simulate_Process_B;
   begin
      Remove_If_Present (Target_4);
      Write_Exact (Target_4, Base_Journal);
      declare
         Expected_4 : constant Expected_Source := Must_Observe (Target_4);
      begin
         HRA.Writer.Test_Hooks.Set_After_Stage_Hook (Simulate_Process_B'Address);
         Assert
           (not Atomic_Publish_Journal
              (Target_Path => Target_4,
               Expected    => Expected_4,
               Candidate   => Make_Candidate_Source (Cand_4),
               Status      => Status,
               Error_Msg   => Error)
            and then Status = Stale_Source_Rejected,
            "second stale fence rejects concurrent exact-source modification");
         HRA.Writer.Test_Hooks.Clear_After_Stage_Hook;
      end;

      Assert
        (Exact_Text (Target_4) = External_Mod,
         "second stale rejection leaves concurrent source intact");
      Assert
        (Length (Captured_Stage) > 0
         and then not Exists (To_String (Captured_Stage)),
         "staging file is cleaned after second stale rejection");
      Remove_If_Present (Target_4);
   end;

   declare
      Target_5 : constant String := "/tmp/hra_test_disappeared.journal";
      Cand_5   : constant String :=
        Base_Journal & ASCII.LF &
        "2026-08-11 Candidate Mutation" & ASCII.LF &
        "    expenses:food          200 JPY" & ASCII.LF &
        "    assets:cash           -200 JPY" & ASCII.LF;
      Captured_Stage : Unbounded_String := Null_Unbounded_String;

      procedure Simulate_Target_Deleted (Staged_Path : String) is
      begin
         Captured_Stage := To_Unbounded_String (Staged_Path);
         Remove_If_Present (Target_5);
      end Simulate_Target_Deleted;
   begin
      Remove_If_Present (Target_5);
      Write_Exact (Target_5, Base_Journal);
      declare
         Expected_5 : constant Expected_Source := Must_Observe (Target_5);
      begin
         HRA.Writer.Test_Hooks.Set_After_Stage_Hook (Simulate_Target_Deleted'Address);
         Assert
           (not Atomic_Publish_Journal
              (Target_Path => Target_5,
               Expected    => Expected_5,
               Candidate   => Make_Candidate_Source (Cand_5),
               Status      => Status,
               Error_Msg   => Error)
            and then Status = Stale_Source_Rejected,
            "second stale fence rejects disappearance of observed source");
         HRA.Writer.Test_Hooks.Clear_After_Stage_Hook;
      end;

      Assert
        (not Exists (Target_5),
         "disappeared target is not resurrected on stale rejection");
      Assert
        (Length (Captured_Stage) > 0
         and then not Exists (To_String (Captured_Stage)),
         "staging file is cleaned after target disappearance");
   end;

   declare
      Target_6 : constant String := "/tmp/hra_test_concurrent_staging.journal";
      Cand_6A  : constant String :=
        Base_Journal & ASCII.LF &
        "2026-08-11 Branch A" & ASCII.LF &
        "    expenses:food          200 JPY" & ASCII.LF &
        "    assets:cash           -200 JPY" & ASCII.LF;
      Cand_6B  : constant String :=
        Base_Journal & ASCII.LF &
        "2026-08-11 Branch B" & ASCII.LF &
        "    expenses:food          300 JPY" & ASCII.LF &
        "    assets:cash           -300 JPY" & ASCII.LF;
      Captured_Stage_6A : Unbounded_String := Null_Unbounded_String;
      Captured_Stage_6B : Unbounded_String := Null_Unbounded_String;
      Nested_Success    : Boolean := False;
      Status_6B         : Writer_Status;
      Error_6B          : Unbounded_String;
      Expected_6        : Expected_Source;

      procedure Capture_6B (Staged_Path_B : String) is
      begin
         Captured_Stage_6B := To_Unbounded_String (Staged_Path_B);
         Assert
           (To_String (Captured_Stage_6A) /= To_String (Captured_Stage_6B),
            "concurrent publications allocate distinct staging paths");
         Assert
           (Exists (To_String (Captured_Stage_6A))
            and then Exists (To_String (Captured_Stage_6B)),
            "both concurrent staging files coexist");
      end Capture_6B;

      procedure Simulate_Concurrent_Publish (Staged_Path_A : String) is
      begin
         Captured_Stage_6A := To_Unbounded_String (Staged_Path_A);
         HRA.Writer.Test_Hooks.Set_After_Stage_Hook (Capture_6B'Address);
         Nested_Success :=
           Atomic_Publish_Journal
             (Target_Path => Target_6,
              Expected    => Expected_6,
              Candidate   => Make_Candidate_Source (Cand_6B),
              Status      => Status_6B,
              Error_Msg   => Error_6B);
      end Simulate_Concurrent_Publish;
   begin
      Remove_If_Present (Target_6);
      Write_Exact (Target_6, Base_Journal);
      Expected_6 := Must_Observe (Target_6);

      HRA.Writer.Test_Hooks.Set_After_Stage_Hook
        (Simulate_Concurrent_Publish'Address);
      Assert
        (not Atomic_Publish_Journal
           (Target_Path => Target_6,
            Expected    => Expected_6,
            Candidate   => Make_Candidate_Source (Cand_6A),
            Status      => Status,
            Error_Msg   => Error)
         and then Status = Stale_Source_Rejected,
         "outer publication is rejected after inner publication changes source");
      HRA.Writer.Test_Hooks.Clear_After_Stage_Hook;

      Assert
        (Nested_Success and then Status_6B = Success,
         "concurrent inner publication succeeded");
      Assert
        (Exact_Text (Target_6) = Cand_6B,
         "target retains successful inner publication bytes");
      Assert
        (Length (Captured_Stage_6A) > 0
         and then not Exists (To_String (Captured_Stage_6A)),
         "outer staging file is cleaned after stale rejection");
      Assert
        (Length (Captured_Stage_6B) > 0
         and then not Exists (To_String (Captured_Stage_6B)),
         "inner staging file is cleaned after successful publication");
      Remove_If_Present (Target_6);
   end;

   Remove_If_Present (Target_File);

   New_Line;
   Put_Line
     ("Summary: Passed =" & Natural'Image (Passed_Count) &
      ", Failed =" & Natural'Image (Failed_Count));

   if Failed_Count > 0 then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   else
      Put_Line ("RESULT: SUCCESS");
   end if;
end Test_Writer;
