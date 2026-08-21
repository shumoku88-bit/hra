with Ada.Command_Line;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO; use Ada.Text_IO;
with HRA.Actual_Admission;
with HRA.Dates;
with HRA.Journal;
with HRA.Journal_Evidence;
with HRA.Ledger;
with HRA.Plan;
with HRA.Plan_Admission;
with HRA.Plan_Completion;

procedure Test_Plan_Completion_Relation is
   use type HRA.Plan_Completion.Admission_Status;

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

   function Admit_Plan_Source
     (Source : String) return HRA.Plan_Admission.Plan_Journal
   is
      L             : HRA.Ledger.Ledger;
      Parse_Error   : Unbounded_String;
      Evidence      : HRA.Journal_Evidence.Journal_Evidence;
      Evidence_Diag : HRA.Journal_Evidence.Evidence_Diagnostic;
      Result        : HRA.Plan_Admission.Plan_Journal;
      Diag          : HRA.Plan_Admission.Admission_Diagnostic;
   begin
      if not HRA.Journal.Parse_Journal_Text (Source, L, Parse_Error)
        or else not HRA.Journal_Evidence.Extract
          (Source, L, Evidence, Evidence_Diag)
        or else not HRA.Plan_Admission.Admit (L, Evidence, Result, Diag)
      then
         raise Program_Error with "Plan setup admission failed";
      end if;
      return Result;
   end Admit_Plan_Source;

   function Admit_Actual_Source
     (Source : String) return HRA.Actual_Admission.Actual_Observation
   is
      L             : HRA.Ledger.Ledger;
      Parse_Error   : Unbounded_String;
      Evidence      : HRA.Journal_Evidence.Journal_Evidence;
      Evidence_Diag : HRA.Journal_Evidence.Evidence_Diagnostic;
      Result        : HRA.Actual_Admission.Actual_Observation;
      Diag          : HRA.Actual_Admission.Admission_Diagnostic;
   begin
      if not HRA.Journal.Parse_Journal_Text (Source, L, Parse_Error)
        or else not HRA.Journal_Evidence.Extract
          (Source, L, Evidence, Evidence_Diag)
        or else not HRA.Actual_Admission.Admit (L, Evidence, Result, Diag)
      then
         raise Program_Error with "Actual setup admission failed";
      end if;
      return Result;
   end Admit_Actual_Source;

   Plan_Source : constant String :=
     "2026-09-01 Planned food" & ASCII.LF &
     "    ; plan-id: plan-a" & ASCII.LF &
     "    assets:cash       -100 JPY" & ASCII.LF &
     "    expenses:food      100 JPY" & ASCII.LF;

   Known_And_Ordinary_Actual : constant String :=
     "2026-08-10 Completion" & ASCII.LF &
     "    ; plan-id: plan-a" & ASCII.LF &
     "    assets:cash        -80 JPY" & ASCII.LF &
     "    expenses:food       80 JPY" & ASCII.LF & ASCII.LF &
     "2026-08-11 Ordinary actual" & ASCII.LF &
     "    assets:cash        -20 JPY" & ASCII.LF &
     "    expenses:food       20 JPY" & ASCII.LF;

   Unknown_Actual : constant String :=
     "2026-08-10 Unknown completion" & ASCII.LF &
     "    ; plan-id: plan-missing" & ASCII.LF &
     "    assets:cash        -50 JPY" & ASCII.LF &
     "    expenses:food       50 JPY" & ASCII.LF;

   Multiple_Actual : constant String :=
     "2026-08-10 First completion" & ASCII.LF &
     "    ; event-id: actual-a-1" & ASCII.LF &
     "    ; plan-id: plan-a" & ASCII.LF &
     "    assets:cash        -80 JPY" & ASCII.LF &
     "    expenses:food       80 JPY" & ASCII.LF & ASCII.LF &
     "2026-08-11 Second completion" & ASCII.LF &
     "    ; event-id: actual-a-2" & ASCII.LF &
     "    ; plan-id: plan-a" & ASCII.LF &
     "    assets:cash        -20 JPY" & ASCII.LF &
     "    expenses:food       20 JPY" & ASCII.LF;

   Plans     : constant HRA.Plan_Admission.Plan_Journal :=
     Admit_Plan_Source (Plan_Source);
   Relations : HRA.Plan_Completion.Completion_Relations;
   Diag      : HRA.Plan_Completion.Admission_Diagnostic;

begin
   Put_Line ("--- Testing HRA.Plan_Completion ---");

   declare
      Actuals : constant HRA.Actual_Admission.Actual_Observation :=
        Admit_Actual_Source (Known_And_Ordinary_Actual);
   begin
      Assert
        (HRA.Plan_Completion.Admit (Plans, Actuals, Relations, Diag),
         "explicit admitted Actual-to-Plan completion relation is admitted");
      Assert
        (HRA.Plan_Completion.Count (Relations) = 1,
         "ordinary Actual without plan-id creates no completion relation");

      declare
         Relation : constant HRA.Plan_Completion.Completion_Relation :=
           HRA.Plan_Completion.Relation_At (Relations, 1);
      begin
         Assert
           (HRA.Plan.Text (Relation.Plan_ID) = "plan-a"
              and then HRA.Plan.Text (Relation.Plan.ID) = "plan-a"
              and then Relation.Actual.Identity.Present
              and then HRA.Actual_Admission.Text
                (Relation.Actual.Identity.Value) = "plan-completion-plan-a",
            "relation retains typed Plan identity and whole admitted endpoints");
         Assert
           (Relation.Plan.Source.Header_Line = 1
              and then Relation.Actual.Source.Header_Line = 1,
            "relation preserves provenance on both endpoint facts");
      end;

      declare
         PID      : HRA.Plan.Plan_Id;
         PStat    : HRA.Plan.Plan_Id_Status;
         Rel_Out  : HRA.Plan_Completion.Completion_Relation;
         D_Before : HRA.Dates.Date;
         D_After  : HRA.Dates.Date;
         DStat    : HRA.Dates.Date_Status;
      begin
         if not HRA.Plan.Create_Plan_Id ("plan-a", PID, PStat)
           or else not HRA.Dates.Parse ("2026-08-09", D_Before, DStat)
           or else not HRA.Dates.Parse ("2026-08-10", D_After, DStat)
         then
            raise Program_Error with "test setup parsing failed";
         end if;

         Assert
           (not HRA.Plan_Completion.Has_Visible_Completion
              (Relations, PID, D_Before, Rel_Out),
            "completion is not visible before Actual transaction date");

         Assert
           (HRA.Plan_Completion.Has_Visible_Completion
              (Relations, PID, D_After, Rel_Out)
              and then HRA.Plan.Text (Rel_Out.Plan_ID) = "plan-a",
            "completion is visible on or after Actual transaction date");
      end;
   end;

   declare
      Actuals : constant HRA.Actual_Admission.Actual_Observation :=
        Admit_Actual_Source (Unknown_Actual);
   begin
      Assert
        (not HRA.Plan_Completion.Admit (Plans, Actuals, Relations, Diag)
           and then Diag.Status = HRA.Plan_Completion.Unknown_Completion_Plan,
         "completion relation cannot reference an unknown admitted Plan");
   end;

   declare
      Actuals : constant HRA.Actual_Admission.Actual_Observation :=
        Admit_Actual_Source (Multiple_Actual);
   begin
      Assert
        (not HRA.Plan_Completion.Admit (Plans, Actuals, Relations, Diag)
           and then Diag.Status = HRA.Plan_Completion.Multiple_Completion_Actuals,
         "one Plan cannot be completed by multiple distinct Actual facts");
   end;

   New_Line;
   Put_Line
     ("Summary: Passed =" & Natural'Image (Passed_Count) &
      ", Failed =" & Natural'Image (Failed_Count));

   if Failed_Count > 0 then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   else
      Put_Line ("RESULT: SUCCESS");
   end if;
end Test_Plan_Completion_Relation;
