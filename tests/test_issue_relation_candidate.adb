with Ada.Command_Line;
with Ada.Directories; use Ada.Directories;
with Ada.Streams; use Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Text_IO; use Ada.Text_IO;
with HRA.Actual_Admission;
with HRA.Dates;
with HRA.Issue_Relation;
with HRA.Issue_Relation.Sidecar;
with HRA.Issue_Relation.TSV;
with HRA.Issue_Relation_Candidate;
with HRA.Issues;

procedure Test_Issue_Relation_Candidate is
   use type HRA.Dates.Date;
   use type HRA.Issue_Relation.Relation_Kind;
   use type HRA.Issue_Relation.Sidecar.Presence;
   use type HRA.Issue_Relation.TSV.Admission_Status;
   use type HRA.Issue_Relation_Candidate.Candidate_Status;

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

   Temp_Root    : constant String := ".hra-test-issue-relation-candidate";
   Sidecar_Path : constant String :=
     Compose (Temp_Root, "issue-relations.tsv");

   procedure Write_Exact (Path : String; Text : String) is
      package SIO renames Ada.Streams.Stream_IO;
      File : SIO.File_Type;
   begin
      SIO.Create (File, SIO.Out_File, Path);
      if Text'Length > 0 then
         declare
            Bytes : Stream_Element_Array
              (1 .. Stream_Element_Offset (Text'Length));
         begin
            for I in Text'Range loop
               Bytes (Stream_Element_Offset (I - Text'First + 1)) :=
                 Stream_Element (Character'Pos (Text (I)));
            end loop;
            SIO.Write (File, Bytes);
         end;
      end if;
      SIO.Close (File);
   exception
      when others =>
         if SIO.Is_Open (File) then
            SIO.Close (File);
         end if;
         raise;
   end Write_Exact;

   function Observe_Absent
     return HRA.Issue_Relation.Sidecar.Observation
   is
      Result : HRA.Issue_Relation.Sidecar.Observation;
      Diag   : HRA.Issue_Relation.Sidecar.Observation_Diagnostic;
   begin
      if Exists (Sidecar_Path) then
         Delete_File (Sidecar_Path);
      end if;
      if not HRA.Issue_Relation.Sidecar.Observe (Temp_Root, Result, Diag) then
         raise Program_Error with "failed to observe absent candidate fixture";
      end if;
      return Result;
   end Observe_Absent;

   function Observe_Present
     (Source_Text : String) return HRA.Issue_Relation.Sidecar.Observation
   is
      Result : HRA.Issue_Relation.Sidecar.Observation;
      Diag   : HRA.Issue_Relation.Sidecar.Observation_Diagnostic;
   begin
      Write_Exact (Sidecar_Path, Source_Text);
      if not HRA.Issue_Relation.Sidecar.Observe (Temp_Root, Result, Diag) then
         raise Program_Error with "failed to observe present candidate fixture";
      end if;
      return Result;
   end Observe_Present;

   function D (Value : String) return HRA.Dates.Date is
      Result : HRA.Dates.Date;
      Status : HRA.Dates.Date_Status;
   begin
      if not HRA.Dates.Parse (Value, Result, Status) then
         raise Program_Error with "invalid test date: " & Value;
      end if;
      return Result;
   end D;

   function Make_Event
     (ID_Text      : String;
      Recorded_On  : String;
      Issue_ID_Str : String;
      Actual_ID_Str: String;
      Details_Str  : String) return HRA.Issue_Relation.Relation_Event
   is
      Event_ID      : HRA.Issue_Relation.Relation_Event_Id;
      ID_Status     : HRA.Issue_Relation.Relation_Event_Id_Status;
      Issue_ID      : HRA.Issues.Issue_Id;
      Issue_Status  : HRA.Issues.Issue_Id_Status;
      Actual_ID     : HRA.Actual_Admission.Actual_Id;
      Actual_Status : HRA.Actual_Admission.Actual_Id_Status;
      Event         : HRA.Issue_Relation.Relation_Event;
      Create_Status : HRA.Issue_Relation.Create_Status;
   begin
      if not HRA.Issue_Relation.Create_Relation_Event_Id (ID_Text, Event_ID, ID_Status) then
         raise Program_Error with "invalid event id: " & ID_Text;
      end if;
      if not HRA.Issues.Create_Issue_Id (Issue_ID_Str, Issue_ID, Issue_Status) then
         raise Program_Error with "invalid issue id: " & Issue_ID_Str;
      end if;
      if not HRA.Actual_Admission.Create_Actual_Id (Actual_ID_Str, Actual_ID, Actual_Status) then
         raise Program_Error with "invalid actual id: " & Actual_ID_Str;
      end if;
      if not HRA.Issue_Relation.Create_Realized_As
        (Event_ID    => Event_ID,
         Recorded_On => D (Recorded_On),
         Issue_ID    => Issue_ID,
         Actual_ID   => Actual_ID,
         Details     => Details_Str,
         Event       => Event,
         Status      => Create_Status)
      then
         raise Program_Error with "failed to create realized_as event";
      end if;
      return Event;
   end Make_Event;

   Header : constant String :=
     HRA.Issue_Relation.TSV.Canonical_Header_Text;

   Event1 : constant HRA.Issue_Relation.Relation_Event :=
     Make_Event ("rel-1", "2026-08-21", "ISSUE-DESK", "actual-desk-001", "bought desk");
   Event2 : constant HRA.Issue_Relation.Relation_Event :=
     Make_Event ("rel-2", "2026-08-22", "ISSUE-CHAIR", "actual-chair-002", "bought chair");

   Candidate : HRA.Issue_Relation_Candidate.Candidate_Source;
   Diag      : HRA.Issue_Relation_Candidate.Candidate_Diagnostic;

begin
   Put_Line ("--- Testing Issue Relation Candidate Preparation ---");

   if Exists (Temp_Root) then
      Delete_Tree (Temp_Root);
   end if;
   Create_Directory (Temp_Root);

   --  1. Absent sidecar observation -> first canonical relation candidate
   declare
      Observed : constant HRA.Issue_Relation.Sidecar.Observation :=
        Observe_Absent;
   begin
      Assert
        (HRA.Issue_Relation_Candidate.Prepare (Observed, Event1, Candidate, Diag),
         "Absent sidecar produces first canonical candidate");
      Assert
        (HRA.Issue_Relation_Candidate.Path_Of (Candidate) =
           Compose (Full_Name (Temp_Root), "issue-relations.tsv"),
         "Candidate retains observed sidecar path");
      Assert
        (HRA.Issue_Relation_Candidate.Observed_State_Of (Candidate) =
           HRA.Issue_Relation.Sidecar.Absent,
         "Candidate retains Absent observed state");
      Assert
        (HRA.Issue_Relation_Candidate.Observed_Text (Candidate) = "",
         "Candidate retains empty text for Absent observed state");

      declare
         Expected_Text : constant String :=
           Header & ASCII.LF &
           "rel-1" & ASCII.HT &
           "2026-08-21" & ASCII.HT &
           "ISSUE-DESK" & ASCII.HT &
           "realized-as" & ASCII.HT &
           "actual-desk-001" & ASCII.HT &
           "bought desk" & ASCII.LF;
      begin
         Assert
           (HRA.Issue_Relation_Candidate.Text (Candidate) = Expected_Text,
            "Candidate text matches canonical header and rendered row with trailing LF");
      end;

      declare
         Hist : constant HRA.Issue_Relation.TSV.Relation_History :=
           HRA.Issue_Relation_Candidate.History_Of (Candidate);
      begin
         Assert
           (HRA.Issue_Relation.TSV.Count (Hist) = 1,
            "Candidate history contains exactly one relation");
         declare
            Ev : constant HRA.Issue_Relation.Relation_Event :=
              HRA.Issue_Relation.TSV.Element (Hist, 1);
         begin
            Assert
              (HRA.Issue_Relation.Text (HRA.Issue_Relation.Event_Id (Ev)) = "rel-1"
               and then HRA.Issue_Relation.Recorded_On (Ev) = D ("2026-08-21")
               and then HRA.Issues.Text (HRA.Issue_Relation.Issue_Id (Ev)) = "ISSUE-DESK"
               and then HRA.Issue_Relation.Kind (Ev) = HRA.Issue_Relation.Realized_As
               and then HRA.Actual_Admission.Text (HRA.Issue_Relation.Actual_Id (Ev)) = "actual-desk-001"
               and then HRA.Issue_Relation.Details (Ev) = "bought desk",
               "Re-admitted relation matches input event exactly");
         end;
      end;
   end;

   --  2. Present empty sidecar -> distinct premise from Absent
   declare
      Observed : constant HRA.Issue_Relation.Sidecar.Observation :=
        Observe_Present ("");
   begin
      Assert
        (HRA.Issue_Relation_Candidate.Prepare (Observed, Event1, Candidate, Diag),
         "Present empty sidecar produces candidate");
      Assert
        (HRA.Issue_Relation_Candidate.Observed_State_Of (Candidate) =
           HRA.Issue_Relation.Sidecar.Present,
         "Present empty sidecar premise is distinguished from Absent");
      Assert
        (HRA.Issue_Relation_Candidate.Observed_Text (Candidate) = "",
         "Present empty sidecar text is empty string");
      Assert
        (HRA.Issue_Relation.TSV.Count
           (HRA.Issue_Relation_Candidate.History_Of (Candidate)) = 1,
         "Candidate from present empty sidecar has count 1");
   end;

   --  3. Present comment-only sidecar -> preserves existing bytes and adds header + row
   declare
      Comment_Source : constant String :=
        "# initial comment" & ASCII.LF & "# second comment" & ASCII.LF;
      Observed : constant HRA.Issue_Relation.Sidecar.Observation :=
        Observe_Present (Comment_Source);
   begin
      Assert
        (HRA.Issue_Relation_Candidate.Prepare (Observed, Event1, Candidate, Diag),
         "Comment-only sidecar produces candidate");
      Assert
        (HRA.Issue_Relation_Candidate.Observed_Text (Candidate) = Comment_Source,
         "Observed comment text is preserved byte-for-byte in premise");

      declare
         Candidate_Str : constant String :=
           HRA.Issue_Relation_Candidate.Text (Candidate);
         Expected_Str  : constant String :=
           Comment_Source & Header & ASCII.LF &
           "rel-1" & ASCII.HT &
           "2026-08-21" & ASCII.HT &
           "ISSUE-DESK" & ASCII.HT &
           "realized-as" & ASCII.HT &
           "actual-desk-001" & ASCII.HT &
           "bought desk" & ASCII.LF;
      begin
         Assert
           (Candidate_Str = Expected_Str,
            "Comment-only source retains existing comments and prepends header before row");
      end;
   end;

   --  4. Present existing history -> appends 2nd relation in order, retaining existing bytes
   declare
      Existing_Source : constant String :=
        Header & ASCII.LF &
        "rel-1" & ASCII.HT &
        "2026-08-21" & ASCII.HT &
        "ISSUE-DESK" & ASCII.HT &
        "realized-as" & ASCII.HT &
        "actual-desk-001" & ASCII.HT &
        "bought desk" & ASCII.LF;
      Observed : constant HRA.Issue_Relation.Sidecar.Observation :=
        Observe_Present (Existing_Source);
   begin
      Assert
        (HRA.Issue_Relation_Candidate.Prepare (Observed, Event2, Candidate, Diag),
         "Appending to existing relation history succeeds");
      Assert
        (HRA.Issue_Relation_Candidate.Observed_Text (Candidate) = Existing_Source,
         "Existing source text is retained as observed premise");

      declare
         Candidate_Str : constant String :=
           HRA.Issue_Relation_Candidate.Text (Candidate);
         Expected_Str  : constant String :=
           Existing_Source &
           "rel-2" & ASCII.HT &
           "2026-08-22" & ASCII.HT &
           "ISSUE-CHAIR" & ASCII.HT &
           "realized-as" & ASCII.HT &
           "actual-chair-002" & ASCII.HT &
           "bought chair" & ASCII.LF;
      begin
         Assert
           (Candidate_Str = Expected_Str,
            "Existing source bytes are preserved and new row is appended exactly");
      end;

      declare
         Hist : constant HRA.Issue_Relation.TSV.Relation_History :=
           HRA.Issue_Relation_Candidate.History_Of (Candidate);
      begin
         Assert
           (HRA.Issue_Relation.TSV.Count (Hist) = 2,
            "Candidate history contains exactly 2 relations");
         Assert
           (HRA.Issue_Relation.Text
              (HRA.Issue_Relation.Event_Id (HRA.Issue_Relation.TSV.Element (Hist, 1))) = "rel-1"
            and then HRA.Issue_Relation.Text
              (HRA.Issue_Relation.Event_Id (HRA.Issue_Relation.TSV.Element (Hist, 2))) = "rel-2",
            "History retains original order: rel-1 then rel-2");
      end;
   end;

   --  5. Existing source with CRLF -> preserves CRLF exactly on existing lines
   declare
      CRLF_Source : constant String :=
        Header & ASCII.CR & ASCII.LF &
        "rel-1" & ASCII.HT &
        "2026-08-21" & ASCII.HT &
        "ISSUE-DESK" & ASCII.HT &
        "realized-as" & ASCII.HT &
        "actual-desk-001" & ASCII.HT &
        "bought desk" & ASCII.CR & ASCII.LF;
      Observed : constant HRA.Issue_Relation.Sidecar.Observation :=
        Observe_Present (CRLF_Source);
   begin
      Assert
        (HRA.Issue_Relation_Candidate.Prepare (Observed, Event2, Candidate, Diag),
         "Appending to CRLF source succeeds");

      declare
         Candidate_Str : constant String :=
           HRA.Issue_Relation_Candidate.Text (Candidate);
         Expected_Str  : constant String :=
           CRLF_Source &
           "rel-2" & ASCII.HT &
           "2026-08-22" & ASCII.HT &
           "ISSUE-CHAIR" & ASCII.HT &
           "realized-as" & ASCII.HT &
           "actual-chair-002" & ASCII.HT &
           "bought chair" & ASCII.LF;
      begin
         Assert
           (Candidate_Str = Expected_Str,
            "Existing CRLF lines are preserved byte-for-byte without unwanted normalization");
      end;
   end;

   --  6. Existing source missing trailing LF -> adds single LF before row
   declare
      No_Trailing_LF : constant String :=
        Header & ASCII.LF &
        "rel-1" & ASCII.HT &
        "2026-08-21" & ASCII.HT &
        "ISSUE-DESK" & ASCII.HT &
        "realized-as" & ASCII.HT &
        "actual-desk-001" & ASCII.HT &
        "bought desk";
      Observed : constant HRA.Issue_Relation.Sidecar.Observation :=
        Observe_Present (No_Trailing_LF);
   begin
      Assert
        (HRA.Issue_Relation_Candidate.Prepare (Observed, Event2, Candidate, Diag),
         "Appending to source without trailing LF succeeds");

      declare
         Candidate_Str : constant String :=
           HRA.Issue_Relation_Candidate.Text (Candidate);
         Expected_Str  : constant String :=
           No_Trailing_LF & ASCII.LF &
           "rel-2" & ASCII.HT &
           "2026-08-22" & ASCII.HT &
           "ISSUE-CHAIR" & ASCII.HT &
           "realized-as" & ASCII.HT &
           "actual-chair-002" & ASCII.HT &
           "bought chair" & ASCII.LF;
      begin
         Assert
           (Candidate_Str = Expected_Str,
            "Single LF is placed between existing source and new row");
      end;
   end;

   --  7. Duplicate relation event ID rejection
   declare
      Existing_Source : constant String :=
        Header & ASCII.LF &
        "rel-1" & ASCII.HT &
        "2026-08-21" & ASCII.HT &
        "ISSUE-DESK" & ASCII.HT &
        "realized-as" & ASCII.HT &
        "actual-desk-001" & ASCII.HT &
        "bought desk" & ASCII.LF;
      Observed : constant HRA.Issue_Relation.Sidecar.Observation :=
        Observe_Present (Existing_Source);
      Dup_Event : constant HRA.Issue_Relation.Relation_Event :=
        Make_Event ("rel-1", "2026-08-22", "ISSUE-OTHER", "actual-other", "duplicate id");
   begin
      Assert
        (not HRA.Issue_Relation_Candidate.Prepare (Observed, Dup_Event, Candidate, Diag)
         and then Diag.Status = HRA.Issue_Relation_Candidate.Candidate_Admission_Failed
         and then Diag.TSV.Status = HRA.Issue_Relation.TSV.Duplicate_Relation_Event_Id,
         "Duplicate relation event ID fails closed during candidate re-admission");
   end;

   --  8. Malformed existing source rejection
   declare
      Bad_Source : constant String := "invalid" & ASCII.HT & "header" & ASCII.LF;
      Observed   : constant HRA.Issue_Relation.Sidecar.Observation :=
        Observe_Present (Bad_Source);
   begin
      Assert
        (not HRA.Issue_Relation_Candidate.Prepare (Observed, Event1, Candidate, Diag)
         and then Diag.Status = HRA.Issue_Relation_Candidate.Existing_Sidecar_Admission_Failed
         and then Diag.TSV.Status = HRA.Issue_Relation.TSV.Invalid_Header,
         "Malformed existing sidecar fails closed with Existing_Sidecar_Admission_Failed");
   end;

   --  9. Source-local preparation does not require target Actual existence in current authority
   declare
      Observed : constant HRA.Issue_Relation.Sidecar.Observation :=
        Observe_Absent;
      Future_Event : constant HRA.Issue_Relation.Relation_Event :=
        Make_Event
          ("rel-future", "2026-08-22", "ISSUE-NEW", "actual-future-not-yet-admitted", "future relation");
   begin
      Assert
        (HRA.Issue_Relation_Candidate.Prepare (Observed, Future_Event, Candidate, Diag),
         "Source-local candidate prepares without requiring existing Actual target admission");
   end;

   Delete_Tree (Temp_Root);

   New_Line;
   Put_Line
     ("Summary: Passed =" & Natural'Image (Passed_Count) &
      ", Failed =" & Natural'Image (Failed_Count));

   if Failed_Count > 0 then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   else
      Put_Line ("RESULT: SUCCESS");
   end if;
exception
   when others =>
      if Exists (Temp_Root) then
         Delete_Tree (Temp_Root);
      end if;
      raise;
end Test_Issue_Relation_Candidate;
