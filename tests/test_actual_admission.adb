with Ada.Command_Line;
with Ada.Text_IO; use Ada.Text_IO;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with ALedger.Actual_Admission;
with ALedger.Journal;
with ALedger.Journal_Evidence;
with ALedger.Ledger;

procedure Test_Actual_Admission is
   use type ALedger.Actual_Admission.Admission_Status;

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

   function Admit_Source
     (Source : String;
      Result : out ALedger.Actual_Admission.Actual_Observation;
      Diag   : out ALedger.Actual_Admission.Admission_Diagnostic) return Boolean
   is
      L             : ALedger.Ledger.Ledger;
      Parse_Error   : Unbounded_String;
      Evidence      : ALedger.Journal_Evidence.Journal_Evidence;
      Evidence_Diag : ALedger.Journal_Evidence.Evidence_Diagnostic;
   begin
      if not ALedger.Journal.Parse_Journal_Text (Source, L, Parse_Error) then
         raise Program_Error with "test source failed Journal admission: " &
           To_String (Parse_Error);
      end if;

      if not ALedger.Journal_Evidence.Extract
        (Source, L, Evidence, Evidence_Diag)
      then
         raise Program_Error with "test source failed evidence extraction: " &
           To_String (Evidence_Diag.Message);
      end if;

      return ALedger.Actual_Admission.Admit (L, Evidence, Result, Diag);
   end Admit_Source;

   Valid_Source : constant String :=
     "2026-08-10 Completion" & ASCII.LF &
     "    ; plan-id: plan-a" & ASCII.LF &
     "    assets:savings      100 JPY" & ASCII.LF &
     "    assets:cash        -100 JPY" & ASCII.LF & ASCII.LF &
     "2026-08-11 Undo [event-id: rev-a] [reverses: plan-completion-plan-a]" & ASCII.LF &
     "    assets:savings     -100 JPY" & ASCII.LF &
     "    assets:cash         100 JPY" & ASCII.LF;

   Duplicate_Id_Source : constant String :=
     "2026-08-10 One [event-id: same]" & ASCII.LF &
     "    assets:cash        -10 JPY" & ASCII.LF &
     "    expenses:food      10 JPY" & ASCII.LF & ASCII.LF &
     "2026-08-11 Two [event-id: same]" & ASCII.LF &
     "    assets:cash        -20 JPY" & ASCII.LF &
     "    expenses:food      20 JPY" & ASCII.LF;

   Missing_Reversal_Id_Source : constant String :=
     "2026-08-10 One [event-id: a]" & ASCII.LF &
     "    assets:cash        -10 JPY" & ASCII.LF &
     "    expenses:food      10 JPY" & ASCII.LF & ASCII.LF &
     "2026-08-11 Undo [reverses: a]" & ASCII.LF &
     "    assets:cash         10 JPY" & ASCII.LF &
     "    expenses:food     -10 JPY" & ASCII.LF;

   Unknown_Target_Source : constant String :=
     "2026-08-11 Undo [event-id: r] [reverses: missing]" & ASCII.LF &
     "    assets:cash         10 JPY" & ASCII.LF &
     "    expenses:food     -10 JPY" & ASCII.LF;

   Duplicate_Target_Source : constant String :=
     "2026-08-10 One [event-id: a]" & ASCII.LF &
     "    assets:cash        -10 JPY" & ASCII.LF &
     "    expenses:food      10 JPY" & ASCII.LF & ASCII.LF &
     "2026-08-11 Undo 1 [event-id: r1] [reverses: a]" & ASCII.LF &
     "    assets:cash         10 JPY" & ASCII.LF &
     "    expenses:food     -10 JPY" & ASCII.LF & ASCII.LF &
     "2026-08-12 Undo 2 [event-id: r2] [reverses: a]" & ASCII.LF &
     "    assets:cash         10 JPY" & ASCII.LF &
     "    expenses:food     -10 JPY" & ASCII.LF;

   Mismatch_Source : constant String :=
     "2026-08-10 One [event-id: a]" & ASCII.LF &
     "    assets:cash        -10 JPY" & ASCII.LF &
     "    expenses:food      10 JPY" & ASCII.LF & ASCII.LF &
     "2026-08-11 Wrong undo [event-id: r] [reverses: a]" & ASCII.LF &
     "    assets:cash          9 JPY" & ASCII.LF &
     "    expenses:food      -9 JPY" & ASCII.LF;

   Cycle_Source : constant String :=
     "2026-08-10 A [event-id: a] [reverses: b]" & ASCII.LF &
     "    assets:cash        -10 JPY" & ASCII.LF &
     "    expenses:food      10 JPY" & ASCII.LF & ASCII.LF &
     "2026-08-11 B [event-id: b] [reverses: a]" & ASCII.LF &
     "    assets:cash         10 JPY" & ASCII.LF &
     "    expenses:food     -10 JPY" & ASCII.LF;

   Duplicate_Metadata_Source : constant String :=
     "2026-08-10 One [event-id: a]" & ASCII.LF &
     "    ; event-id: a" & ASCII.LF &
     "    assets:cash        -10 JPY" & ASCII.LF &
     "    expenses:food      10 JPY" & ASCII.LF;

   Observation : ALedger.Actual_Admission.Actual_Observation;
   Diag        : ALedger.Actual_Admission.Admission_Diagnostic;

begin
   Put_Line ("--- Testing ALedger.Actual_Admission ---");

   Assert
     (Admit_Source (Valid_Source, Observation, Diag),
      "Explicit reversal may target Plan-derived Actual identity");
   Assert
     (ALedger.Actual_Admission.Identified_Count (Observation) = 2 and then
      ALedger.Actual_Admission.Reversal_Count (Observation) = 1,
      "Actual admission retains identified transactions and reversal edge");
   Assert
     (Natural (Observation.Value.Transactions.Length) = 2 and then
      To_String (Observation.Value.Transactions.Element (1).Event_ID) =
        "plan-completion-plan-a" and then
      To_String (Observation.Value.Transactions.Element (1).Reverses_ID) = "" and then
      To_String (Observation.Value.Transactions.Element (2).Event_ID) = "rev-a" and then
      To_String (Observation.Value.Transactions.Element (2).Reverses_ID) =
        "plan-completion-plan-a",
      "Admitted Ledger carries only normalized identity provenance");

   Assert
     (not Admit_Source (Duplicate_Id_Source, Observation, Diag) and then
      Diag.Status = ALedger.Actual_Admission.Duplicate_Actual_Id,
      "Duplicate Actual identity is rejected");

   Assert
     (not Admit_Source (Missing_Reversal_Id_Source, Observation, Diag) and then
      Diag.Status = ALedger.Actual_Admission.Reversal_Missing_Event_Id,
      "Reversal requires its own explicit event-id");

   Assert
     (not Admit_Source (Unknown_Target_Source, Observation, Diag) and then
      Diag.Status = ALedger.Actual_Admission.Unknown_Reversal_Target,
      "Unknown reversal target is rejected");

   Assert
     (not Admit_Source (Duplicate_Target_Source, Observation, Diag) and then
      Diag.Status = ALedger.Actual_Admission.Duplicate_Reversal_Target,
      "One Actual target cannot be directly reversed twice");

   Assert
     (not Admit_Source (Mismatch_Source, Observation, Diag) and then
      Diag.Status = ALedger.Actual_Admission.Reversal_Posting_Mismatch,
      "Reversal posting effect must be exact inverse");

   Assert
     (not Admit_Source (Cycle_Source, Observation, Diag) and then
      Diag.Status = ALedger.Actual_Admission.Reversal_Cycle,
      "Reversal provenance cycle is rejected");

   Assert
     (not Admit_Source (Duplicate_Metadata_Source, Observation, Diag) and then
      Diag.Status = ALedger.Actual_Admission.Duplicate_Metadata,
      "Header and indented metadata share one duplicate-key law");

   New_Line;
   Put_Line
     ("Summary: Passed =" & Natural'Image (Passed_Count) &
      ", Failed =" & Natural'Image (Failed_Count));

   if Failed_Count > 0 then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   else
      Put_Line ("RESULT: SUCCESS");
   end if;
end Test_Actual_Admission;
