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

   Observed : Expected_Source;
   Error    : Unbounded_String;
   Status   : Writer_Status;

begin
   Put_Line ("--- Testing Writer exact source premise ---");

   if Exists (Target) then
      Delete_File (Target);
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

   if Exists (Target) then
      Delete_File (Target);
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
