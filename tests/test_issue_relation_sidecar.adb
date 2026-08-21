with Ada.Command_Line;
with Ada.Directories; use Ada.Directories;
with Ada.Streams; use Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Text_IO; use Ada.Text_IO;
with HRA.Issue_Relation.Sidecar;

procedure Test_Issue_Relation_Sidecar is
   use type HRA.Issue_Relation.Sidecar.Observation_Status;
   use type HRA.Issue_Relation.Sidecar.Presence;

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

   Root         : constant String := "/tmp/hra_issue_relation_sidecar_test";
   Missing_Root : constant String := "/tmp/hra_issue_relation_sidecar_missing";
   Sidecar      : constant String := Root & "/issue-relations.tsv";

   Result : HRA.Issue_Relation.Sidecar.Observation;
   Diag   : HRA.Issue_Relation.Sidecar.Observation_Diagnostic;

begin
   Put_Line ("--- Testing Issue relation sidecar observation ---");

   if Exists (Root) then
      if Kind (Root) = Directory then
         Delete_Tree (Root);
      else
         Delete_File (Root);
      end if;
   end if;

   if Exists (Missing_Root) then
      if Kind (Missing_Root) = Directory then
         Delete_Tree (Missing_Root);
      else
         Delete_File (Missing_Root);
      end if;
   end if;

   Assert
     (not HRA.Issue_Relation.Sidecar.Observe
        (Missing_Root, Result, Diag)
        and then Diag.Status =
          HRA.Issue_Relation.Sidecar.Root_Not_Directory,
      "Missing Household root is not mistaken for absent sidecar");

   Create_Directory (Root);

   Assert
     (HRA.Issue_Relation.Sidecar.Observe (Root, Result, Diag)
        and then HRA.Issue_Relation.Sidecar.State_Of (Result) =
          HRA.Issue_Relation.Sidecar.Absent
        and then HRA.Issue_Relation.Sidecar.Path_Of (Result) = Sidecar,
      "Missing sidecar is an explicit successful Absent observation");

   declare
      Absent_Path : constant String :=
        HRA.Issue_Relation.Sidecar.Path_Of (Result);
   begin
      Write_Exact (Sidecar, "");
      Assert
        (HRA.Issue_Relation.Sidecar.Observe (Root, Result, Diag)
           and then HRA.Issue_Relation.Sidecar.State_Of (Result) =
             HRA.Issue_Relation.Sidecar.Present
           and then HRA.Issue_Relation.Sidecar.Path_Of (Result) = Absent_Path
           and then HRA.Issue_Relation.Sidecar.Text_Of (Result) = "",
         "Present empty sidecar remains distinct from Absent at the same path");
   end;

   declare
      Exact_Text : constant String :=
        "relation_event_id" & ASCII.HT &
        "recorded_on" & ASCII.HT &
        "issue_id" & ASCII.HT &
        "relation_kind" & ASCII.HT &
        "target_id" & ASCII.HT &
        "details" & ASCII.CR & ASCII.LF &
        "rel-1" & ASCII.HT &
        "2026-08-21" & ASCII.HT &
        "ISSUE-1" & ASCII.HT &
        "realized-as" & ASCII.HT &
        "actual-1" & ASCII.HT &
        "exact bytes";
   begin
      Write_Exact (Sidecar, Exact_Text);
      Assert
        (HRA.Issue_Relation.Sidecar.Observe (Root, Result, Diag)
           and then HRA.Issue_Relation.Sidecar.State_Of (Result) =
             HRA.Issue_Relation.Sidecar.Present
           and then HRA.Issue_Relation.Sidecar.Text_Of (Result) = Exact_Text,
         "Present sidecar preserves CRLF and missing trailing newline exactly");
   end;

   Delete_File (Sidecar);
   Create_Directory (Sidecar);
   Assert
     (not HRA.Issue_Relation.Sidecar.Observe (Root, Result, Diag)
        and then Diag.Status =
          HRA.Issue_Relation.Sidecar.Sidecar_Not_Regular_File,
      "Existing non-file sidecar coordinate fails closed");

   Delete_Tree (Root);

   New_Line;
   Put_Line
     ("Summary: Passed =" & Natural'Image (Passed_Count) &
      ", Failed =" & Natural'Image (Failed_Count));

   if Failed_Count > 0 then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   else
      Put_Line ("RESULT: SUCCESS");
   end if;
end Test_Issue_Relation_Sidecar;
