with Ada.Text_IO;          use Ada.Text_IO;
with Ada.Directories;        use Ada.Directories;
with GNAT.OS_Lib;            use type GNAT.OS_Lib.File_Descriptor;
with HRA.Ledger;             use HRA.Ledger;
with HRA.Journal;            use HRA.Journal;

package body HRA.Writer is

   function Make_Expected_Source (Text : String) return Expected_Source is
     ((Text => To_Unbounded_String (Text)));

   function Make_Expected_Source
     (Text : Ada.Strings.Unbounded.Unbounded_String) return Expected_Source is
     ((Text => Text));

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

   function Read_File (Path : String; Content : out Unbounded_String) return Boolean is
      F : File_Type;
   begin
      if not Exists (Path) then
         Content := Null_Unbounded_String;
         return True;
      end if;

      Open (F, In_File, Path);
      Content := Null_Unbounded_String;
      while not End_Of_File (F) loop
         Append (Content, Get_Line (F));
         Append (Content, ASCII.LF);
      end loop;
      Close (F);
      return True;
   exception
      when others =>
         Content := Null_Unbounded_String;
         return False;
   end Read_File;

   function Write_File (Path : String; Content : String) return Boolean is
      F : File_Type;
   begin
      Create (F, Out_File, Path);
      Put (F, Content);
      Close (F);
      return True;
   exception
      when others =>
         return False;
   end Write_File;

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

   Global_Stage_Sequence : Natural := 0;

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
         Global_Stage_Sequence := Global_Stage_Sequence + 1;
         declare
            Trial_Path : constant String :=
              Target_Path & ".candidate." & Pid_Str & "_" &
              Format_Natural (Global_Stage_Sequence) & ".tmp";
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
     (Target_Path      : String;
      Expected         : Expected_Source;
      Candidate        : Candidate_Source;
      Status           : out Writer_Status;
      Error_Msg        : out Unbounded_String;
      After_Stage_Hook : access procedure (Staged_Path : String) := null) return Boolean
    is
      Initial_On_Disk  : Unbounded_String;
      Second_On_Disk   : Unbounded_String;
      Staged_Path      : Unbounded_String := Null_Unbounded_String;
      Bak_Path         : constant String := Target_Path & ".bak";
      Dummy_L          : Ledger.Ledger;
      Parse_Err        : Unbounded_String;
      Expected_Text    : constant String := Source_Text (Expected);
      Candidate_Text   : constant String := Source_Text (Candidate);
   begin
      --  1. Initial Stale Check: read current bytes before mutation or staging
      --  to reject stale premise early.
      if not Read_File (Target_Path, Initial_On_Disk) then
         Status := File_Write_Failed;
         Error_Msg := To_Unbounded_String ("Failed to read target file for initial stale check");
         return False;
      end if;

      if To_String (Initial_On_Disk) /= Expected_Text then
         Status := Stale_Source_Rejected;
         Error_Msg := To_Unbounded_String ("Stale source rejected: file changed on disk by another process");
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
      if After_Stage_Hook /= null then
         After_Stage_Hook.all (To_String (Staged_Path));
      end if;

      --  5. Second Stale Fence: re-observe target right before publication to detect
      --  any modification occurring while staging was prepared.
      if not Read_File (Target_Path, Second_On_Disk) then
         if Exists (To_String (Staged_Path)) then
            Delete_File (To_String (Staged_Path));
         end if;
         Status := File_Write_Failed;
         Error_Msg := To_Unbounded_String ("Failed to read target file for second stale fence");
         return False;
      end if;

      if To_String (Second_On_Disk) /= Expected_Text then
         --  Second stale fence detected mismatch: cleanup staging only,
         --  leave target untouched without modifying or restoring.
         if Exists (To_String (Staged_Path)) then
            Delete_File (To_String (Staged_Path));
         end if;
         Status := Stale_Source_Rejected;
         Error_Msg := To_Unbounded_String ("Stale source rejected: target modified on disk during publication preparation");
         return False;
      end if;

      --  6. Keep a recovery copy until post-admission validation succeeds.
      if Exists (Target_Path) and then not Write_File (Bak_Path, Expected_Text) then
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
            if Exists (Bak_Path) then
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
            --  Post-admission failure: Restore from backup
            if Exists (Bak_Path) then
               if Exists (Target_Path) then
                  Delete_File (Target_Path);
               end if;
               Rename (Bak_Path, Target_Path);
            end if;

            Status := Post_Admission_Failed;
            Error_Msg := To_Unbounded_String ("Post-admission validation failed (file restored from backup): " & To_String (Parse_Err));
            return False;
         end if;
      end;

      --  9. Success: Clean up temporary backup & staging files if present
      if Exists (To_String (Staged_Path)) then
         Delete_File (To_String (Staged_Path));
      end if;
      if Exists (Bak_Path) then
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
      Old_Content : Unbounded_String;
      New_Content : Unbounded_String;
   begin
      if Exists (Target_Path) then
         if not Read_File (Target_Path, Old_Content) then
            Status := File_Write_Failed;
            Error_Msg := To_Unbounded_String ("Failed to read target file");
            return False;
         end if;
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
         Expected    => Make_Expected_Source (Old_Content),
         Candidate   => Make_Candidate_Source (New_Content),
         Status      => Status,
         Error_Msg   => Error_Msg);
   end Append_Transaction_Safely;

end HRA.Writer;
