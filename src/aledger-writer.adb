with Ada.Text_IO;          use Ada.Text_IO;
with Ada.Directories;        use Ada.Directories;
with GNAT.OS_Lib;
with ALedger.Ledger;         use ALedger.Ledger;
with ALedger.Journal;        use ALedger.Journal;

package body ALedger.Writer is

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

   function Atomic_Publish_Journal
     (Target_Path       : String;
      Expected_Old_Text : String;
      New_Text          : String;
      Status            : out Writer_Status;
      Error_Msg         : out Unbounded_String) return Boolean
   is
      Current_On_Disk : Unbounded_String;
      Tmp_Path        : constant String := Target_Path & ".tmp";
      Bak_Path        : constant String := Target_Path & ".bak";
      Dummy_L         : Ledger.Ledger;
      Parse_Err       : Unbounded_String;
   begin
      --  1. Stale Check: read current bytes before doing any mutation.
      if Exists (Target_Path) then
         if not Read_File (Target_Path, Current_On_Disk) then
            Status := File_Write_Failed;
            Error_Msg := To_Unbounded_String ("Failed to read target file for stale check");
            return False;
         end if;

         if To_String (Current_On_Disk) /= Expected_Old_Text then
            Status := Stale_Source_Rejected;
            Error_Msg := To_Unbounded_String ("Stale source rejected: file changed on disk by another process");
            return False;
         end if;

      end if;

      --  2. Pre-admission validation, still before any filesystem mutation.
      if not Parse_Journal_Text (New_Text, Dummy_L, Parse_Err) then
         Status := Pre_Admission_Failed;
         Error_Msg := To_Unbounded_String ("Pre-admission validation rejected candidate: " & To_String (Parse_Err));
         return False;
      end if;

      --  3. Keep a recovery copy until post-admission validation succeeds.
      if Exists (Target_Path) and then not Write_File (Bak_Path, Expected_Old_Text) then
         Status := Backup_Failed;
         Error_Msg := To_Unbounded_String ("Failed to create backup file: " & Bak_Path);
         return False;
      end if;

      --  4. Write Candidate to Sibling Temporary File
      if not Write_File (Tmp_Path, New_Text) then
         Status := File_Write_Failed;
         Error_Msg := To_Unbounded_String ("Failed to write candidate to temporary file: " & Tmp_Path);
         if Exists (Bak_Path) then
            Delete_File (Bak_Path);
         end if;
         return False;
      end if;

      --  5. Atomically replace the target where the host rename semantics
      --  support replacement.  Unlike delete-then-rename, a failure leaves
      --  the original target in place.
      declare
         Renamed : Boolean;
      begin
         GNAT.OS_Lib.Rename_File (Tmp_Path, Target_Path, Renamed);
         if not Renamed then
            Status := File_Write_Failed;
            Error_Msg := To_Unbounded_String ("Failed atomic rename from " & Tmp_Path & " to " & Target_Path);
            if Exists (Tmp_Path) then
               Delete_File (Tmp_Path);
            end if;
            if Exists (Bak_Path) then
               Delete_File (Bak_Path);
            end if;
            return False;
         end if;
      end;

      --  6. Post-Admission Validation
      declare
         Parsed_L : Ledger.Ledger;
      begin
         if not Parse_Journal_Text (New_Text, Parsed_L, Parse_Err) then
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

      --  Success: Clean up temporary backup & temp files if present
      if Exists (Tmp_Path) then
         Delete_File (Tmp_Path);
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
        (Target_Path       => Target_Path,
         Expected_Old_Text => To_String (Old_Content),
         New_Text          => To_String (New_Content),
         Status            => Status,
         Error_Msg         => Error_Msg);
   end Append_Transaction_Safely;

end ALedger.Writer;
