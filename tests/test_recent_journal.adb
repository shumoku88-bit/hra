with Ada.Strings.Fixed;     use Ada.Strings.Fixed;
with Ada.Text_IO;           use Ada.Text_IO;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA.Actual_Admission;
with HRA.Dates;
with HRA.Journal;       use HRA.Journal;
with HRA.Journal_Evidence;
with HRA.Ledger;
with HRA.Recent_Journal;
with HRA.Recent_Journal_Render;
with HRA.Terminal_UTF8;

procedure Test_Recent_Journal is
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

   function D (S : String) return HRA.Dates.Date is
      Val    : HRA.Dates.Date;
      Status : HRA.Dates.Date_Status;
   begin
      if not HRA.Dates.Parse (S, Val, Status) then
         raise Program_Error with "Invalid date in test: " & S;
      end if;
      return Val;
   end D;

   Journal_Text : constant String :=
     "2026-06-10 First" & ASCII.LF &
     "    expenses:food       100 JPY" & ASCII.LF &
     "    assets:cash        -100 JPY" & ASCII.LF &
     "" & ASCII.LF &
     "2026-07-20 Second" & ASCII.LF &
     "    ; event-id: actual-second" & ASCII.LF &
     "    expenses:food       200 JPY" & ASCII.LF &
     "    assets:cash        -200 JPY" & ASCII.LF &
     "" & ASCII.LF &
     "2026-09-01 Future" & ASCII.LF &
     "    expenses:food       300 JPY" & ASCII.LF &
     "    assets:cash        -300 JPY" & ASCII.LF;

   L             : HRA.Ledger.Ledger;
   Parse_Error   : Unbounded_String;
   Evidence      : HRA.Journal_Evidence.Journal_Evidence;
   Evidence_Diag : HRA.Journal_Evidence.Evidence_Diagnostic;
   Actual        : HRA.Actual_Admission.Actual_Observation;
   Actual_Diag   : HRA.Actual_Admission.Admission_Diagnostic;
   Result        : HRA.Recent_Journal.Observation;

begin
   HRA.Terminal_UTF8.Initialize;
   Put_Line ("--- Testing HRA.Recent_Journal ---");

   Assert
     (Parse_Journal_Text (Journal_Text, L, Parse_Error),
      "Setup: parse Actual Journal");
   Assert
     (HRA.Journal_Evidence.Extract
        (Journal_Text,
         "fixtures/actual.journal",
         L,
         Evidence,
         Evidence_Diag),
      "Setup: retain aligned Actual source evidence");

   Assert
     (HRA.Actual_Admission.Admit
        (L, Evidence, Actual, Actual_Diag),
      "Setup: admit one aligned Actual observation");

   Result := HRA.Recent_Journal.Observe
     (Actual, D ("2026-08-15"), 2);
   Assert
     (Natural (Result.Entries.Length) = 2,
      "Recent Journal returns requested count when available");

   if Natural (Result.Entries.Length) = 2 then
      declare
         Newest : constant HRA.Recent_Journal.Recent_Entry :=
           Result.Entries.Element (1);
         Older  : constant HRA.Recent_Journal.Recent_Entry :=
           Result.Entries.Element (2);
         Rendered : constant String :=
           HRA.Recent_Journal_Render.Render (Result);
      begin
         Assert
           (HRA.Dates.Image (Newest.Value.Date) = "2026-07-20"
              and then HRA.Dates.Image (Older.Value.Date) = "2026-06-10",
            "Selection excludes future Actual and returns newest source entry first");
         Assert
           (Newest.Identity.Present
              and then HRA.Actual_Admission.Text (Newest.Identity.Value) =
                "actual-second"
              and then not Older.Identity.Present,
            "Selected entries preserve typed optional Actual identity");
         Assert
           (To_String (Newest.Source.Source_Path) = "fixtures/actual.journal"
              and then Newest.Source.Header_Line = 5,
            "Selected entry retains physical source path and header line");
         Assert
           (Index (Rendered, "2026-07-20 Second") > 0
              and then Index (Rendered, "; event-id: actual-second") > 0
              and then Index (Rendered, "2026-06-10 First") > 0
              and then Index (Rendered, "2026-09-01 Future") = 0,
            "Renderer consumes typed identity from the bounded Actual result");
      end;
   end if;

   Put_Line
     (Natural'Image (Passed_Count) & " passed, " &
      Natural'Image (Failed_Count) & " failed");

   if Failed_Count > 0 then
      raise Program_Error with "Recent Journal tests failed";
   end if;
end Test_Recent_Journal;
