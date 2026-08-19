with Ada.Command_Line;
with Ada.Text_IO; use Ada.Text_IO;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA.Journal;
with HRA.Journal_Evidence;
with HRA.Ledger;
with HRA.Plan;
with HRA.Plan_Observation;

procedure Test_Plan_Completion_Admission is
   use type HRA.Plan_Observation.Admission_Status;

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

   function Known_Plans return HRA.Plan.Plan_Id_Universe is
      Result : HRA.Plan.Plan_Id_Universe :=
        HRA.Plan.Empty_Plan_Id_Universe;
      PID    : HRA.Plan.Plan_Id;
      Status : HRA.Plan.Plan_Id_Status;
   begin
      if not HRA.Plan.Create_Plan_Id ("plan-a", PID, Status) then
         raise Program_Error with "test PlanId setup failed";
      end if;
      HRA.Plan.Include (Result, PID);
      return Result;
   end Known_Plans;

   function Admit_Source
     (Source : String;
      Diag   : out HRA.Plan_Observation.Admission_Diagnostic) return Boolean
   is
      L             : HRA.Ledger.Ledger;
      Parse_Error   : Unbounded_String;
      Evidence      : HRA.Journal_Evidence.Journal_Evidence;
      Evidence_Diag : HRA.Journal_Evidence.Evidence_Diagnostic;
   begin
      if not HRA.Journal.Parse_Journal_Text (Source, L, Parse_Error) then
         raise Program_Error with
           "test source failed Journal admission: " & To_String (Parse_Error);
      end if;

      if not HRA.Journal_Evidence.Extract
        (Source, L, Evidence, Evidence_Diag)
      then
         raise Program_Error with
           "test source failed evidence extraction: " &
           To_String (Evidence_Diag.Message);
      end if;

      return HRA.Plan_Observation.Admit_Plan_Completions
        (Known_Plans, L, Evidence, Diag);
   end Admit_Source;

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

   Diag : HRA.Plan_Observation.Admission_Diagnostic;

begin
   Put_Line ("--- Testing Plan completion admission ---");

   Assert
     (Admit_Source (Known_Source, Diag),
      "Known Plan completion is admitted");

   Assert
     (Admit_Source (Identity_Free_Source, Diag),
      "Ordinary identity-free Actual remains valid");

   Assert
     (not Admit_Source (Unknown_Source, Diag)
        and then Diag.Status = HRA.Plan_Observation.Unknown_Completion_Plan,
      "Actual completion must reference an admitted Plan");

   Assert
     (not Admit_Source (Multiple_Source, Diag)
        and then Diag.Status = HRA.Plan_Observation.Multiple_Completion_Actuals,
      "Distinct Actual identities cannot complete one Plan twice");

   Assert
     (not Admit_Source (Duplicate_Metadata_Source, Diag)
        and then Diag.Status = HRA.Plan_Observation.Duplicate_Plan_Metadata,
      "Completion metadata is singular per Actual transaction");

   Assert
     (not Admit_Source (Invalid_Source, Diag)
        and then Diag.Status = HRA.Plan_Observation.Invalid_Actual_Plan_Id,
      "Completion PlanId must be a valid durable Plan identity");

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
