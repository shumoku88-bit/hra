with Ada.Command_Line;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO; use Ada.Text_IO;
with HRA.Actual_Admission;
with HRA.Dates;
with HRA.Issue_Relation;
with HRA.Issues;
with HRA.Journal;
with HRA.Journal_Evidence;
with HRA.Ledger;

procedure Test_Issue_Relation is
   use type HRA.Dates.Date;
   use type HRA.Issue_Relation.Create_Status;
   use type HRA.Issue_Relation.Reference_Status;
   use type HRA.Issue_Relation.Relation_Event_Id_Status;
   use type HRA.Issue_Relation.Relation_Kind;

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

   Issues_Header : constant String :=
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

   Issues_Source : constant String :=
     Issues_Header & ASCII.LF &
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

   Issues     : HRA.Issues.Issues_Inventory;
   Issues_Diag : HRA.Issues.Admission_Diagnostic;
   Actuals    : HRA.Actual_Admission.Actual_Observation;

begin
   Put_Line ("--- Testing HRA.Issue_Relation ---");

   if not HRA.Issues.Admit_Issues_TSV (Issues_Source, Issues, Issues_Diag) then
      raise Program_Error with "test Issue admission failed: " &
        To_String (Issues_Diag.Message);
   end if;
   Actuals := Admit_Actual_Source (Actual_Source);

   declare
      Event_ID_Status : HRA.Issue_Relation.Relation_Event_Id_Status;
      Event_ID        : HRA.Issue_Relation.Relation_Event_Id;
      Event_Status    : HRA.Issue_Relation.Create_Status;
      Event           : HRA.Issue_Relation.Relation_Event;
      Ref_Diag        : HRA.Issue_Relation.Reference_Diagnostic;
      Durable_Actual  : constant HRA.Actual_Admission.Actual_Transaction_Entry :=
        HRA.Actual_Admission.Transaction_At (Actuals, 2);
   begin
      Assert
        (HRA.Issue_Relation.Create_Relation_Event_Id
           ("rel-chair-realized", Event_ID, Event_ID_Status)
         and then Event_ID_Status = HRA.Issue_Relation.Success,
         "Relation event identity admits a stable non-whitespace value");

      Assert
        (HRA.Issue_Relation.Create_Realized_As
           (Event_ID    => Event_ID,
            Recorded_On => D ("2026-08-12"),
            Issue_ID    => HRA.Issues.Make_Issue_Id ("ISSUE-OPEN"),
            Actual_ID   => Durable_Actual.Source_Durable_Identity.Value,
            Details     => "bought after deciding",
            Event       => Event,
            Status      => Event_Status)
         and then Event_Status = HRA.Issue_Relation.Create_Success,
         "Create explicit Issue Realized_As relation event");

      Assert
        (HRA.Issue_Relation.Kind (Event) = HRA.Issue_Relation.Realized_As
         and then HRA.Issue_Relation.Recorded_On (Event) = D ("2026-08-12")
         and then HRA.Issues.Text (HRA.Issue_Relation.Issue_Id (Event)) =
           "ISSUE-OPEN"
         and then HRA.Actual_Admission.Text
           (HRA.Issue_Relation.Actual_Id (Event)) = "chair-actual"
         and then HRA.Issue_Relation.Details (Event) = "bought after deciding",
         "Relation retains its own date, endpoints, kind, and details");

      Assert
        (HRA.Issue_Relation.Admit_References
           (Event, Issues, Actuals, Ref_Diag)
         and then Ref_Diag.Status = HRA.Issue_Relation.Reference_Success,
         "Realized_As accepts known Issue and source-durable Actual");
   end;

   --  Reference admission owns endpoint existence, not Issue lifecycle. A
   --  historical relation to an already resolved Issue remains valid evidence.
   declare
      Event_ID_Status : HRA.Issue_Relation.Relation_Event_Id_Status;
      Event_ID        : HRA.Issue_Relation.Relation_Event_Id;
      Event_Status    : HRA.Issue_Relation.Create_Status;
      Event           : HRA.Issue_Relation.Relation_Event;
      Ref_Diag        : HRA.Issue_Relation.Reference_Diagnostic;
      Durable_Actual  : constant HRA.Actual_Admission.Actual_Transaction_Entry :=
        HRA.Actual_Admission.Transaction_At (Actuals, 2);
   begin
      if not HRA.Issue_Relation.Create_Relation_Event_Id
        ("rel-resolved-history", Event_ID, Event_ID_Status)
        or else not HRA.Issue_Relation.Create_Realized_As
          (Event_ID,
           D ("2026-08-14"),
           HRA.Issues.Make_Issue_Id ("ISSUE-RESOLVED"),
           Durable_Actual.Source_Durable_Identity.Value,
           "historical relation",
           Event,
           Event_Status)
      then
         raise Program_Error with "failed to prepare resolved-Issue relation";
      end if;

      Assert
        (HRA.Issue_Relation.Admit_References
           (Event, Issues, Actuals, Ref_Diag),
         "Relation reference admission does not require Issue to be Open");
   end;

   --  Effective Plan-completion identity exists inside Actual semantics but is
   --  not source-durable cross-source evidence.
   declare
      Event_ID_Status : HRA.Issue_Relation.Relation_Event_Id_Status;
      Event_ID        : HRA.Issue_Relation.Relation_Event_Id;
      Event_Status    : HRA.Issue_Relation.Create_Status;
      Event           : HRA.Issue_Relation.Relation_Event;
      Ref_Diag        : HRA.Issue_Relation.Reference_Diagnostic;
      Derived_Actual  : constant HRA.Actual_Admission.Actual_Transaction_Entry :=
        HRA.Actual_Admission.Transaction_At (Actuals, 1);
   begin
      if not HRA.Issue_Relation.Create_Relation_Event_Id
        ("rel-derived-target", Event_ID, Event_ID_Status)
        or else not HRA.Issue_Relation.Create_Realized_As
          (Event_ID,
           D ("2026-08-12"),
           HRA.Issues.Make_Issue_Id ("ISSUE-OPEN"),
           Derived_Actual.Identity.Value,
           "",
           Event,
           Event_Status)
      then
         raise Program_Error with "failed to prepare derived-Actual relation";
      end if;

      Assert
        (not HRA.Issue_Relation.Admit_References
           (Event, Issues, Actuals, Ref_Diag)
         and then Ref_Diag.Status =
           HRA.Issue_Relation.Unknown_Source_Durable_Actual,
         "Realized_As rejects Plan-derived effective Actual identity");
   end;

   declare
      Event_ID_Status : HRA.Issue_Relation.Relation_Event_Id_Status;
      Event_ID        : HRA.Issue_Relation.Relation_Event_Id;
      Event_Status    : HRA.Issue_Relation.Create_Status;
      Event           : HRA.Issue_Relation.Relation_Event;
      Ref_Diag        : HRA.Issue_Relation.Reference_Diagnostic;
      Durable_Actual  : constant HRA.Actual_Admission.Actual_Transaction_Entry :=
        HRA.Actual_Admission.Transaction_At (Actuals, 2);
   begin
      if not HRA.Issue_Relation.Create_Relation_Event_Id
        ("rel-unknown-issue", Event_ID, Event_ID_Status)
        or else not HRA.Issue_Relation.Create_Realized_As
          (Event_ID,
           D ("2026-08-12"),
           HRA.Issues.Make_Issue_Id ("ISSUE-MISSING"),
           Durable_Actual.Source_Durable_Identity.Value,
           "",
           Event,
           Event_Status)
      then
         raise Program_Error with "failed to prepare unknown-Issue relation";
      end if;

      Assert
        (not HRA.Issue_Relation.Admit_References
           (Event, Issues, Actuals, Ref_Diag)
         and then Ref_Diag.Status = HRA.Issue_Relation.Unknown_Issue,
         "Realized_As rejects unknown Issue identity");
   end;

   declare
      Bad_ID_Status : HRA.Issue_Relation.Relation_Event_Id_Status;
      Bad_ID        : HRA.Issue_Relation.Relation_Event_Id;
      Good_ID_Status : HRA.Issue_Relation.Relation_Event_Id_Status;
      Good_ID       : HRA.Issue_Relation.Relation_Event_Id;
      Event_Status  : HRA.Issue_Relation.Create_Status;
      Event         : HRA.Issue_Relation.Relation_Event;
      Durable_Actual : constant HRA.Actual_Admission.Actual_Transaction_Entry :=
        HRA.Actual_Admission.Transaction_At (Actuals, 2);
   begin
      Assert
        (not HRA.Issue_Relation.Create_Relation_Event_Id
           ("bad id", Bad_ID, Bad_ID_Status)
         and then Bad_ID_Status =
           HRA.Issue_Relation.Relation_Event_Id_Contains_Whitespace,
         "Relation event identity rejects whitespace");

      if not HRA.Issue_Relation.Create_Relation_Event_Id
        ("rel-details", Good_ID, Good_ID_Status)
      then
         raise Program_Error with "failed to prepare details validation";
      end if;

      Assert
        (not HRA.Issue_Relation.Create_Realized_As
           (Good_ID,
            D ("2026-08-12"),
            HRA.Issues.Make_Issue_Id ("ISSUE-OPEN"),
            Durable_Actual.Source_Durable_Identity.Value,
            " leading-space",
            Event,
            Event_Status)
         and then Event_Status =
           HRA.Issue_Relation.Details_Have_Surrounding_Whitespace,
         "Relation details reject surrounding whitespace");
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
end Test_Issue_Relation;
