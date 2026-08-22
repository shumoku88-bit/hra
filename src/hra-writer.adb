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

   function Make_Source_Premise
     (Path     : String;
      Expected : Expected_Source) return Source_Premise is
     ((Path     => To_Unbounded_String (Path),
       Expected => Expected));

   function Same_Source
     (Left  : Expected_Source;
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

   type Premise_Check_Result is
     (Premises_Match,
      Premise_Stale,
      Premise_Read_Failed);

   function Check_Source_Premises
     (Premises : Source_Premise_Array;
      Error_Msg : out Unbounded_String) return Premise_Check_Result
   is
      On_Disk    : Expected_Source;
      Read_Error : Unbounded_String;
   begin
      Error_Msg := Null_Unbounded_String;
      for Premise of Premises loop
         declare
            Path : constant String := To_String (Premise.Path);
         begin
            if not Observe_Source (Path, On_Disk, Read_Error) then
               Error_Msg := To_Unbounded_String
                 ("Failed to observe guarded source: " & Path & ": " &
                  To_String (Read_Error));
               return Premise_Read_Failed;
            end if;

            if not Same_Source (On_Disk, Premise.Expected) then
               Error_Msg := To_Unbounded_String
                 ("Guarded source presence or exact bytes changed: " & Path);
               return Premise_Stale;
            end if;
         end;
      end loop;
      return Premises_Match;
   end Check_Source_Premises;

   function Restore_Target_If_Own_Candidate
     (Target_Path    : String;
      Expected       : Expected_Source;
      Candidate_Text : String;
      Backup_Path    : String;
      Error_Msg      : out Unbounded_String) return Boolean
   is
      Current    : Expected_Source;
      Read_Error : Unbounded_String;
      Candidate_Expected : constant Expected_Source :=
        Make_Expected_Source (Candidate_Text);
   begin
      Error_Msg := Null_Unbounded_String;

      if not Observe_Source (Target_Path, Current, Read_Error) then
         Error_Msg := To_Unbounded_String
           ("cannot observe target before rollback: " & To_String (Read_Error));
         return False;
      end if;

      if not Same_Source (Current, Candidate_Expected) then
         Error_Msg := To_Unbounded_String
           ("target no longer contains Writer candidate; refusing to overwrite external change");
         return False;
      end if;

      if Expected.State = Present then
         if not Exists (Backup_Path) then
            Error_Msg := To_Unbounded_String
              ("exact rollback backup is missing: " & Backup_Path);
            return False;
         end if;

         declare
            Renamed : Boolean;
         begin
            GNAT.OS_Lib.Rename_File (Backup_Path, Target_Path, Renamed);
            if not Renamed then
               Error_Msg := To_Unbounded_String
                 ("failed to restore exact rollback backup: " & Backup_Path);
               return False;
            end if;
         end;
      elsif Exists (Target_Path) then
         Delete_File (Target_Path);
      end if;

      return True;
   exception
      when others =>
         Error_Msg := To_Unbounded_String
           ("exception while restoring exact target premise");
         return False;
   end Restore_Target_If_Own_Candidate;

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
      Empty_Guards : Source_Premise_Array (1 .. 0);
   begin
      return Atomic_Publish_Journal_Guarded
        (Target_Path => Target_Path,
         Expected    => Expected,
         Candidate   => Candidate,
         Guards      => Empty_Guards,
         Status      => Status,
         Error_Msg   => Error_Msg);
   end Atomic_Publish_Journal;

   generic
      with function Admit_Candidate
        (Candidate_Text : String;
         Error_Msg      : out Unbounded_String) return Boolean;
      Admission_Failure_Status    : Writer_Status;
      Admission_Failure_Prefix    : String;
      with function Confirm_Candidate
        (Candidate_Text : String;
         Error_Msg      : out Unbounded_String) return Boolean;
      Confirmation_Failure_Status : Writer_Status;
      Confirmation_Failure_Prefix : String;
   function Atomic_Replace_Exact_Guarded_Core
     (Target_Path : String;
      Expected    : Expected_Source;
      Candidate   : Candidate_Source;
      Guards      : Source_Premise_Array;
      Status      : out Writer_Status;
      Error_Msg   : out Unbounded_String) return Boolean;

   function Atomic_Replace_Exact_Guarded_Core
     (Target_Path : String;
      Expected    : Expected_Source;
      Candidate   : Candidate_Source;
      Guards      : Source_Premise_Array;
      Status      : out Writer_Status;
      Error_Msg   : out Unbounded_String) return Boolean
   is
      Initial_On_Disk  : Expected_Source;
      Second_On_Disk   : Expected_Source;
      Read_Error       : Unbounded_String;
      Guard_Error      : Unbounded_String;
      Rollback_Error   : Unbounded_String;
      Staged_Path      : Unbounded_String := Null_Unbounded_String;
      Bak_Path         : constant String := Target_Path & ".bak";
      Admission_Err    : Unbounded_String;
      Confirmation_Err : Unbounded_String;
      Expected_Text    : constant String := Source_Text (Expected);
      Candidate_Text   : constant String := Source_Text (Candidate);

      procedure Clean_Staged is
      begin
         if Length (Staged_Path) > 0 and then Exists (To_String (Staged_Path)) then
            Delete_File (To_String (Staged_Path));
         end if;
      end Clean_Staged;

      function Check_Guards_Before_Mutation
        (Phase : String) return Boolean
      is
         Check : constant Premise_Check_Result :=
           Check_Source_Premises (Guards, Guard_Error);
      begin
         case Check is
            when Premises_Match =>
               return True;
            when Premise_Stale =>
               Clean_Staged;
               Status := Stale_Source_Rejected;
               Error_Msg := To_Unbounded_String
                 ("Stale guarded source rejected during " & Phase & ": " &
                  To_String (Guard_Error));
               return False;
            when Premise_Read_Failed =>
               Clean_Staged;
               Status := File_Write_Failed;
               Error_Msg := To_Unbounded_String
                 ("Guarded source observation failed during " & Phase & ": " &
                  To_String (Guard_Error));
               return False;
         end case;
      end Check_Guards_Before_Mutation;

   begin
      --  1. Initial stale check: compare exact target presence and bytes before
      --  any mutation or staging.
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

      --  2. Guard premises are also checked before staging so already-stale
      --  read-only sources fail without creating any candidate file.
      if not Check_Guards_Before_Mutation ("initial guard fence") then
         return False;
      end if;

      --  3. Run the caller-selected admission before staging. The exact-byte
      --  API supplies an unconditional admission; semantic wrappers can supply
      --  their domain admission without making the mechanism its owner.
      if not Admit_Candidate (Candidate_Text, Admission_Err) then
         Status := Admission_Failure_Status;
         Error_Msg := To_Unbounded_String
           (Admission_Failure_Prefix & ": " & To_String (Admission_Err));
         return False;
      end if;

      --  4. Unique candidate staging.
      if not Stage_Candidate_File (Target_Path, Candidate_Text, Staged_Path) then
         Status := File_Write_Failed;
         Error_Msg := To_Unbounded_String
           ("Failed to stage candidate to unique temporary file");
         return False;
      end if;

      --  5. Optional test / inspection hook immediately after candidate staging.
      HRA.Writer.Test_Hooks.Notify_Staged (To_String (Staged_Path));

      --  6. Second target stale fence right before publication.
      if not Observe_Source (Target_Path, Second_On_Disk, Read_Error) then
         Clean_Staged;
         Status := File_Write_Failed;
         Error_Msg := To_Unbounded_String
           ("Failed to observe target for second stale fence: " &
            To_String (Read_Error));
         return False;
      end if;

      if not Same_Source (Second_On_Disk, Expected) then
         Clean_Staged;
         Status := Stale_Source_Rejected;
         Error_Msg := To_Unbounded_String
           ("Stale source rejected: target presence or exact bytes changed during publication preparation");
         return False;
      end if;

      --  7. Guard premises get their own second fence after staging and as near
      --  as possible to the target replacement. A change here leaves target
      --  untouched.
      if not Check_Guards_Before_Mutation ("pre-publication guard fence") then
         return False;
      end if;

      --  8. Keep an exact target recovery copy until all post-publication
      --  checks succeed.
      if Expected.State = Present
        and then not Write_File_Exact (Bak_Path, Expected_Text)
      then
         Clean_Staged;
         Status := Backup_Failed;
         Error_Msg := To_Unbounded_String
           ("Failed to create backup file: " & Bak_Path);
         return False;
      end if;

      --  9. Atomically replace only the target root.
      declare
         Renamed : Boolean;
      begin
         GNAT.OS_Lib.Rename_File (To_String (Staged_Path), Target_Path, Renamed);
         if not Renamed then
            Status := File_Write_Failed;
            Error_Msg := To_Unbounded_String
              ("Failed atomic rename from " & To_String (Staged_Path) &
               " to " & Target_Path);
            Clean_Staged;
            if Expected.State = Present and then Exists (Bak_Path) then
               Delete_File (Bak_Path);
            end if;
            return False;
         end if;
      end;

      --  10. Test-only race point after root replacement and before the guarded
      --  source post-publication fence.
      HRA.Writer.Test_Hooks.Notify_Published (Target_Path);

      --  11. Recheck every read-only source immediately after replacement. If a
      --  guard changed across the commit window, restore the root only when it
      --  still contains Writer's own candidate. Never overwrite a later
      --  external root change with the old backup.
      declare
         Check : constant Premise_Check_Result :=
           Check_Source_Premises (Guards, Guard_Error);
      begin
         if Check /= Premises_Match then
            if Restore_Target_If_Own_Candidate
              (Target_Path,
               Expected,
               Candidate_Text,
               Bak_Path,
               Rollback_Error)
            then
               Status :=
                 (if Check = Premise_Stale
                  then Stale_Source_Rejected
                  else File_Write_Failed);
               Error_Msg := To_Unbounded_String
                 ((if Check = Premise_Stale
                   then "Guarded source changed across publication; exact target premise restored: "
                   else "Guarded source became unreadable across publication; exact target premise restored: ") &
                  To_String (Guard_Error));
            else
               Status := File_Write_Failed;
               Error_Msg := To_Unbounded_String
                 ("Guarded source fence failed after root publication and safe rollback was refused or failed: " &
                  To_String (Guard_Error) & "; " & To_String (Rollback_Error));
            end if;
            return False;
         end if;
      end;

      --  11. The caller-selected compatibility confirmation runs while the
      --  exact backup is still available. A semantic wrapper can therefore
      --  preserve the same safe rollback law without putting semantics in the
      --  exact replacement mechanism.
      if not Confirm_Candidate (Candidate_Text, Confirmation_Err) then
         if Restore_Target_If_Own_Candidate
           (Target_Path,
            Expected,
            Candidate_Text,
            Bak_Path,
            Rollback_Error)
         then
            Status := Confirmation_Failure_Status;
            Error_Msg := To_Unbounded_String
              (Confirmation_Failure_Prefix &
               "; exact target premise restored: " &
               To_String (Confirmation_Err));
         else
            Status := File_Write_Failed;
            Error_Msg := To_Unbounded_String
              (Confirmation_Failure_Prefix &
               " and safe rollback was refused or failed: " &
               To_String (Confirmation_Err) & "; " &
               To_String (Rollback_Error));
         end if;
         return False;
      end if;

      --  12. Success: remove any remaining backup/staging files.
      Clean_Staged;
      if Expected.State = Present and then Exists (Bak_Path) then
         Delete_File (Bak_Path);
      end if;

      Status := Success;
      Error_Msg := Null_Unbounded_String;
      return True;
   end Atomic_Replace_Exact_Guarded_Core;

   function Accept_Exact_Bytes
     (Candidate_Text : String;
      Error_Msg      : out Unbounded_String) return Boolean
   is
      pragma Unreferenced (Candidate_Text);
   begin
      Error_Msg := Null_Unbounded_String;
      return True;
   end Accept_Exact_Bytes;

   function Replace_Exact_Core is new Atomic_Replace_Exact_Guarded_Core
     (Admit_Candidate               => Accept_Exact_Bytes,
      Admission_Failure_Status     => File_Write_Failed,
      Admission_Failure_Prefix     => "Exact byte admission failed",
      Confirm_Candidate            => Accept_Exact_Bytes,
      Confirmation_Failure_Status => File_Write_Failed,
      Confirmation_Failure_Prefix => "Exact byte confirmation failed");

   function Atomic_Replace_Exact_Guarded
     (Target_Path : String;
      Expected    : Expected_Source;
      Candidate   : Candidate_Source;
      Guards      : Source_Premise_Array;
      Status      : out Writer_Status;
      Error_Msg   : out Unbounded_String) return Boolean
   is
   begin
      return Replace_Exact_Core
        (Target_Path => Target_Path,
         Expected    => Expected,
         Candidate   => Candidate,
         Guards      => Guards,
         Status      => Status,
         Error_Msg   => Error_Msg);
   end Atomic_Replace_Exact_Guarded;

   function Confirm_Journal
     (Candidate_Text : String;
      Error_Msg      : out Unbounded_String) return Boolean
   is
      Parsed : Ledger.Ledger;
   begin
      return Parse_Journal_Text (Candidate_Text, Parsed, Error_Msg);
   end Confirm_Journal;

   function Replace_Journal_Core is new Atomic_Replace_Exact_Guarded_Core
     (Admit_Candidate               => Confirm_Journal,
      Admission_Failure_Status     => Pre_Admission_Failed,
      Admission_Failure_Prefix     => "Pre-admission validation rejected candidate",
      Confirm_Candidate            => Confirm_Journal,
      Confirmation_Failure_Status => Post_Admission_Failed,
      Confirmation_Failure_Prefix => "Post-admission validation failed");

   function Atomic_Publish_Journal_Guarded
     (Target_Path : String;
      Expected    : Expected_Source;
      Candidate   : Candidate_Source;
      Guards      : Source_Premise_Array;
      Status      : out Writer_Status;
      Error_Msg   : out Unbounded_String) return Boolean
   is
   begin
      --  Journal admission is selected by this semantic wrapper, not owned by
      --  exact replacement. The generic mechanism runs it after initial stale
      --  fences and repeats it after rename while rollback remains available.
      return Replace_Journal_Core
        (Target_Path => Target_Path,
         Expected    => Expected,
         Candidate   => Candidate,
         Guards      => Guards,
         Status      => Status,
         Error_Msg   => Error_Msg);
   end Atomic_Publish_Journal_Guarded;

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
      if Length (New_Content) > 0
        and then Element (New_Content, Length (New_Content)) /= ASCII.LF
      then
         Append (New_Content, ASCII.LF);
      end if;
      Append (New_Content, New_Tx_Text);
      if New_Tx_Text'Length > 0
        and then New_Tx_Text (New_Tx_Text'Last) /= ASCII.LF
      then
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
