with Ada.Command_Line;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO; use Ada.Text_IO;
with HRA.Actual_Admission;
with HRA.Actual_Id_Selection;
with HRA.Journal;
with HRA.Journal_Evidence;
with HRA.Ledger;

procedure Test_Actual_Id_Selection is
   use type HRA.Actual_Id_Selection.Selection_Status;

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
     (Source : String) return HRA.Actual_Admission.Actual_Observation
   is
      L             : HRA.Ledger.Ledger;
      Parse_Error   : Unbounded_String;
      Evidence      : HRA.Journal_Evidence.Journal_Evidence;
      Evidence_Diag : HRA.Journal_Evidence.Evidence_Diagnostic;
      Observation   : HRA.Actual_Admission.Actual_Observation;
      Actual_Diag   : HRA.Actual_Admission.Admission_Diagnostic;
   begin
      if not HRA.Journal.Parse_Journal_Text (Source, L, Parse_Error) then
         raise Program_Error with
           "identity selection source failed Journal admission: " &
           To_String (Parse_Error);
      end if;
      if not HRA.Journal_Evidence.Extract
        (Source, L, Evidence, Evidence_Diag)
      then
         raise Program_Error with
           "identity selection source failed evidence admission: " &
           To_String (Evidence_Diag.Message);
      end if;
      if not HRA.Actual_Admission.Admit
        (L, Evidence, Observation, Actual_Diag)
      then
         raise Program_Error with
           "identity selection source failed Actual admission: " &
           To_String (Actual_Diag.Message);
      end if;
      return Observation;
   end Admit_Source;

   function Selected_Text
     (Observation : HRA.Actual_Admission.Actual_Observation) return String
   is
      ID     : HRA.Actual_Admission.Actual_Id;
      Status : HRA.Actual_Id_Selection.Selection_Status;
   begin
      if not HRA.Actual_Id_Selection.Select_Next
        (Observation, ID, Status)
      then
         raise Program_Error with
           "identity selection unexpectedly failed: " &
           HRA.Actual_Id_Selection.Selection_Status'Image (Status);
      end if;
      return HRA.Actual_Admission.Text (ID);
   end Selected_Text;

   Hole_Source : constant String :=
     "2026-08-10 One [event-id: hra-actual-1]" & ASCII.LF &
     "    assets:cash        -10 JPY" & ASCII.LF &
     "    expenses:food      10 JPY" & ASCII.LF & ASCII.LF &
     "2026-08-11 Three [event-id: hra-actual-3]" & ASCII.LF &
     "    assets:cash        -30 JPY" & ASCII.LF &
     "    expenses:food      30 JPY" & ASCII.LF;

   Leading_Zero_Source : constant String :=
     "2026-08-10 External spelling [event-id: hra-actual-01]" & ASCII.LF &
     "    assets:cash        -10 JPY" & ASCII.LF &
     "    expenses:food      10 JPY" & ASCII.LF;

   Plan_Derived_Source : constant String :=
     "2026-08-10 Completion" & ASCII.LF &
     "    ; plan-id: plan-a" & ASCII.LF &
     "    assets:cash        -10 JPY" & ASCII.LF &
     "    expenses:food      10 JPY" & ASCII.LF;

begin
   Put_Line ("--- Testing Actual identity selection ---");

   declare
      Empty  : constant HRA.Actual_Admission.Actual_Observation :=
        HRA.Actual_Admission.Empty_Observation;
      ID     : HRA.Actual_Admission.Actual_Id;
      Status : HRA.Actual_Id_Selection.Selection_Status;
   begin
      Assert
        (HRA.Actual_Id_Selection.Select_Next (Empty, ID, Status)
         and then Status = HRA.Actual_Id_Selection.Success
         and then HRA.Actual_Admission.Text (ID) = "hra-actual-1",
         "Empty Actual authority selects the first canonical clock-free identity");
      Assert
        (Selected_Text (Empty) = "hra-actual-1",
         "Identity selection is deterministic for the same admitted authority");
   end;

   declare
      Observation : constant HRA.Actual_Admission.Actual_Observation :=
        Admit_Source (Hole_Source);
   begin
      Assert
        (Selected_Text (Observation) = "hra-actual-2",
         "Selector chooses the first unused canonical identity inside the bounded N plus one window");
   end;

   declare
      Observation : constant HRA.Actual_Admission.Actual_Observation :=
        Admit_Source (Leading_Zero_Source);
   begin
      Assert
        (Selected_Text (Observation) = "hra-actual-1",
         "Noncanonical external spelling does not occupy a different generated identity");
   end;

   declare
      Observation : constant HRA.Actual_Admission.Actual_Observation :=
        Admit_Source (Plan_Derived_Source);
      Entry : constant HRA.Actual_Admission.Actual_Transaction_Entry :=
        HRA.Actual_Admission.Transaction_At (Observation, 1);
   begin
      Assert
        (Entry.Identity.Present
         and then HRA.Actual_Admission.Text (Entry.Identity.Value) =
           "plan-completion-plan-a"
         and then Selected_Text (Observation) = "hra-actual-1",
         "Selector observes the effective identity universe without confusing Plan-derived identity with generated namespace");
   end;

   Put_Line
     ("Summary: Passed =" & Natural'Image (Passed_Count) &
      ", Failed =" & Natural'Image (Failed_Count));
   if Failed_Count > 0 then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   else
      Put_Line ("RESULT: SUCCESS");
   end if;
end Test_Actual_Id_Selection;
