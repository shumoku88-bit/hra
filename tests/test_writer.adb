with Ada.Command_Line;
with Ada.Directories; use Ada.Directories;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO; use Ada.Text_IO;
with HRA.Writer; use HRA.Writer;

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

   function Read_All (Path : String) return String is
      F      : File_Type;
      Result : Unbounded_String;
   begin
      Open (F, In_File, Path);
      while not End_Of_File (F) loop
         Append (Result, Get_Line (F));
         Append (Result, ASCII.LF);
      end loop;
      Close (F);
      return To_String (Result);
   end Read_All;

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
   Status  : Writer_Status;
   Error   : Unbounded_String;
   F       : File_Type;

begin
   Put_Line ("--- Testing HRA.Writer & Typed Publication Coordinates ---");

   --  ========================================================================
   --  1. Typed Coordinate Construction & Accessor Invariants
   --  ========================================================================
   declare
      Exp_Str : constant Expected_Source := Make_Expected_Source ("initial expected text");
      Exp_Unb : constant Expected_Source := Make_Expected_Source (To_Unbounded_String ("unbounded expected"));
      Can_Str : constant Candidate_Source := Make_Candidate_Source ("candidate text");
      Can_Unb : constant Candidate_Source := Make_Candidate_Source (To_Unbounded_String ("unbounded candidate"));
   begin
      Assert (Source_Text (Exp_Str) = "initial expected text",
              "Expected_Source from String preserves exact source text");
      Assert (To_String (Unbounded_Text (Exp_Unb)) = "unbounded expected",
              "Expected_Source from Unbounded_String preserves text");
      Assert (Source_Text (Can_Str) = "candidate text",
              "Candidate_Source from String preserves proposed source text");
      Assert (To_String (Unbounded_Text (Can_Unb)) = "unbounded candidate",
              "Candidate_Source from Unbounded_String preserves text");
   end;

   --  ========================================================================
   --  2. Safe Publication Protocol with Typed Coordinates
   --  ========================================================================
   if Exists (Target_File) then
      Delete_File (Target_File);
   end if;

   Create (F, Out_File, Target_File);
   Put (F, Initial_Text);
   Close (F);

   Assert
     (Append_Transaction_Safely
        (Target_File, New_Tx_Text, Status, Error)
      and then Status = Success,
      "append valid transaction through checked publication");

   declare
      Published : constant String := Read_All (Target_File);
      Expected_Snapshot : constant Expected_Source := Make_Expected_Source (Published);
      Stale_Snapshot    : constant Expected_Source := Make_Expected_Source ("stale source bytes");
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
      --  Stale rejection with typed Expected_Source
      Assert
        (not Atomic_Publish_Journal
           (Target_Path => Target_File,
            Expected    => Stale_Snapshot,
            Candidate   => Valid_Candidate,
            Status      => Status,
            Error_Msg   => Error)
         and then Status = Stale_Source_Rejected,
         "reject stale publication expectation with typed Expected_Source");

      --  Invalid candidate rejection with typed Candidate_Source
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
        (Read_All (Target_File) = Published,
         "failed publication leaves canonical bytes unchanged");

      --  Valid atomic publish with typed coordinates succeeds
      Assert
        (Atomic_Publish_Journal
           (Target_Path => Target_File,
            Expected    => Expected_Snapshot,
            Candidate   => Valid_Candidate,
            Status      => Status,
            Error_Msg   => Error)
         and then Status = Success,
         "atomic publish succeeds with matching Expected_Source and valid Candidate_Source");

      Assert
        (Read_All (Target_File) = Source_Text (Valid_Candidate),
         "atomic publish replaces canonical bytes with candidate bytes exactly");

      --  Append invalid transaction safely
      Assert
        (not Append_Transaction_Safely
           (Target_File, Invalid_Tx_Text, Status, Error)
         and then
           (Status = Pre_Admission_Failed or else
            Status = Post_Admission_Failed),
         "Append_Transaction_Safely rejects unbalanced candidate");
   end;

   --  ========================================================================
   --  3. Unique Candidate Sibling Staging
   --  ========================================================================
   declare
      Target_3 : constant String := "/tmp/hra_test_staging.journal";
      Init_3   : constant String :=
        "account assets:cash" & ASCII.LF &
        "  ; type: Asset" & ASCII.LF &
        "account expenses:food" & ASCII.LF &
        "  ; type: Expense" & ASCII.LF & ASCII.LF &
        "2026-08-10 Initial" & ASCII.LF &
        "    expenses:food          100 JPY" & ASCII.LF &
        "    assets:cash           -100 JPY" & ASCII.LF;
      Cand_3   : constant String :=
        Init_3 & ASCII.LF &
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
         Seen_Exists    := Exists (Staged_Path);
         if Seen_Exists then
            Seen_Content := To_Unbounded_String (Read_All (Staged_Path));
         end if;
      end Inspect_Staging;
   begin
      if Exists (Target_3) then
         Delete_File (Target_3);
      end if;

      Create (F, Out_File, Target_3);
      Put (F, Init_3);
      Close (F);

      Assert
        (Atomic_Publish_Journal
           (Target_Path      => Target_3,
            Expected         => Make_Expected_Source (Init_3),
            Candidate        => Make_Candidate_Source (Cand_3),
            Status           => Status,
            Error_Msg        => Error,
            After_Stage_Hook => Inspect_Staging'Access)
         and then Status = Success,
         "publish with staging hook succeeds");

      Assert
        (To_String (Captured_Stage) /= Target_3 & ".tmp",
         "staging path is not fixed static .tmp");
      Assert
        (To_String (Seen_Directory) = Containing_Directory (Target_3),
         "staging path is sibling in the same containing directory");
      Assert
        (Seen_Exists,
         "staging file physically existed during candidate staging");
      Assert
        (To_String (Seen_Content) = Cand_3,
         "staging file contained candidate source text");
      Assert
        (not Exists (To_String (Captured_Stage)),
         "staging file is cleaned up after successful publication");

      if Exists (Target_3) then
         Delete_File (Target_3);
      end if;
   end;

   --  ========================================================================
   --  4. Second Stale Fence: Concurrent Modification During Staging
   --  ========================================================================
   declare
      Target_4     : constant String := "/tmp/hra_test_second_stale.journal";
      Init_4       : constant String :=
        "account assets:cash" & ASCII.LF &
        "  ; type: Asset" & ASCII.LF &
        "account expenses:food" & ASCII.LF &
        "  ; type: Expense" & ASCII.LF & ASCII.LF &
        "2026-08-10 Initial" & ASCII.LF &
        "    expenses:food          100 JPY" & ASCII.LF &
        "    assets:cash           -100 JPY" & ASCII.LF;
      Cand_4       : constant String :=
        Init_4 & ASCII.LF &
        "2026-08-11 Candidate Mutation" & ASCII.LF &
        "    expenses:food          200 JPY" & ASCII.LF &
        "    assets:cash           -200 JPY" & ASCII.LF;
      External_Mod : constant String :=
        Init_4 & ASCII.LF &
        "2026-08-11 Process B Mutation" & ASCII.LF &
        "    expenses:food          500 JPY" & ASCII.LF &
        "    assets:cash           -500 JPY" & ASCII.LF;
      Captured_Stage_4 : Unbounded_String := Null_Unbounded_String;

      procedure Simulate_Process_B (Staged_Path : String) is
         Mod_File : File_Type;
      begin
         Captured_Stage_4 := To_Unbounded_String (Staged_Path);
         --  Process B modifies the target while Process A is between staging and publish
         Create (Mod_File, Out_File, Target_4);
         Put (Mod_File, External_Mod);
         Close (Mod_File);
      end Simulate_Process_B;
   begin
      if Exists (Target_4) then
         Delete_File (Target_4);
      end if;

      Create (F, Out_File, Target_4);
      Put (F, Init_4);
      Close (F);

      --  Initial stale check passes with Init_4.
      --  Candidate is staged.
      --  Hook runs and modifies Target_4 with External_Mod.
      --  Second stale fence must detect the change!
      Assert
        (not Atomic_Publish_Journal
           (Target_Path      => Target_4,
            Expected         => Make_Expected_Source (Init_4),
            Candidate        => Make_Candidate_Source (Cand_4),
            Status           => Status,
            Error_Msg        => Error,
            After_Stage_Hook => Simulate_Process_B'Access)
         and then Status = Stale_Source_Rejected,
         "second stale fence rejects publication when target was modified during staging");

      Assert
        (Read_All (Target_4) = External_Mod,
         "second stale rejection leaves concurrently modified target intact");

      Assert
        (not Exists (To_String (Captured_Stage_4)),
         "candidate staging temporary file is cleaned up after second stale rejection");

      if Exists (Target_4) then
         Delete_File (Target_4);
      end if;
   end;

   --  ========================================================================
   --  5. Second Stale Fence: Target Disappeared During Staging
   --  ========================================================================
   declare
      Target_5     : constant String := "/tmp/hra_test_disappeared.journal";
      Init_5       : constant String :=
        "account assets:cash" & ASCII.LF &
        "  ; type: Asset" & ASCII.LF &
        "account expenses:food" & ASCII.LF &
        "  ; type: Expense" & ASCII.LF & ASCII.LF &
        "2026-08-10 Initial" & ASCII.LF &
        "    expenses:food          100 JPY" & ASCII.LF &
        "    assets:cash           -100 JPY" & ASCII.LF;
      Cand_5       : constant String :=
        Init_5 & ASCII.LF &
        "2026-08-11 Candidate Mutation" & ASCII.LF &
        "    expenses:food          200 JPY" & ASCII.LF &
        "    assets:cash           -200 JPY" & ASCII.LF;
      Captured_Stage_5 : Unbounded_String := Null_Unbounded_String;

      procedure Simulate_Target_Deleted (Staged_Path : String) is
      begin
         Captured_Stage_5 := To_Unbounded_String (Staged_Path);
         if Exists (Target_5) then
            Delete_File (Target_5);
         end if;
      end Simulate_Target_Deleted;
   begin
      if Exists (Target_5) then
         Delete_File (Target_5);
      end if;

      Create (F, Out_File, Target_5);
      Put (F, Init_5);
      Close (F);

      Assert
        (not Atomic_Publish_Journal
           (Target_Path      => Target_5,
            Expected         => Make_Expected_Source (Init_5),
            Candidate        => Make_Candidate_Source (Cand_5),
            Status           => Status,
            Error_Msg        => Error,
            After_Stage_Hook => Simulate_Target_Deleted'Access)
         and then Status = Stale_Source_Rejected,
         "second stale fence rejects publication when expected target disappeared during staging");

      Assert
        (not Exists (Target_5),
         "disappeared target is not resurrected or created on stale rejection");

      Assert
        (not Exists (To_String (Captured_Stage_5)),
         "candidate staging temporary file is cleaned up after target deletion rejection");
   end;

   --  ========================================================================
   --  6. Concurrent Staging Sibling Collision Resistance
   --  ========================================================================
   declare
      Target_6     : constant String := "/tmp/hra_test_concurrent_staging.journal";
      Init_6       : constant String :=
        "account assets:cash" & ASCII.LF &
        "  ; type: Asset" & ASCII.LF &
        "account expenses:food" & ASCII.LF &
        "  ; type: Expense" & ASCII.LF & ASCII.LF &
        "2026-08-10 Initial" & ASCII.LF &
        "    expenses:food          100 JPY" & ASCII.LF &
        "    assets:cash           -100 JPY" & ASCII.LF;
      Cand_6A      : constant String :=
        Init_6 & ASCII.LF &
        "2026-08-11 Branch A" & ASCII.LF &
        "    expenses:food          200 JPY" & ASCII.LF &
        "    assets:cash           -200 JPY" & ASCII.LF;
      Cand_6B      : constant String :=
        Init_6 & ASCII.LF &
        "2026-08-11 Branch B" & ASCII.LF &
        "    expenses:food          300 JPY" & ASCII.LF &
        "    assets:cash           -300 JPY" & ASCII.LF;
      Captured_Stage_6A : Unbounded_String := Null_Unbounded_String;
      Captured_Stage_6B : Unbounded_String := Null_Unbounded_String;
      Nested_Success    : Boolean := False;
      Status_6B         : Writer_Status;
      Error_6B          : Unbounded_String;

      procedure Capture_6B (Staged_Path_B : String) is
      begin
         Captured_Stage_6B := To_Unbounded_String (Staged_Path_B);
         Assert
           (To_String (Captured_Stage_6A) /= To_String (Captured_Stage_6B),
            "concurrent publications allocate distinct unique staging paths");
         Assert
           (Exists (To_String (Captured_Stage_6A)) and then Exists (To_String (Captured_Stage_6B)),
            "both staging files coexist without collision");
      end Capture_6B;

      procedure Simulate_Concurrent_Publish (Staged_Path_A : String) is
      begin
         Captured_Stage_6A := To_Unbounded_String (Staged_Path_A);
         --  Concurrent writer publishes Cand_6B to Target_6 while 6A is staged
         Nested_Success :=
           Atomic_Publish_Journal
             (Target_Path      => Target_6,
              Expected         => Make_Expected_Source (Init_6),
              Candidate        => Make_Candidate_Source (Cand_6B),
              Status           => Status_6B,
              Error_Msg        => Error_6B,
              After_Stage_Hook => Capture_6B'Access);
      end Simulate_Concurrent_Publish;
   begin
      if Exists (Target_6) then
         Delete_File (Target_6);
      end if;

      Create (F, Out_File, Target_6);
      Put (F, Init_6);
      Close (F);

      --  Outer publish (6A) stages, then during hook, 6B runs and publishes successfully.
      --  When 6A resumes at second stale fence, Target_6 now contains 6B, so 6A is rejected.
      Assert
        (not Atomic_Publish_Journal
           (Target_Path      => Target_6,
            Expected         => Make_Expected_Source (Init_6),
            Candidate        => Make_Candidate_Source (Cand_6A),
            Status           => Status,
            Error_Msg        => Error,
            After_Stage_Hook => Simulate_Concurrent_Publish'Access)
         and then Status = Stale_Source_Rejected,
         "outer publish rejected by second stale fence after concurrent inner publication");

      Assert
        (Nested_Success and then Status_6B = Success,
         "concurrent inner publication succeeded");

      Assert
        (Read_All (Target_6) = Cand_6B,
         "target retains bytes of successful inner publication without being overwritten by outer candidate");

      Assert
        (not Exists (To_String (Captured_Stage_6A)),
         "outer staging file is cleaned up after second stale rejection");
      Assert
        (not Exists (To_String (Captured_Stage_6B)),
         "inner staging file is cleaned up after successful publication");

      if Exists (Target_6) then
         Delete_File (Target_6);
      end if;
   end;

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
