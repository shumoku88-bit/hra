with Ada.Directories;        use Ada.Directories;
with Ada.Streams;            use Ada.Streams;
with Ada.Streams.Stream_IO;
with GNAT.OS_Lib;            use type GNAT.OS_Lib.File_Descriptor;
with HRA.Ledger;             use HRA.Ledger;
with HRA.Journal;            use HRA.Journal;
with HRA.Writer.Test_Hooks;

package body HRA.Writer is

   function Make_Expected_Source (Text : String) return Expected_Source is
     ((State => Present, Text => To_Unbounded_String (Text)));

   function Make_Expected_Source
     (Text : Ada.Strings.Unbounded.Unbounded_String) return Expected_Source is
     ((State => Present, Text => Text));

   function Make_Absent_Expected_Source return Expected_Source is
     ((State => Absent, Text => Null_Unbounded_String));

   function Presence_Of (Value : Expected_Source) return Source_Presence is
     (Value.State);

   function Make_Candidate_Source (Text : String) return Candidate_Source is
     ((Text => To_Unbounded_String (Text)));

   function Make_Candidate_Source
     (Text : Ada.Strings.Unbounded.Unbounded_String) return Candidate_Source is
     ((Text => Text));

   function Source_Text (Value : Expected_Source) return String is
     (To_String (Value.Text));

   function Source_Text (Value : Candidate_Source) return String is
     (To_String (Value.Text));

   function Unbounded_Text
     (Value : Expected_Source) return Ada.Strings.Unbounded.Unbounded_String is
     (Value.Text);

   function Unbounded_Text
     (Value : Candidate_Source) return Ada.Strings.Unbounded.Unbounded_String is
     (Value.Text);

   function Same_Source
     (Left : Expected_Source;
      Right : Expected_Source) return Boolean is
   begin
      if Left.State /= Right.State then
         return False;
      end if;

      if Left.State = Absent then
         return True;
      end if;

      return To_String (Left.Text) = To_String (Right.Text);
   end Same_Source;

   function Observe_Source
     (Target_Path : String;
      Observed    : out Expected_Source;
      Error_Msg   : out Unbounded_String) return Boolean
   is
      package SIO renames Ada.Streams.Stream_IO;
      use type SIO.Count;

      File : SIO.File_Type;
   begin
      if not Exists (Target_Path) then
         Observed := Make_Absent_Expected_Source;
         Error_Msg := Null_Unbounded_String;
         return True;
      end if;

      if Kind (Target_Path) /= Ordinary_File then
         Observed := Make_Absent_Expected_Source;
         Error_Msg := To_Unbounded_String
           ("Target source is not an ordinary file: " & Target_Path);
         return False;
      end if;

      SIO.Open (File, SIO.In_File, Target_Path);
      declare
         Byte_Count : constant SIO.Count := SIO.Size (File);
      begin
         if Byte_Count > SIO.Count (Natural'Last) then
            SIO.Close (File);
            Observed := Make_Absent_Expected_Source;
            Error_Msg := To_Unbounded_String
              ("Target source is too large to observe exactly: " & Target_Path);
            return False;
         elsif Byte_Count = 0 then
            SIO.Close (File);
            Observed := Make_Expected_Source ("");
            Error_Msg := Null_Unbounded_String;
            return True;
         else
            declare
               Bytes : Stream_Element_Array
                 (1 .. Stream_Element_Offset (Byte_Count));
               Last  : Stream_Element_Offset;
               Value : String (1 .. Natural (Byte_Count));
            begin
               SIO.Read (File, Bytes, Last);
               if Last /= Bytes'Last then
                  SIO.Close (File);
                  Observed := Make_Absent_Expected_Source;
                  Error_Msg := To_Unbounded_String
                    ("Short read while observing target source: " & Target_Path);
                  return False;
               end if;

               for I in Bytes'Range loop
                  Value (Natural (I)) := Character'Val (Bytes (I));
               end loop;

               SIO.Close (File);
               Observed := Make_Expected_Source (Value);
               Error_Msg := Null_Unbounded_String;
               return True;
            end;
         end if;
      end;
   exception
      when others =>
         if SIO.Is_Open (File) then
            SIO.Close (File);
         end if;
         Observed := Make_Absent_Expected_Source;
         Error_Msg := To_Unbounded_String
           ("Failed to observe target source bytes: " & Target_Path);
         return False;
   end Observe_Source;

   function Write_File_Exact (Path : String; Content : String) return Boolean is
      package SIO renames Ada.Streams.Stream_IO;
      File : SIO.File_Type;
   begin
      SIO.Create (File, SIO.Out_File, Path);
      if Content'Length > 0 then
         declare
            Bytes : Stream_Element_Array
              (1 .. Stream_Element_Offset (Content'Length));
         begin
            for I in Content'Range loop
               Bytes (Stream_Element_Offset (I - Content'First + 1)) :=
                 Stream_Element (Character'Pos (Content (I)));
            end loop;
            SIO.Write (File, Bytes);
         end;
      end if;
      SIO.Close (File);
      return True;
   exception
      when others =>
         if SIO.Is_Open (File) then
            SIO.Close (File);
         end if;
         return False;
   end Write_File_Exact;

   function Writer_Status_Image (Status : Writer_Status) return String is
   begin
      case Status is
         when Success               => return "Success";
         when Stale_Source_Rejected => return "Stale_Source_Rejected";
         when Pre_Admission_Failed  => return "Pre_Admission_Failed";
         when Backup_Failed         => return "Backup_Failed";
         when File_Write_Failed     => return "File_Write_Failed";
         when Post_Admission_Failed => return "Post_Admission_Failed";
      end case;
   end Writer_Status_Image;

   function Format_Natural (N : Natural) return String is
      Img : constant String := Natural'Image (N);
   begin
      if Img'Length > 0 and then Img (Img'First) = ' ' then
         return Img (Img'First + 1 .. Img'Last);
      else
         return Img;
      end if;
   end Format_Natural;

   function Format_Integer (N : Integer) return String is
      Img : constant String := Integer'Image (N);
   begin
      if Img'Length > 0 and then Img (Img'First) = ' ' then
         return Img (Img'First + 1 .. Img'Last);
      else
         return Img;
      end if;
   end Format_Integer;

   function Stage_Candidate_File
     (Target_Path    : String;
      Candidate_Text : String;
      Staged_Path    : out Ada.Strings.Unbounded.Unbounded_String) return Boolean
   is
      Pid_Val      : constant Integer :=
        GNAT.OS_Lib.Pid_To_Integer (GNAT.OS_Lib.Current_Process_Id);
      Pid_Str      : constant String :=
        (if Pid_Val >= 0 then Format_Integer (Pid_Val) else "0");
      Max_Attempts : constant := 100;
   begin
      for Attempt in 1 .. Max_Attempts loop
         declare
            Trial_Path : constant String :=
              Target_Path & ".candidate." & Pid_Str & "_" &
              Format_Natural (Attempt) & ".tmp";
            FD         : constant GNAT.OS_Lib.File_Descriptor :=
              GNAT.OS_Lib.Create_New_File (Trial_Path, GNAT.OS_Lib.Binary);
         begin
            if FD /= GNAT.OS_Lib.Invalid_FD then
               if Candidate_Text'Length > 0 then
                  declare
                     Written      : constant Integer :=
                       GNAT.OS_Lib.Write
                         (FD,
                          Candidate_Text (Candidate_Text'First)'Address,
                          Candidate_Text'Length);
                     Close_Status : Boolean;
                  begin
                     GNAT.OS_Lib.Close (FD, Close_Status);
                     if Written /= Candidate_Text'Length or else not Close_Status then
                        if Exists (Trial_Path) then
                           Delete_File (Trial_Path);
                        end if;
                        return False;
                     end if;
                  end;
               else
                  declare
                     Close_Status : Boolean;
                  begin
                     GNAT.OS_Lib.Close (FD, Close_Status);
                     if not Close_Status then
                        if Exists (Trial_Path) then
                           Delete_File (Trial_Path);
                        end if;
                        return False;
                     end if;
                  end;
               end if;

               Staged_Path := To_Unbounded_String (Trial_Path);
               return True;
            end if;
         end;
      end loop;

      Staged_Path := Null_Unbounded_String;
      return False;
   exception
      when others =>
         Staged_Path := Null_Unbounded_String;
         return False;
   end Stage_Candidate_File;

   function Atomic_Publish_Journal
     (Target_Path : String;
      Expected    : Expected_Source;
      Candidate   : Candidate_Source;
      Status      : out Writer_Status;
      Error_Msg   : out Unbounded_String) return Boolean
   is
      Initial_On_Disk  : Expected_Source;
      Second_On_Disk   : Expected_Source;
      Read_Error       : Unbounded_String;
      Staged_Path      : Unbounded_String := Null_Unbounded_String;
      Bak_Path         : constant String := Target_Path & ".bak";
      Dummy_L          : Ledger.Ledger;
      Parse_Err        : Unbounded_String;
      Expected_Text    : constant String := Source_Text (Expected);
      Candidate_Text   : constant String := Source_Text (Candidate);
   begin
      --  1. Initial stale check: compare exact filesystem presence and bytes
      --  before any mutation or staging.
      if not Observe_Source (Target_Path, Initial_On_Disk, Read_Error) then
         Status := File_Write_Failed;
         Error_Msg := To_Unbounded_String
           ("Failed to observe target for initial stale check: " &
            To_String (Read_Error));
         return False;
      end if;

      if not Same_Source (Initial_On_Disk, Expected) then
         Status := Stale_Source_Rejected;
         Error_Msg := To_Unbounded_String
           ("Stale source rejected: file presence or exact bytes changed on disk");
         return False;
      end if;

      --  2. Pre-admission validation, before any candidate staging or filesystem mutation.
      if not Parse_Journal_Text (Candidate_Text, Dummy_L, Parse_Err) then
         Status := Pre_Admission_Failed;
         Error_Msg := To_Unbounded_String ("Pre-admission validation rejected candidate: " & To_String (Parse_Err));
         return False;
      end if;

      --  3. Unique Candidate Staging: write Candidate to unique sibling staging file.
      if not Stage_Candidate_File (Target_Path, Candidate_Text, Staged_Path) then
         Status := File_Write_Failed;
         Error_Msg := To_Unbounded_String ("Failed to stage candidate to unique temporary file");
         return False;
      end if;

      --  4. Optional test / inspection hook immediately after candidate staging.
      HRA.Writer.Test_Hooks.Notify_Staged (To_String (Staged_Path));

      --  5. Second stale fence: re-observe target right before publication.
      if not Observe_Source (Target_Path, Second_On_Disk, Read_Error) then
         if Exists (To_String (Staged_Path)) then
            Delete_File (To_String (Staged_Path));
         end if;
         Status := File_Write_Failed;
         Error_Msg := To_Unbounded_String
           ("Failed to observe target for second stale fence: " &
            To_String (Read_Error));
         return False;
      end if;

      if not Same_Source (Second_On_Disk, Expected) then
         if Exists (To_String (Staged_Path)) then
            Delete_File (To_String (Staged_Path));
         end if;
         Status := Stale_Source_Rejected;
         Error_Msg := To_Unbounded_String
           ("Stale source rejected: target presence or exact bytes changed during publication preparation");
         return False;
      end if;

      --  6. Keep an exact recovery copy until post-admission validation succeeds.
      if Expected.State = Present
        and then not Write_File_Exact (Bak_Path, Expected_Text)
      then
         if Exists (To_String (Staged_Path)) then
            Delete_File (To_String (Staged_Path));
         end if;
         Status := Backup_Failed;
         Error_Msg := To_Unbounded_String ("Failed to create backup file: " & Bak_Path);
         return False;
      end if;

      --  7. Atomically replace the target where the host rename semantics
      --  support replacement. Unlike delete-then-rename, a failure leaves
      --  the original target in place.
      declare
         Renamed : Boolean;
      begin
         GNAT.OS_Lib.Rename_File (To_String (Staged_Path), Target_Path, Renamed);
         if not Renamed then
            Status := File_Write_Failed;
            Error_Msg := To_Unbounded_String ("Failed atomic rename from " & To_String (Staged_Path) & " to " & Target_Path);
            if Exists (To_String (Staged_Path)) then
               Delete_File (To_String (Staged_Path));
            end if;
            if Expected.State = Present and then Exists (Bak_Path) then
               Delete_File (Bak_Path);
            end if;
            return False;
         end if;
      end;

      --  8. Post-Admission Validation (Intentional legacy preserved for 2A)
      declare
         Parsed_L : Ledger.Ledger;
      begin
         if not Parse_Journal_Text (Candidate_Text, Parsed_L, Parse_Err) then
            if Expected.State = Present and then Exists (Bak_Path) then
               if Exists (Target_Path) then
                  Delete_File (Target_Path);
               end if;
               Rename (Bak_Path, Target_Path);
            elsif Expected.State = Absent and then Exists (Target_Path) then
               --  The exact pre-publication premise was absence, so rollback
               --  restores absence rather than inventing an empty file.
               Delete_File (Target_Path);
            end if;

            Status := Post_Admission_Failed;
            Error_Msg := To_Unbounded_String ("Post-admission validation failed (source premise restored): " & To_String (Parse_Err));
            return False;
         end if;
      end;

      --  9. Success: Clean up temporary backup & staging files if present
      if Exists (To_String (Staged_Path)) then
         Delete_File (To_String (Staged_Path));
      end if;
      if Expected.State = Present and then Exists (Bak_Path) then
         Delete_File (Bak_Path);
      end if;

      Status := Success;
      Error_Msg := Null_Unbounded_String;
      return True;
   end Atomic_Publish_Journal;

   function Append_Transaction_Safely
     (Target_Path : String;
      New_Tx_Text : String;
      Status      : out Writer_Status;
      Error_Msg   : out Unbounded_String) return Boolean
   is
      Observed_Source : Expected_Source;
      Observe_Error   : Unbounded_String;
      Old_Content     : Unbounded_String;
      New_Content     : Unbounded_String;
   begin
      if not Observe_Source (Target_Path, Observed_Source, Observe_Error) then
         Status := File_Write_Failed;
         Error_Msg := To_Unbounded_String
           ("Failed to observe target file: " & To_String (Observe_Error));
         return False;
      end if;

      if Presence_Of (Observed_Source) = Present then
         Old_Content := Unbounded_Text (Observed_Source);
      else
         Old_Content := Null_Unbounded_String;
      end if;

      New_Content := Old_Content;
      if Length (New_Content) > 0 and then Element (New_Content, Length (New_Content)) /= ASCII.LF then
         Append (New_Content, ASCII.LF);
      end if;
      Append (New_Content, New_Tx_Text);
      if New_Tx_Text'Length > 0 and then New_Tx_Text (New_Tx_Text'Last) /= ASCII.LF then
         Append (New_Content, ASCII.LF);
      end if;

      return Atomic_Publish_Journal
        (Target_Path => Target_Path,
         Expected    => Observed_Source,
         Candidate   => Make_Candidate_Source (New_Content),
         Status      => Status,
         Error_Msg   => Error_Msg);
   end Append_Transaction_Safely;

end HRA.Writer;
