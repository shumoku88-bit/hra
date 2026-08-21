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

   if Exists (Target_File) then
      Delete_File (Target_File);
   end if;

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
