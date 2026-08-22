with Ada.Command_Line;
with Ada.Directories; use Ada.Directories;
with Ada.Streams; use Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO; use Ada.Text_IO;
with HRA.Writer; use HRA.Writer;
with HRA.Writer.Test_Hooks;

procedure Test_Writer_Exact_Source is
   use type HRA.Writer.Source_Presence;
   use type HRA.Writer.Writer_Status;

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
            Bytes : Stream_Element_Array (1 .. Text'Length);
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

   function Read_Exact (Path : String) return String is
      package SIO renames Ada.Streams.Stream_IO;
      use type SIO.Count;
      File : SIO.File_Type;
   begin
      SIO.Open (File, SIO.In_File, Path);
      declare
         Byte_Count : constant SIO.Count := SIO.Size (File);
      begin
         if Byte_Count = 0 then
            SIO.Close (File);
            return "";
         end if;

         declare
            Bytes : Stream_Element_Array
              (1 .. Stream_Element_Offset (Byte_Count));
            Last  : Stream_Element_Offset;
            Value : String (1 .. Natural (Byte_Count));
         begin
            SIO.Read (File, Bytes, Last);
            if Last /= Bytes'Last then
               SIO.Close (File);
               raise Program_Error with "short exact test read";
            end if;

            for I in Bytes'Range loop
               Value (Natural (I)) := Character'Val (Bytes (I));
            end loop;
            SIO.Close (File);
            return Value;
         end;
      end;
   end Read_Exact;

   Target : constant String := "/tmp/hra_writer_exact_source.journal";
   Guard  : constant String := "/tmp/hra_writer_guarded_source.txt";

   CRLF_Initial : constant String :=
     "account assets:cash" & ASCII.CR & ASCII.LF &
     "  ; type: Asset" & ASCII.CR & ASCII.LF &
     "account expenses:food" & ASCII.CR & ASCII.LF &
     "  ; type: Expense" & ASCII.CR & ASCII.LF & ASCII.CR & ASCII.LF &
     "2026-08-10 Initial" & ASCII.CR & ASCII.LF &
     "    expenses:food          100 JPY" & ASCII.CR & ASCII.LF &
     "    assets:cash           -100 JPY";

   LF_Initial : constant String :=
     "account assets:cash" & ASCII.LF &
     "  ; type: Asset" & ASCII.LF &
     "account expenses:food" & ASCII.LF &
     "  ; type: Expense" & ASCII.LF & ASCII.LF &
     "2026-08-10 Initial" & ASCII.LF &
     "    expenses:food          100 JPY" & ASCII.LF &
     "    assets:cash           -100 JPY";

   New_Tx : constant String :=
     "2026-08-11 Second" & ASCII.LF &
     "    expenses:food          200 JPY" & ASCII.LF &
     "    assets:cash           -200 JPY" & ASCII.LF;

   Complete_Candidate : constant String := LF_Initial & ASCII.LF;

   Guard_Initial : constant String :=
     "included source" & ASCII.CR & ASCII.LF & "exact bytes";
   Guard_Changed : constant String :=
     "included source" & ASCII.LF & "changed bytes";
   External_Root : constant String := "external root change" & ASCII.LF;

   Observed : Expected_Source;
   Error    : Unbounded_String;
   Status   : Writer_Status;

begin
   Put_Line ("--- Testing Writer exact source premise ---");

   if Exists (Target) then
      Delete_File (Target);
   end if;
   if Exists (Guard) then
      Delete_File (Guard);
   end if;
   if Exists (Target & ".bak") then
      Delete_File (Target & ".bak");
   end if;

   Assert
     (Observe_Source (Target, Observed, Error)
        and then Presence_Of (Observed) = Absent,
      "Absent path is an explicit successful source observation");

   Write_Exact (Target, "");
   Assert
     (Observe_Source (Target, Observed, Error)
        and then Presence_Of (Observed) = Present
        and then Source_Text (Observed) = "",
      "Present zero-byte file remains distinct from Absent");

   Write_Exact (Target, CRLF_Initial);
   Assert
     (Observe_Source (Target, Observed, Error)
        and then Presence_Of (Observed) = Present
        and then Source_Text (Observed) = CRLF_Initial,
      "Source observation preserves CRLF and missing trailing newline exactly");

   declare
      Expected_CRLF : Expected_Source;
   begin
      Assert
        (Observe_Source (Target, Expected_CRLF, Error),
         "Exact CRLF premise can be captured before publication");

      Write_Exact (Target, LF_Initial);
      Assert
        (not Atomic_Publish_Journal
           (Target_Path => Target,
            Expected    => Expected_CRLF,
            Candidate   => Make_Candidate_Source (Complete_Candidate),
            Status      => Status,
            Error_Msg   => Error)
         and then Status = Stale_Source_Rejected,
         "LF-only rewrite is stale against an observed CRLF premise");
   end;

   Write_Exact (Target, CRLF_Initial);
   Assert
     (Append_Transaction_Safely (Target, New_Tx, Status, Error)
        and then Status = Success,
      "Append succeeds from an exact CRLF source premise");
   Assert
     (Read_Exact (Target) = CRLF_Initial & ASCII.LF & New_Tx,
      "Append preserves every existing source byte before the new separator");

   Write_Exact (Target, "");
   declare
      Present_Empty : Expected_Source;

      procedure Delete_Target_After_Stage (Staged_Path : String) is
         pragma Unreferenced (Staged_Path);
      begin
         if Exists (Target) then
            Delete_File (Target);
         end if;
      end Delete_Target_After_Stage;
   begin
      Assert
        (Observe_Source (Target, Present_Empty, Error)
           and then Presence_Of (Present_Empty) = Present,
         "Present-empty premise is captured before second stale fence test");

      HRA.Writer.Test_Hooks.Set_After_Stage_Hook
        (Delete_Target_After_Stage'Address);
      Assert
        (not Atomic_Publish_Journal
           (Target_Path => Target,
            Expected    => Present_Empty,
            Candidate   => Make_Candidate_Source (Complete_Candidate),
            Status      => Status,
            Error_Msg   => Error)
         and then Status = Stale_Source_Rejected,
         "Second stale fence distinguishes deleted file from present-empty premise");
      HRA.Writer.Test_Hooks.Clear_After_Stage_Hook;
      Assert
        (not Exists (Target),
         "Presence stale rejection does not resurrect the deleted target");
   end;

   declare
      Absent_Premise : Expected_Source;

      procedure Create_Target_After_Stage (Staged_Path : String) is
         pragma Unreferenced (Staged_Path);
      begin
         Write_Exact (Target, "");
      end Create_Target_After_Stage;
   begin
      if Exists (Target) then
         Delete_File (Target);
      end if;

      Assert
        (Observe_Source (Target, Absent_Premise, Error)
           and then Presence_Of (Absent_Premise) = Absent,
         "Absent premise is captured before appearance race test");

      HRA.Writer.Test_Hooks.Set_After_Stage_Hook
        (Create_Target_After_Stage'Address);
      Assert
        (not Atomic_Publish_Journal
           (Target_Path => Target,
            Expected    => Absent_Premise,
            Candidate   => Make_Candidate_Source (Complete_Candidate),
            Status      => Status,
            Error_Msg   => Error)
         and then Status = Stale_Source_Rejected,
         "Second stale fence distinguishes newly appeared file from Absent premise");
      HRA.Writer.Test_Hooks.Clear_After_Stage_Hook;
      Assert
        (Exists (Target) and then Read_Exact (Target) = "",
         "Appearance stale rejection leaves the external target untouched");
   end;

   --  Guarded publication succeeds only while an unrelated read-only source
   --  remains byte-for-byte equal to its supplied premise.
   declare
      Target_Expected : Expected_Source;
      Guard_Expected  : Expected_Source;
   begin
      Write_Exact (Target, LF_Initial);
      Write_Exact (Guard, Guard_Initial);
      Assert
        (Observe_Source (Target, Target_Expected, Error)
         and then Observe_Source (Guard, Guard_Expected, Error),
         "Guarded publication captures target and additional source premises");

      declare
         Guards : Source_Premise_Array (1 .. 1) :=
           (1 => Make_Source_Premise (Guard, Guard_Expected));
      begin
         Assert
           (Atomic_Publish_Journal_Guarded
              (Target_Path => Target,
               Expected    => Target_Expected,
               Candidate   => Make_Candidate_Source (Complete_Candidate),
               Guards      => Guards,
               Status      => Status,
               Error_Msg   => Error)
            and then Status = Success,
            "Guarded publication succeeds while every source premise remains exact");
         Assert
           (Read_Exact (Target) = Complete_Candidate
            and then Read_Exact (Guard) = Guard_Initial,
            "Successful guarded publication changes only the target root");
      end;
   end;

   --  A guard change after staging but before root replacement is rejected
   --  without mutating the root.
   declare
      Target_Expected : Expected_Source;
      Guard_Expected  : Expected_Source;

      procedure Change_Guard_After_Stage (Staged_Path : String) is
         pragma Unreferenced (Staged_Path);
      begin
         Write_Exact (Guard, Guard_Changed);
      end Change_Guard_After_Stage;
   begin
      Write_Exact (Target, LF_Initial);
      Write_Exact (Guard, Guard_Initial);
      Assert
        (Observe_Source (Target, Target_Expected, Error)
         and then Observe_Source (Guard, Guard_Expected, Error),
         "Pre-publication guard race captures exact premises");

      declare
         Guards : Source_Premise_Array (1 .. 1) :=
           (1 => Make_Source_Premise (Guard, Guard_Expected));
      begin
         HRA.Writer.Test_Hooks.Set_After_Stage_Hook
           (Change_Guard_After_Stage'Address);
         Assert
           (not Atomic_Publish_Journal_Guarded
              (Target_Path => Target,
               Expected    => Target_Expected,
               Candidate   => Make_Candidate_Source (Complete_Candidate),
               Guards      => Guards,
               Status      => Status,
               Error_Msg   => Error)
            and then Status = Stale_Source_Rejected,
            "Guard change after staging is rejected before root replacement");
         HRA.Writer.Test_Hooks.Clear_After_Stage_Hook;
         Assert
           (Read_Exact (Target) = LF_Initial
            and then Read_Exact (Guard) = Guard_Changed,
            "Pre-publication guard rejection leaves root and external guard ownership intact");
      end;
   end;

   --  A guard change in the narrow window after root replacement is detected by
   --  the post-publication fence and the exact old root is restored.
   declare
      Target_Expected : Expected_Source;
      Guard_Expected  : Expected_Source;

      procedure Change_Guard_After_Publish (Published_Path : String) is
         pragma Unreferenced (Published_Path);
      begin
         Write_Exact (Guard, Guard_Changed);
      end Change_Guard_After_Publish;
   begin
      Write_Exact (Target, LF_Initial);
      Write_Exact (Guard, Guard_Initial);
      Assert
        (Observe_Source (Target, Target_Expected, Error)
         and then Observe_Source (Guard, Guard_Expected, Error),
         "Post-publication guard race captures exact premises");

      declare
         Guards : Source_Premise_Array (1 .. 1) :=
           (1 => Make_Source_Premise (Guard, Guard_Expected));
      begin
         HRA.Writer.Test_Hooks.Set_After_Publish_Hook
           (Change_Guard_After_Publish'Address);
         Assert
           (not Atomic_Publish_Journal_Guarded
              (Target_Path => Target,
               Expected    => Target_Expected,
               Candidate   => Make_Candidate_Source (Complete_Candidate),
               Guards      => Guards,
               Status      => Status,
               Error_Msg   => Error)
            and then Status = Stale_Source_Rejected,
            "Guard change after root replacement is rejected by post-publication fence");
         HRA.Writer.Test_Hooks.Clear_After_Publish_Hook;
         Assert
           (Read_Exact (Target) = LF_Initial
            and then Read_Exact (Guard) = Guard_Changed
            and then not Exists (Target & ".bak"),
            "Post-publication guard rejection restores exact root and never rewrites guard");
      end;
   end;

   --  If somebody also changes the root after Writer's rename, rollback must not
   --  overwrite that later external root change with an older backup.
   declare
      Target_Expected : Expected_Source;
      Guard_Expected  : Expected_Source;

      procedure Change_Guard_And_Root_After_Publish (Published_Path : String) is
      begin
         Write_Exact (Guard, Guard_Changed);
         Write_Exact (Published_Path, External_Root);
      end Change_Guard_And_Root_After_Publish;
   begin
      Write_Exact (Target, LF_Initial);
      Write_Exact (Guard, Guard_Initial);
      Assert
        (Observe_Source (Target, Target_Expected, Error)
         and then Observe_Source (Guard, Guard_Expected, Error),
         "External root race captures exact premises");

      declare
         Guards : Source_Premise_Array (1 .. 1) :=
           (1 => Make_Source_Premise (Guard, Guard_Expected));
      begin
         HRA.Writer.Test_Hooks.Set_After_Publish_Hook
           (Change_Guard_And_Root_After_Publish'Address);
         Assert
           (not Atomic_Publish_Journal_Guarded
              (Target_Path => Target,
               Expected    => Target_Expected,
               Candidate   => Make_Candidate_Source (Complete_Candidate),
               Guards      => Guards,
               Status      => Status,
               Error_Msg   => Error)
            and then Status = File_Write_Failed,
            "Writer refuses rollback when root no longer contains its own candidate");
         HRA.Writer.Test_Hooks.Clear_After_Publish_Hook;
         Assert
           (Read_Exact (Target) = External_Root
            and then Read_Exact (Guard) = Guard_Changed
            and then Exists (Target & ".bak")
            and then Read_Exact (Target & ".bak") = LF_Initial,
            "Rollback refusal preserves external root and retains exact recovery backup");
      end;
   end;

   HRA.Writer.Test_Hooks.Clear_After_Stage_Hook;
   HRA.Writer.Test_Hooks.Clear_After_Publish_Hook;

   if Exists (Target) then
      Delete_File (Target);
   end if;
   if Exists (Guard) then
      Delete_File (Guard);
   end if;
   if Exists (Target & ".bak") then
      Delete_File (Target & ".bak");
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
end Test_Writer_Exact_Source;
