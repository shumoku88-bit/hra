with Ada.Command_Line;
with Ada.Directories; use Ada.Directories;
with Ada.Streams; use Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO; use Ada.Text_IO;
with HRA.Writer; use HRA.Writer;
with HRA.Writer.Test_Hooks;

procedure Test_Writer_Exact_Replacement is
   Target : constant String := "/tmp/hra_writer_exact_replacement.tsv";
   Guard  : constant String := "/tmp/hra_writer_exact_replacement.guard";
   Old_Bytes       : constant String := "old" & ASCII.CR & ASCII.LF;
   TSV_Bytes       : constant String := "issue-7" & ASCII.HT & "closed" & ASCII.LF;
   Guard_Bytes     : constant String := "guard premise";
   Changed_Guard   : constant String := "changed guard";
   External_Bytes  : constant String := "later external bytes";

   Passed : Natural := 0;
   Failed : Natural := 0;
   Status : Writer_Status;
   Error  : Unbounded_String;
   Staged   : Unbounded_String;
   Recovery : Unbounded_String;
   Hook_Called : Boolean := False;

   Recovery_Marker : constant String := "recovery backup preserved at: ";

   procedure Assert (Condition : Boolean; Name : String) is
   begin
      if Condition then
         Put_Line ("[PASS] " & Name);
         Passed := Passed + 1;
      else
         Put_Line ("[FAIL] " & Name);
         Failed := Failed + 1;
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
         Count : constant SIO.Count := SIO.Size (File);
      begin
         if Count = 0 then
            SIO.Close (File);
            return "";
         end if;
         declare
            Bytes : Stream_Element_Array (1 .. Stream_Element_Offset (Count));
            Last  : Stream_Element_Offset;
            Text  : String (1 .. Natural (Count));
         begin
            SIO.Read (File, Bytes, Last);
            if Last /= Bytes'Last then
               raise Program_Error with "short test read";
            end if;
            for I in Bytes'Range loop
               Text (Natural (I)) := Character'Val (Bytes (I));
            end loop;
            SIO.Close (File);
            return Text;
         end;
      end;
   end Read_Exact;

   function Recovery_Path (Message : String) return String is
      Position : constant Natural := Index (Message, Recovery_Marker);
   begin
      if Position = 0 then
         return "";
      end if;
      return Message
        (Position + Recovery_Marker'Length .. Message'Last);
   end Recovery_Path;

   function Backup_File_Count return Natural is
      Search : Search_Type;
      Item   : Directory_Entry_Type;
      Count  : Natural := 0;
      Filter : constant Filter_Type :=
        [Directory => False, Ordinary_File => True, Special_File => False];
   begin
      Start_Search
        (Search,
         "/tmp",
         "hra_writer_exact_replacement.tsv.backup.*.tmp",
         Filter);
      while More_Entries (Search) loop
         Get_Next_Entry (Search, Item);
         Count := Count + 1;
      end loop;
      End_Search (Search);
      return Count;
   end Backup_File_Count;

   procedure Clean is
   begin
      HRA.Writer.Test_Hooks.Clear_After_Stage_Hook;
      HRA.Writer.Test_Hooks.Clear_After_Publish_Hook;
      if Exists (Target) then Delete_File (Target); end if;
      if Exists (Guard) then Delete_File (Guard); end if;
      if Exists (Target & ".bak") then Delete_File (Target & ".bak"); end if;
      if Length (Recovery) > 0 and then Exists (To_String (Recovery)) then
         Delete_File (To_String (Recovery));
      end if;
      if Length (Staged) > 0 and then Exists (To_String (Staged)) then
         Delete_File (To_String (Staged));
      end if;
      Staged := Null_Unbounded_String;
      Recovery := Null_Unbounded_String;
      Hook_Called := False;
   end Clean;

   procedure Capture_Stage (Path : String) is
   begin
      Hook_Called := True;
      Staged := To_Unbounded_String (Path);
   end Capture_Stage;

   procedure Change_Guard_After_Stage (Path : String) is
   begin
      Capture_Stage (Path);
      Write_Exact (Guard, Changed_Guard);
   end Change_Guard_After_Stage;

   procedure Change_Guard_After_Publish (Path : String) is
      pragma Unreferenced (Path);
   begin
      Write_Exact (Guard, Changed_Guard);
   end Change_Guard_After_Publish;

   procedure Change_Guard_And_Target (Path : String) is
   begin
      Write_Exact (Guard, Changed_Guard);
      Write_Exact (Path, External_Bytes);
   end Change_Guard_And_Target;

begin
   Put_Line ("--- Testing source-neutral exact replacement ---");
   Clean;

   --  Present -> Present, arbitrary non-Journal TSV-like bytes, and successful
   --  staging/backup cleanup are covered by one exact replacement.
   Write_Exact (Target, Old_Bytes);
   Write_Exact (Target & ".bak", "operator-owned sentinel" & ASCII.LF);
   declare
      Expected : Expected_Source;
      Empty_Guards : Source_Premise_Array (1 .. 0);
   begin
      Assert (Observe_Source (Target, Expected, Error), "Present premise observed");
      HRA.Writer.Test_Hooks.Set_After_Stage_Hook (Capture_Stage'Address);
      Assert
        (Atomic_Replace_Exact_Guarded
           (Target, Expected, Make_Candidate_Source (TSV_Bytes), Empty_Guards,
            Status, Error)
         and then Status = Success and then Read_Exact (Target) = TSV_Bytes,
         "Present target is replaced by arbitrary non-Journal bytes");
      HRA.Writer.Test_Hooks.Clear_After_Stage_Hook;
      Assert (Hook_Called and then not Exists (To_String (Staged)),
              "Successful replacement cleans its unique staging path");
      Assert (Backup_File_Count = 0,
              "Successful replacement cleans its own unique recovery backup");
      Assert
        (Read_Exact (Target & ".bak") = "operator-owned sentinel" & ASCII.LF,
         "Successful replacement does not alter a pre-existing .bak file");
      Assert (Read_Exact (Target) = TSV_Bytes,
              "Exact primitive requires no Journal semantic parser");
   end;

   --  Absent -> Present creation.
   Clean;
   declare
      Empty_Guards : Source_Premise_Array (1 .. 0);
   begin
      Assert
        (Atomic_Replace_Exact_Guarded
           (Target, Make_Absent_Expected_Source,
            Make_Candidate_Source (TSV_Bytes), Empty_Guards, Status, Error)
         and then Exists (Target) and then Read_Exact (Target) = TSV_Bytes,
         "Absent target is created with exact candidate bytes");
   end;

   --  Present empty is not Absent.
   Clean;
   Write_Exact (Target, "");
   declare
      Empty_Guards : Source_Premise_Array (1 .. 0);
   begin
      Assert
        (not Atomic_Replace_Exact_Guarded
           (Target, Make_Absent_Expected_Source,
            Make_Candidate_Source (TSV_Bytes), Empty_Guards, Status, Error)
         and then Status = Stale_Source_Rejected and then Exists (Target)
         and then Read_Exact (Target) = "",
         "Present empty target is distinct from Absent premise");
   end;

   --  Initial target stale fence rejects before staging.
   Clean;
   Write_Exact (Target, Old_Bytes);
   declare
      Empty_Guards : Source_Premise_Array (1 .. 0);
   begin
      HRA.Writer.Test_Hooks.Set_After_Stage_Hook (Capture_Stage'Address);
      Assert
        (not Atomic_Replace_Exact_Guarded
           (Target, Make_Expected_Source ("stale"),
            Make_Candidate_Source (TSV_Bytes), Empty_Guards, Status, Error)
         and then Status = Stale_Source_Rejected and then not Hook_Called
         and then Read_Exact (Target) = Old_Bytes,
         "Stale target rejects before staging or mutation");
      HRA.Writer.Test_Hooks.Clear_After_Stage_Hook;
   end;

   --  Initial guard stale fence rejects before staging.
   Clean;
   Write_Exact (Target, Old_Bytes);
   Write_Exact (Guard, Changed_Guard);
   declare
      Expected : Expected_Source;
      Guards : constant Source_Premise_Array (1 .. 1) :=
        [1 => Make_Source_Premise (Guard, Make_Expected_Source (Guard_Bytes))];
   begin
      Assert (Observe_Source (Target, Expected, Error), "Guard test target observed");
      HRA.Writer.Test_Hooks.Set_After_Stage_Hook (Capture_Stage'Address);
      Assert
        (not Atomic_Replace_Exact_Guarded
           (Target, Expected, Make_Candidate_Source (TSV_Bytes), Guards,
            Status, Error)
         and then Status = Stale_Source_Rejected and then not Hook_Called
         and then Read_Exact (Target) = Old_Bytes,
         "Stale guard rejects before staging or mutation");
      HRA.Writer.Test_Hooks.Clear_After_Stage_Hook;
   end;

   --  Guard race after staging leaves target untouched and cleans own staging.
   Clean;
   Write_Exact (Target, Old_Bytes);
   Write_Exact (Guard, Guard_Bytes);
   declare
      Expected : Expected_Source;
      Guards : constant Source_Premise_Array (1 .. 1) :=
        [1 => Make_Source_Premise (Guard, Make_Expected_Source (Guard_Bytes))];
   begin
      Assert (Observe_Source (Target, Expected, Error), "Staging-race target observed");
      HRA.Writer.Test_Hooks.Set_After_Stage_Hook
        (Change_Guard_After_Stage'Address);
      Assert
        (not Atomic_Replace_Exact_Guarded
           (Target, Expected, Make_Candidate_Source (TSV_Bytes), Guards,
            Status, Error)
         and then Status = Stale_Source_Rejected
         and then Read_Exact (Target) = Old_Bytes,
         "Guard change after staging rejects before target replacement");
      HRA.Writer.Test_Hooks.Clear_After_Stage_Hook;
      Assert (Length (Staged) > 0 and then not Exists (To_String (Staged)),
              "Pre-publication failure cleans Writer's staging file");
   end;

   --  Post-replacement guard race restores the exact old target.
   Clean;
   Write_Exact (Target, Old_Bytes);
   Write_Exact (Guard, Guard_Bytes);
   declare
      Expected : Expected_Source;
      Guards : constant Source_Premise_Array (1 .. 1) :=
        [1 => Make_Source_Premise (Guard, Make_Expected_Source (Guard_Bytes))];
   begin
      Assert (Observe_Source (Target, Expected, Error), "Rollback target observed");
      HRA.Writer.Test_Hooks.Set_After_Publish_Hook
        (Change_Guard_After_Publish'Address);
      Assert
        (not Atomic_Replace_Exact_Guarded
           (Target, Expected, Make_Candidate_Source (TSV_Bytes), Guards,
            Status, Error)
         and then Status = Stale_Source_Rejected
         and then Read_Exact (Target) = Old_Bytes
         and then not Exists (Target & ".bak"),
         "Post-replacement guard change causes exact rollback");
      HRA.Writer.Test_Hooks.Clear_After_Publish_Hook;
   end;

   --  A later external target mutation is never overwritten by rollback.
   Clean;
   Write_Exact (Target, Old_Bytes);
   Write_Exact (Guard, Guard_Bytes);
   declare
      Expected : Expected_Source;
      Guards : constant Source_Premise_Array (1 .. 1) :=
        [1 => Make_Source_Premise (Guard, Make_Expected_Source (Guard_Bytes))];
   begin
      Assert (Observe_Source (Target, Expected, Error), "External-race target observed");
      HRA.Writer.Test_Hooks.Set_After_Publish_Hook
        (Change_Guard_And_Target'Address);
      Assert
        (not Atomic_Replace_Exact_Guarded
           (Target, Expected, Make_Candidate_Source (TSV_Bytes), Guards,
            Status, Error)
         and then Status = File_Write_Failed
         and then Read_Exact (Target) = External_Bytes,
         "Rollback refuses to overwrite a later external target change");
      HRA.Writer.Test_Hooks.Clear_After_Publish_Hook;

      Recovery := To_Unbounded_String (Recovery_Path (To_String (Error)));
      Assert
        (Length (Recovery) > 0
         and then Index (To_String (Error), Recovery_Marker) > 0,
         "Rollback-refused diagnostic identifies the recovery backup path");
      Assert
        (Exists (To_String (Recovery))
         and then Read_Exact (To_String (Recovery)) = Old_Bytes,
         "Rollback refusal retains exact old Expected bytes in a unique backup");
   end;

   --  A later successful publication owns another unique backup and cannot
   --  overwrite or clean the retained evidence from the refused rollback.
   declare
      Retained_Path  : constant String := To_String (Recovery);
      Expected_Now   : Expected_Source;
      Empty_Guards   : Source_Premise_Array (1 .. 0);
      Next_Candidate : constant String := "next" & ASCII.HT & "publication";
   begin
      Assert
        (Observe_Source (Target, Expected_Now, Error)
         and then Atomic_Replace_Exact_Guarded
           (Target, Expected_Now, Make_Candidate_Source (Next_Candidate),
            Empty_Guards, Status, Error)
         and then Status = Success
         and then Read_Exact (Target) = Next_Candidate,
         "Later exact publication succeeds from newly observed target bytes");
      Assert
        (Exists (Retained_Path)
         and then Read_Exact (Retained_Path) = Old_Bytes,
         "Later publication preserves prior recovery evidence byte-for-byte");
   end;

   Clean;
   New_Line;
   Put_Line ("Summary: Passed =" & Natural'Image (Passed) &
             ", Failed =" & Natural'Image (Failed));
   if Failed > 0 then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   else
      Put_Line ("RESULT: SUCCESS");
   end if;
end Test_Writer_Exact_Replacement;
