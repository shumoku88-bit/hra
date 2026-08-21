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
with HRA.Plan_Temporal_Observation;

procedure Test_Plan_Temporal_Observation is
   use type HRA.Dates.Date;

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

   function D (Text : String) return HRA.Dates.Date is
      Value  : HRA.Dates.Date;
      Status : HRA.Dates.Date_Status;
   begin
      if not HRA.Dates.Parse (Text, Value, Status) then
         raise Program_Error with "invalid synthetic date";
      end if;
      return Value;
   end D;

   function Admit_Plans (Source : String) return HRA.Plan_Admission.Plan_Journal is
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
   end Admit_Plans;

   function Admit_Actuals
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
   end Admit_Actuals;

   Plan_Source : constant String :=
     "2026-08-10 Old commitment" & ASCII.LF &
     "    ; plan-id: plan-old" & ASCII.LF &
     "    ; superseded-on: 2026-08-20" & ASCII.LF &
     "    ; superseded-by: plan-new" & ASCII.LF &
     "    assets:cash       -100 JPY" & ASCII.LF &
     "    expenses:food      100 JPY" & ASCII.LF & ASCII.LF &
     "2026-09-01 Future-dated successor" & ASCII.LF &
     "    ; plan-id: plan-new" & ASCII.LF &
     "    assets:cash       -120 JPY" & ASCII.LF &
     "    expenses:food      120 JPY" & ASCII.LF;

   Actual_Source : constant String :=
     "2026-08-25 Early completion" & ASCII.LF &
     "    ; plan-id: plan-new" & ASCII.LF &
     "    assets:cash       -110 JPY" & ASCII.LF &
     "    expenses:food      110 JPY" & ASCII.LF;

   Plans : constant HRA.Plan_Admission.Plan_Journal :=
     Admit_Plans (Plan_Source);
   Actuals : constant HRA.Actual_Admission.Actual_Observation :=
     Admit_Actuals (Actual_Source);
   Relations : HRA.Plan_Completion.Completion_Relations;
   Relation_Diag : HRA.Plan_Completion.Admission_Diagnostic;

begin
   Put_Line ("--- Testing HRA.Plan_Temporal_Observation ---");

   if not HRA.Plan_Completion.Admit
     (Plans, Actuals, Relations, Relation_Diag)
   then
      raise Program_Error with "completion relation setup failed";
   end if;

   declare
      Before_Retirement : constant HRA.Plan_Temporal_Observation.Observation :=
        HRA.Plan_Temporal_Observation.Observe
          (Plans, Relations, D ("2026-08-19"));
   begin
      Assert
        (Natural (Before_Retirement.Open_Plans.Length) = 2
           and then Natural (Before_Retirement.Completed_Plans.Length) = 0,
         "future retirement and future completion do not close Plans early");
      Assert
        (HRA.Plan.Text (Before_Retirement.Open_Plans.Element (2).ID) =
           "plan-new",
         "future planned date is not an open-Plan selection coordinate");
   end;

   declare
      On_Retirement : constant HRA.Plan_Temporal_Observation.Observation :=
        HRA.Plan_Temporal_Observation.Observe
          (Plans, Relations, D ("2026-08-20"));
   begin
      Assert
        (Natural (On_Retirement.Open_Plans.Length) = 1
           and then HRA.Plan.Text
             (On_Retirement.Open_Plans.Element (1).ID) = "plan-new",
         "supersession becomes visible exactly on its admitted date");
   end;

   declare
      Before_Completion : constant HRA.Plan_Temporal_Observation.Observation :=
        HRA.Plan_Temporal_Observation.Observe
          (Plans, Relations, D ("2026-08-24"));
   begin
      Assert
        (Natural (Before_Completion.Open_Plans.Length) = 1
           and then Natural (Before_Completion.Completed_Plans.Length) = 0,
         "completion relation remains invisible before Actual date");
   end;

   declare
      On_Completion : constant HRA.Plan_Temporal_Observation.Observation :=
        HRA.Plan_Temporal_Observation.Observe
          (Plans, Relations, D ("2026-08-25"));
   begin
      Assert
        (Natural (On_Completion.Open_Plans.Length) = 0
           and then Natural (On_Completion.Completed_Plans.Length) = 1
           and then HRA.Plan.Text
             (On_Completion.Completed_Plans.Element (1).ID) = "plan-new",
         "completion becomes visible exactly with its Actual fact");
      Assert
        (On_Completion.Completed_Plans.Element (1).Actual_Tx.Date =
           D ("2026-08-25"),
         "completed projection retains the exact admitted Actual endpoint");
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
end Test_Plan_Temporal_Observation;
