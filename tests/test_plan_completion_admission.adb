with Ada.Command_Line;
with Ada.Text_IO; use Ada.Text_IO;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA.Actual_Admission;
with HRA.Journal;
with HRA.Journal_Evidence;
with HRA.Ledger;
with HRA.Plan_Admission;
with HRA.Plan_Completion;

procedure Test_Plan_Completion_Admission is
   use type HRA.Actual_Admission.Admission_Status;
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

   function Admit_Plans return HRA.Plan_Admission.Plan_Journal is
      Source : constant String :=
        "2026-08-20 Planned purchase" & ASCII.LF &
        "    ; plan-id: plan-a" & ASCII.LF &
        "    assets:cash        -100 JPY" & ASCII.LF &
        "    expenses:food       100 JPY" & ASCII.LF;
      L             : HRA.Ledger.Ledger;
      Parse_Error   : Unbounded_String;
      Evidence      : HRA.Journal_Evidence.Journal_Evidence;
      Evidence_Diag : HRA.Journal_Evidence.Evidence_Diagnostic;
      Journal       : HRA.Plan_Admission.Plan_Journal;
      Diag          : HRA.Plan_Admission.Admission_Diagnostic;
   begin
      if not HRA.Journal.Parse_Journal_Text (Source, L, Parse_Error) then
         raise Program_Error with "test Plan source failed Journal admission";
      end if;
      if not HRA.Journal_Evidence.Extract (Source, L, Evidence, Evidence_Diag) then
         raise Program_Error with "test Plan source failed evidence extraction";
      end if;
      if not HRA.Plan_Admission.Admit (L, Evidence, Journal, Diag) then
         raise Program_Error with "test Plan source failed native Plan admission";
      end if;
      return Journal;
   end Admit_Plans;

   Plans : constant HRA.Plan_Admission.Plan_Journal := Admit_Plans;

   function Admit_Actual
     (Source : String;
      Result : out HRA.Actual_Admission.Actual_Observation;
      Diag   : out HRA.Actual_Admission.Admission_Diagnostic) return Boolean
   is
      L             : HRA.Ledger.Ledger;
      Parse_Error   : Unbounded_String;
      Evidence      : HRA.Journal_Evidence.Journal_Evidence;
      Evidence_Diag : HRA.Journal_Evidence.Evidence_Diagnostic;
   begin
      if not HRA.Journal.Parse_Journal_Text (Source, L, Parse_Error) then
         raise Program_Error with
           "test Actual source failed Journal admission: " & To_String (Parse_Error);
      end if;
      if not HRA.Journal_Evidence.Extract (Source, L, Evidence, Evidence_Diag) then
         raise Program_Error with
           "test Actual source failed evidence extraction: " &
           To_String (Evidence_Diag.Message);
      end if;
      return HRA.Actual_Admission.Admit (L, Evidence, Result, Diag);
   end Admit_Actual;

   function Admit_Completions
     (Source : String;
      Diag   : out HRA.Plan_Completion.Admission_Diagnostic) return Boolean
   is
      Actual      : HRA.Actual_Admission.Actual_Observation;
      Actual_Diag : HRA.Actual_Admission.Admission_Diagnostic;
      Relations   : HRA.Plan_Completion.Completion_Relations;
   begin
      if not Admit_Actual (Source, Actual, Actual_Diag) then
         raise Program_Error with
           "test source unexpectedly failed Actual admission: " &
           HRA.Actual_Admission.Admission_Status'Image (Actual_Diag.Status);
      end if;
      return HRA.Plan_Completion.Admit (Plans, Actual, Relations, Diag);
   end Admit_Completions;

   Known_Source : constant String :=
     "2026-08-10 Completion" & ASCII.LF &
     "    ; plan-id: plan-a" & ASCII.LF &
     "    assets:cash        -100 JPY" & ASCII.LF &
     "    expenses:food       100 JPY" & ASCII.LF;

   Identity_Free_Source : constant String :=
     "2026-08-10 Ordinary actual" & ASCII.LF &
     "    assets:cash         -50 JPY" & ASCII.LF &
     "    expenses:food        50 JPY" & ASCII.LF;

   Unknown_Source : constant String :=
     "2026-08-10 Unknown completion" & ASCII.LF &
     "    ; plan-id: plan-missing" & ASCII.LF &
     "    assets:cash        -100 JPY" & ASCII.LF &
     "    expenses:food       100 JPY" & ASCII.LF;

   Multiple_Source : constant String :=
     "2026-08-10 First completion [event-id: completion-a-1]" & ASCII.LF &
     "    ; plan-id: plan-a" & ASCII.LF &
     "    assets:cash        -100 JPY" & ASCII.LF &
     "    expenses:food       100 JPY" & ASCII.LF & ASCII.LF &
     "2026-08-11 Second completion [event-id: completion-a-2]" & ASCII.LF &
     "    ; plan-id: plan-a" & ASCII.LF &
     "    assets:cash         -20 JPY" & ASCII.LF &
     "    expenses:food        20 JPY" & ASCII.LF;

   Duplicate_Metadata_Source : constant String :=
     "2026-08-10 Duplicate metadata" & ASCII.LF &
     "    ; plan-id: plan-a" & ASCII.LF &
     "    ; plan-id: plan-a" & ASCII.LF &
     "    assets:cash        -100 JPY" & ASCII.LF &
     "    expenses:food       100 JPY" & ASCII.LF;

   Invalid_Source : constant String :=
     "2026-08-10 Invalid completion" & ASCII.LF &
     "    ; plan-id: bad id" & ASCII.LF &
     "    assets:cash        -100 JPY" & ASCII.LF &
     "    expenses:food       100 JPY" & ASCII.LF;

   Completion_Diag : HRA.Plan_Completion.Admission_Diagnostic;

begin
   Put_Line ("--- Testing Plan completion admission ---");

   Assert
     (Admit_Completions (Known_Source, Completion_Diag),
      "Known Plan completion is admitted");

   Assert
     (Admit_Completions (Identity_Free_Source, Completion_Diag),
      "Ordinary identity-free Actual remains valid");

   Assert
     (not Admit_Completions (Unknown_Source, Completion_Diag)
        and then Completion_Diag.Status = HRA.Plan_Completion.Unknown_Completion_Plan,
      "Actual completion must reference an admitted Plan");

   Assert
     (not Admit_Completions (Multiple_Source, Completion_Diag)
        and then Completion_Diag.Status = HRA.Plan_Completion.Multiple_Completion_Actuals,
      "Distinct Actual identities cannot complete one Plan twice");

   declare
      Actual      : HRA.Actual_Admission.Actual_Observation;
      Actual_Diag : HRA.Actual_Admission.Admission_Diagnostic;
   begin
      Assert
        (not Admit_Actual (Duplicate_Metadata_Source, Actual, Actual_Diag)
           and then Actual_Diag.Status = HRA.Actual_Admission.Duplicate_Metadata,
         "duplicate completion metadata is rejected by Actual admission");
   end;

   declare
      Actual      : HRA.Actual_Admission.Actual_Observation;
      Actual_Diag : HRA.Actual_Admission.Admission_Diagnostic;
   begin
      Assert
        (not Admit_Actual (Invalid_Source, Actual, Actual_Diag)
           and then Actual_Diag.Status = HRA.Actual_Admission.Invalid_Plan_Id,
         "invalid completion PlanId is rejected by Actual admission");
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
end Test_Plan_Completion_Admission;
