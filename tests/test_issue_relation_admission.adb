with Ada.Command_Line;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO; use Ada.Text_IO;
with HRA.Actual_Admission;
with HRA.Issue_Relation;
with HRA.Issue_Relation.Admission;
with HRA.Issue_Relation.TSV;
with HRA.Issues;
with HRA.Journal;
with HRA.Journal_Evidence;
with HRA.Ledger;

procedure Test_Issue_Relation_Admission is
   use type HRA.Issue_Relation.Admission.Admission_Status;
   use type HRA.Issue_Relation.Reference_Status;
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

   function Admit_Actual_Source
     (Source : String) return HRA.Actual_Admission.Actual_Observation
   is
      L             : HRA.Ledger.Ledger;
      Parse_Error   : Unbounded_String;
      Evidence      : HRA.Journal_Evidence.Journal_Evidence;
      Evidence_Diag : HRA.Journal_Evidence.Evidence_Diagnostic;
      Observation   : HRA.Actual_Admission.Actual_Observation;
      Diag          : HRA.Actual_Admission.Admission_Diagnostic;
   begin
      if not HRA.Journal.Parse_Journal_Text (Source, L, Parse_Error) then
         raise Program_Error with "test Actual Journal failed: " &
           To_String (Parse_Error);
      end if;

      if not HRA.Journal_Evidence.Extract
        (Source, L, Evidence, Evidence_Diag)
      then
         raise Program_Error with "test Actual evidence failed: " &
           To_String (Evidence_Diag.Message);
      end if;

      if not HRA.Actual_Admission.Admit (L, Evidence, Observation, Diag) then
         raise Program_Error with "test Actual admission failed: " &
           To_String (Diag.Message);
      end if;

      return Observation;
   end Admit_Actual_Source;

   Issue_Header : constant String :=
     "issue_id" & ASCII.HT &
     "status" & ASCII.HT &
     "date" & ASCII.HT &
     "due" & ASCII.HT &
     "closed" & ASCII.HT &
     "category" & ASCII.HT &
     "title" & ASCII.HT &
     "amount" & ASCII.HT &
     "currency" & ASCII.HT &
     "details";

   Issue_Source : constant String :=
     Issue_Header & ASCII.LF &
     "ISSUE-OPEN" & ASCII.HT & "open" & ASCII.HT & "2026-08-01" & ASCII.HT &
     "none" & ASCII.HT & "none" & ASCII.HT & "purchase" & ASCII.HT &
     "Chair" & ASCII.HT & "" & ASCII.HT & "" & ASCII.HT & "" & ASCII.LF &
     "ISSUE-RESOLVED" & ASCII.HT & "resolved" & ASCII.HT & "2026-08-01" & ASCII.HT &
     "none" & ASCII.HT & "2026-08-15" & ASCII.HT & "purchase" & ASCII.HT &
     "Older chair" & ASCII.HT & "" & ASCII.HT & "" & ASCII.HT & "" & ASCII.LF;

   Actual_Source : constant String :=
     "2026-08-10 Plan completion" & ASCII.LF &
     "    ; plan-id: plan-a" & ASCII.LF &
     "    assets:cash         -100 JPY" & ASCII.LF &
     "    expenses:household   100 JPY" & ASCII.LF & ASCII.LF &
     "2026-08-11 Chair [event-id: chair-actual]" & ASCII.LF &
     "    assets:cash         -200 JPY" & ASCII.LF &
     "    expenses:household   200 JPY" & ASCII.LF;

   Relation_Header : constant String :=
     "relation_event_id" & ASCII.HT &
     "recorded_on"       & ASCII.HT &
     "issue_id"          & ASCII.HT &
     "relation_kind"     & ASCII.HT &
     "target_id"         & ASCII.HT &
     "details";

   Issues  : HRA.Issues.Issues_Inventory;
   I_Diag  : HRA.Issues.Admission_Diagnostic;
   Actuals : HRA.Actual_Admission.Actual_Observation;
   History : HRA.Issue_Relation.Admission.Admitted_History;
   Diag    : HRA.Issue_Relation.Admission.Admission_Diagnostic;

begin
   Put_Line ("--- Testing Issue relation cross-source admission ---");

   if not HRA.Issues.Admit_Issues_TSV (Issue_Source, Issues, I_Diag) then
      raise Program_Error with "test Issues admission failed";
   end if;
   Actuals := Admit_Actual_Source (Actual_Source);

   Assert
     (HRA.Issue_Relation.Admission.Admit
        ("", Issues, Actuals, History, Diag)
        and then HRA.Issue_Relation.Admission.Count (History) = 0,
      "Empty sidecar admits as empty cross-source history");

   declare
      Source : constant String :=
        Relation_Header & ASCII.LF &
        "rel-open" & ASCII.HT & "2026-08-12" & ASCII.HT &
        "ISSUE-OPEN" & ASCII.HT & "realized-as" & ASCII.HT &
        "chair-actual" & ASCII.HT & "purchase recorded" & ASCII.LF &
        "rel-resolved" & ASCII.HT & "2026-08-16" & ASCII.HT &
        "ISSUE-RESOLVED" & ASCII.HT & "realized-as" & ASCII.HT &
        "chair-actual" & ASCII.HT & "historical link" & ASCII.LF;
   begin
      Assert
        (HRA.Issue_Relation.Admission.Admit
           (Source, Issues, Actuals, History, Diag),
         "Known Issue and source-durable Actual references admit");
      Assert
        (HRA.Issue_Relation.Admission.Count (History) = 2
           and then HRA.Issue_Relation.Text
             (HRA.Issue_Relation.Event_Id
                (HRA.Issue_Relation.Admission.Element (History, 1))) = "rel-open"
           and then HRA.Issue_Relation.Text
             (HRA.Issue_Relation.Event_Id
                (HRA.Issue_Relation.Admission.Element (History, 2))) = "rel-resolved",
         "Admitted relation history retains source order");
      Assert
        (HRA.Issue_Relation.Admission.Count (History) = 2,
         "Resolved Issue may retain independent historical relation evidence");
   end;

   Assert
     (not HRA.Issue_Relation.Admission.Admit
        ("wrong-header" & ASCII.LF,
         Issues,
         Actuals,
         History,
         Diag)
        and then Diag.Status = HRA.Issue_Relation.Admission.Source_Error
        and then Diag.Source.Status = HRA.Issue_Relation.TSV.Invalid_Header,
      "Source syntax failure remains distinguishable from reference failure");

   Assert
     (not HRA.Issue_Relation.Admission.Admit
        (Relation_Header & ASCII.LF &
         "rel-missing-issue" & ASCII.HT & "2026-08-12" & ASCII.HT &
         "ISSUE-MISSING" & ASCII.HT & "realized-as" & ASCII.HT &
         "chair-actual" & ASCII.HT & ASCII.LF,
         Issues,
         Actuals,
         History,
         Diag)
        and then Diag.Status = HRA.Issue_Relation.Admission.Reference_Error
        and then Diag.Relation_Index = 1
        and then To_String (Diag.Relation_Event_Id) = "rel-missing-issue"
        and then Diag.Reference.Status = HRA.Issue_Relation.Unknown_Issue,
      "Unknown Issue is rejected at cross-source admission");

   Assert
     (not HRA.Issue_Relation.Admission.Admit
        (Relation_Header & ASCII.LF &
         "rel-derived-actual" & ASCII.HT & "2026-08-12" & ASCII.HT &
         "ISSUE-OPEN" & ASCII.HT & "realized-as" & ASCII.HT &
         "plan-completion-plan-a" & ASCII.HT & ASCII.LF,
         Issues,
         Actuals,
         History,
         Diag)
        and then Diag.Status = HRA.Issue_Relation.Admission.Reference_Error
        and then Diag.Reference.Status =
          HRA.Issue_Relation.Unknown_Source_Durable_Actual,
      "Plan-derived effective Actual identity is not cross-source evidence");

   Assert
     (not HRA.Issue_Relation.Admission.Admit
        (Relation_Header & ASCII.LF &
         "rel-good" & ASCII.HT & "2026-08-12" & ASCII.HT &
         "ISSUE-OPEN" & ASCII.HT & "realized-as" & ASCII.HT &
         "chair-actual" & ASCII.HT & ASCII.LF &
         "rel-bad-second" & ASCII.HT & "2026-08-13" & ASCII.HT &
         "ISSUE-MISSING" & ASCII.HT & "realized-as" & ASCII.HT &
         "chair-actual" & ASCII.HT & ASCII.LF,
         Issues,
         Actuals,
         History,
         Diag)
        and then Diag.Status = HRA.Issue_Relation.Admission.Reference_Error
        and then Diag.Relation_Index = 2
        and then To_String (Diag.Relation_Event_Id) = "rel-bad-second",
      "Reference admission fails closed in relation source order");

   New_Line;
   Put_Line
     ("Summary: Passed =" & Natural'Image (Passed_Count) &
      ", Failed =" & Natural'Image (Failed_Count));

   if Failed_Count > 0 then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   else
      Put_Line ("RESULT: SUCCESS");
   end if;
end Test_Issue_Relation_Admission;
