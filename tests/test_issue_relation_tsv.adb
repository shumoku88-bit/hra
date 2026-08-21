with Ada.Command_Line;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO; use Ada.Text_IO;
with HRA.Actual_Admission;
with HRA.Dates;
with HRA.Issue_Relation;
with HRA.Issue_Relation.TSV;
with HRA.Issues;

procedure Test_Issue_Relation_TSV is
   use type HRA.Dates.Date;
   use type HRA.Issue_Relation.Relation_Kind;
   use type HRA.Issue_Relation.TSV.Admission_Status;

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

   function D (Value : String) return HRA.Dates.Date is
      Result : HRA.Dates.Date;
      Status : HRA.Dates.Date_Status;
   begin
      if not HRA.Dates.Parse (Value, Result, Status) then
         raise Program_Error with "invalid test date: " & Value;
      end if;
      return Result;
   end D;

   Header : constant String :=
     "relation_event_id" & ASCII.HT &
     "recorded_on"       & ASCII.HT &
     "issue_id"          & ASCII.HT &
     "relation_kind"     & ASCII.HT &
     "target_id"         & ASCII.HT &
     "details";

   History : HRA.Issue_Relation.TSV.Relation_History;
   Diag    : HRA.Issue_Relation.TSV.Admission_Diagnostic;

begin
   Put_Line ("--- Testing Issue relation TSV admission ---");

   Assert
     (HRA.Issue_Relation.TSV.Admit ("", History, Diag)
        and then HRA.Issue_Relation.TSV.Count (History) = 0,
      "Absent sidecar text admits as empty relation history");

   Assert
     (HRA.Issue_Relation.TSV.Admit
        ("# no relation history yet" & ASCII.LF & ASCII.LF,
         History,
         Diag)
        and then HRA.Issue_Relation.TSV.Count (History) = 0,
      "Comment-only source admits as empty relation history");

   declare
      Source : constant String :=
        "# explicit Issue provenance" & ASCII.CR & ASCII.LF &
        Header & ASCII.CR & ASCII.LF &
        "rel-chair-1" & ASCII.HT &
        "2026-08-21" & ASCII.HT &
        "ISSUE-CHAIR" & ASCII.HT &
        "realized-as" & ASCII.HT &
        "chair-actual" & ASCII.HT &
        "bought chair" & ASCII.CR & ASCII.LF;
   begin
      Assert
        (HRA.Issue_Relation.TSV.Admit (Source, History, Diag),
         "Six-column realized-as source admits with CRLF");
      Assert
        (HRA.Issue_Relation.TSV.Count (History) = 1,
         "Source order retains one relation event");

      declare
         Event : constant HRA.Issue_Relation.Relation_Event :=
           HRA.Issue_Relation.TSV.Element (History, 1);
      begin
         Assert
           (HRA.Issue_Relation.Text (HRA.Issue_Relation.Event_Id (Event)) =
              "rel-chair-1"
              and then HRA.Issue_Relation.Recorded_On (Event) = D ("2026-08-21")
              and then HRA.Issues.Text (HRA.Issue_Relation.Issue_Id (Event)) =
                "ISSUE-CHAIR"
              and then HRA.Issue_Relation.Kind (Event) =
                HRA.Issue_Relation.Realized_As
              and then HRA.Actual_Admission.Text
                (HRA.Issue_Relation.Actual_Id (Event)) = "chair-actual"
              and then HRA.Issue_Relation.Details (Event) = "bought chair",
            "TSV syntax maps exactly into typed relation coordinates");
      end;
   end;

   --  Source-local admission deliberately does not know the Household identity
   --  universe. The target becomes cross-source evidence only after the parent
   --  Issue_Relation owner admits references against an Actual observation.
   Assert
     (HRA.Issue_Relation.TSV.Admit
        (Header & ASCII.LF &
         "rel-unknown-target" & ASCII.HT &
         "2026-08-21" & ASCII.HT &
         "ISSUE-UNKNOWN" & ASCII.HT &
         "realized-as" & ASCII.HT &
         "actual-not-yet-resolved" & ASCII.HT & ASCII.LF,
         History,
         Diag),
      "Source-local syntax does not perform cross-source reference admission");

   Assert
     (not HRA.Issue_Relation.TSV.Admit
        ("wrong" & ASCII.HT & "header" & ASCII.LF,
         History,
         Diag)
        and then Diag.Status = HRA.Issue_Relation.TSV.Invalid_Header
        and then Diag.Line_Number = 1,
      "Unexpected header fails closed at its physical line");

   Assert
     (not HRA.Issue_Relation.TSV.Admit
        (Header & ASCII.LF &
         "rel-short" & ASCII.HT &
         "2026-08-21" & ASCII.HT &
         "ISSUE-X" & ASCII.HT &
         "realized-as" & ASCII.HT &
         "actual-x" & ASCII.LF,
         History,
         Diag)
        and then Diag.Status = HRA.Issue_Relation.TSV.Malformed_Column_Count
        and then Diag.Line_Number = 2,
      "Five-column relation row is rejected");

   Assert
     (not HRA.Issue_Relation.TSV.Admit
        (Header & ASCII.LF &
         "rel-dup" & ASCII.HT & "2026-08-20" & ASCII.HT &
         "ISSUE-A" & ASCII.HT & "realized-as" & ASCII.HT &
         "actual-a" & ASCII.HT & ASCII.LF &
         "rel-dup" & ASCII.HT & "2026-08-21" & ASCII.HT &
         "ISSUE-B" & ASCII.HT & "realized-as" & ASCII.HT &
         "actual-b" & ASCII.HT & ASCII.LF,
         History,
         Diag)
        and then Diag.Status = HRA.Issue_Relation.TSV.Duplicate_Relation_Event_Id
        and then Diag.Line_Number = 3
        and then To_String (Diag.Relation_Event_Id) = "rel-dup",
      "Duplicate relation event identity is rejected in source order");

   Assert
     (not HRA.Issue_Relation.TSV.Admit
        (Header & ASCII.LF &
         "rel-date" & ASCII.HT & "2026-02-30" & ASCII.HT &
         "ISSUE-A" & ASCII.HT & "realized-as" & ASCII.HT &
         "actual-a" & ASCII.HT & ASCII.LF,
         History,
         Diag)
        and then Diag.Status = HRA.Issue_Relation.TSV.Invalid_Recorded_Date,
      "Invalid Gregorian recorded_on is rejected");

   Assert
     (not HRA.Issue_Relation.TSV.Admit
        (Header & ASCII.LF &
         "rel-issue" & ASCII.HT & "2026-08-21" & ASCII.HT &
         "ISSUE A" & ASCII.HT & "realized-as" & ASCII.HT &
         "actual-a" & ASCII.HT & ASCII.LF,
         History,
         Diag)
        and then Diag.Status = HRA.Issue_Relation.TSV.Invalid_Issue_Id,
      "Invalid Issue identity is rejected by Issue owner law");

   Assert
     (not HRA.Issue_Relation.TSV.Admit
        (Header & ASCII.LF &
         "rel-kind" & ASCII.HT & "2026-08-21" & ASCII.HT &
         "ISSUE-A" & ASCII.HT & "similar-to" & ASCII.HT &
         "actual-a" & ASCII.HT & ASCII.LF,
         History,
         Diag)
        and then Diag.Status = HRA.Issue_Relation.TSV.Unknown_Relation_Kind,
      "Unknown relation meaning is not preserved as opaque text");

   Assert
     (not HRA.Issue_Relation.TSV.Admit
        (Header & ASCII.LF &
         "rel-actual" & ASCII.HT & "2026-08-21" & ASCII.HT &
         "ISSUE-A" & ASCII.HT & "realized-as" & ASCII.HT &
         "actual a" & ASCII.HT & ASCII.LF,
         History,
         Diag)
        and then Diag.Status = HRA.Issue_Relation.TSV.Invalid_Actual_Id,
      "Invalid Actual target identity is rejected by Actual owner law");

   Assert
     (not HRA.Issue_Relation.TSV.Admit
        (Header & ASCII.LF &
         "rel-details" & ASCII.HT & "2026-08-21" & ASCII.HT &
         "ISSUE-A" & ASCII.HT & "realized-as" & ASCII.HT &
         "actual-a" & ASCII.HT & " padded" & ASCII.LF,
         History,
         Diag)
        and then Diag.Status = HRA.Issue_Relation.TSV.Invalid_Details,
      "Relation details retain domain whitespace law");

   New_Line;
   Put_Line
     ("Summary: Passed =" & Natural'Image (Passed_Count) &
      ", Failed =" & Natural'Image (Failed_Count));

   if Failed_Count > 0 then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   else
      Put_Line ("RESULT: SUCCESS");
   end if;
end Test_Issue_Relation_TSV;
