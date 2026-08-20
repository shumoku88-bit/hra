with Ada.Command_Line;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO; use Ada.Text_IO;
with HRA.Journal;
with HRA.Journal_Evidence;
with HRA.Ledger;
with HRA.Plan;
with HRA.Plan_Admission;

procedure Test_Plan_Admission is
   use type HRA.Plan_Admission.Admission_Status;
   use type HRA.Plan_Admission.Retirement_Kind;

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
      Result : out HRA.Plan_Admission.Plan_Observation;
      Diag   : out HRA.Plan_Admission.Admission_Diagnostic) return Boolean
   is
      L             : HRA.Ledger.Ledger;
      Parse_Error   : Unbounded_String;
      Evidence      : HRA.Journal_Evidence.Journal_Evidence;
      Evidence_Diag : HRA.Journal_Evidence.Evidence_Diagnostic;
   begin
      if not HRA.Journal.Parse_Journal_Text (Source, L, Parse_Error) then
         raise Program_Error with "test source failed Journal admission: " &
           To_String (Parse_Error);
      end if;

      if not HRA.Journal_Evidence.Extract
        (Source, L, Evidence, Evidence_Diag)
      then
         raise Program_Error with "test source failed evidence extraction: " &
           To_String (Evidence_Diag.Message);
      end if;

      return HRA.Plan_Admission.Admit (L, Evidence, Result, Diag);
   end Admit_Source;

   Valid_Source : constant String :=
     "2026-08-10 Old plan" & ASCII.LF &
     "    ; plan-id: plan-old" & ASCII.LF &
     "    ; superseded-on: 2026-08-11" & ASCII.LF &
     "    ; superseded-by: plan-new" & ASCII.LF &
     "    assets:cash       -10 JPY" & ASCII.LF &
     "    expenses:food      10 JPY" & ASCII.LF & ASCII.LF &
     "2026-08-12 New plan" & ASCII.LF &
     "    ; plan-id: plan-new" & ASCII.LF &
     "    assets:cash       -12 JPY" & ASCII.LF &
     "    expenses:food      12 JPY" & ASCII.LF;

   Canceled_Source : constant String :=
     "2026-08-10 Canceled plan" & ASCII.LF &
     "    ; plan-id: plan-cancel" & ASCII.LF &
     "    ; cancelled-on: 2026-08-13" & ASCII.LF &
     "    assets:cash       -10 JPY" & ASCII.LF &
     "    expenses:food      10 JPY" & ASCII.LF;

   Unknown_Successor_Source : constant String :=
     "2026-08-10 Orphan supersession" & ASCII.LF &
     "    ; plan-id: plan-a" & ASCII.LF &
     "    ; superseded-on: 2026-08-11" & ASCII.LF &
     "    ; superseded-by: missing" & ASCII.LF &
     "    assets:cash       -10 JPY" & ASCII.LF &
     "    expenses:food      10 JPY" & ASCII.LF;

   Cycle_Source : constant String :=
     "2026-08-10 Plan A" & ASCII.LF &
     "    ; plan-id: plan-a" & ASCII.LF &
     "    ; superseded-on: 2026-08-11" & ASCII.LF &
     "    ; superseded-by: plan-b" & ASCII.LF &
     "    assets:cash       -10 JPY" & ASCII.LF &
     "    expenses:food      10 JPY" & ASCII.LF & ASCII.LF &
     "2026-08-10 Plan B" & ASCII.LF &
     "    ; plan-id: plan-b" & ASCII.LF &
     "    ; superseded-on: 2026-08-11" & ASCII.LF &
     "    ; superseded-by: plan-a" & ASCII.LF &
     "    assets:cash       -10 JPY" & ASCII.LF &
     "    expenses:food      10 JPY" & ASCII.LF;

   Duplicate_Id_Source : constant String :=
     "2026-08-10 One" & ASCII.LF &
     "    ; plan-id: same" & ASCII.LF &
     "    assets:cash       -10 JPY" & ASCII.LF &
     "    expenses:food      10 JPY" & ASCII.LF & ASCII.LF &
     "2026-08-11 Two" & ASCII.LF &
     "    ; plan-id: same" & ASCII.LF &
     "    assets:cash       -20 JPY" & ASCII.LF &
     "    expenses:food      20 JPY" & ASCII.LF;

   Observation : HRA.Plan_Admission.Plan_Observation;
   Diag        : HRA.Plan_Admission.Admission_Diagnostic;

begin
   Put_Line ("--- Testing HRA.Plan_Admission ---");

   Assert
     (Admit_Source (Valid_Source, Observation, Diag),
      "Plan Journal admits identity lifecycle and provenance together");
   Assert
     (HRA.Plan_Admission.Transaction_Count (Observation) = 2,
      "Plan admission retains source-order whole transactions");

   declare
      First : constant HRA.Plan_Admission.Plan_Transaction_Entry :=
        HRA.Plan_Admission.Transaction_At (Observation, 1);
      Second : constant HRA.Plan_Admission.Plan_Transaction_Entry :=
        HRA.Plan_Admission.Transaction_At (Observation, 2);
      Evidence : constant HRA.Journal_Evidence.Journal_Evidence :=
        HRA.Plan_Admission.Evidence_Of (Observation);
      Ids : constant HRA.Plan.Plan_Id_Universe :=
        HRA.Plan_Admission.Plan_Ids_Of (Observation);
   begin
      Assert
        (HRA.Plan.Text (First.ID) = "plan-old"
           and then First.Retirement.Kind = HRA.Plan_Admission.Superseded
           and then HRA.Plan.Text (First.Retirement.Successor) = "plan-new"
           and then HRA.Plan.Text (Second.ID) = "plan-new"
           and then Second.Retirement.Kind = HRA.Plan_Admission.Active,
         "Plan lifecycle is structural rather than Boolean plus dummy values");
      Assert
        (First.Source.Header_Line = 1
           and then Natural (Evidence.Transactions.Length) = 2,
         "Plan entries retain parser-owned provenance");
      Assert
        (HRA.Plan.Contains (Ids, First.ID)
           and then HRA.Plan.Contains (Ids, Second.ID),
         "Plan identity universe is projected from admitted entries");
   end;

   Assert
     (Admit_Source (Canceled_Source, Observation, Diag)
        and then HRA.Plan_Admission.Transaction_At
          (Observation, 1).Retirement.Kind = HRA.Plan_Admission.Canceled,
      "Cancellation has its own variant shape");

   Assert
     (not Admit_Source (Unknown_Successor_Source, Observation, Diag)
        and then Diag.Status = HRA.Plan_Admission.Unknown_Supersession_Target,
      "Unknown Plan successor fails closed");

   Assert
     (not Admit_Source (Cycle_Source, Observation, Diag)
        and then Diag.Status = HRA.Plan_Admission.Supersession_Cycle,
      "Plan supersession cycle fails closed");

   Assert
     (not Admit_Source (Duplicate_Id_Source, Observation, Diag)
        and then Diag.Status = HRA.Plan_Admission.Duplicate_Plan_Id,
      "Duplicate Plan identity fails closed");

   New_Line;
   Put_Line
     ("Summary: Passed =" & Natural'Image (Passed_Count) &
      ", Failed =" & Natural'Image (Failed_Count));

   if Failed_Count > 0 then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   else
      Put_Line ("RESULT: SUCCESS");
   end if;
end Test_Plan_Admission;
