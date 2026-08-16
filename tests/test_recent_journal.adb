with Ada.Strings.Fixed;     use Ada.Strings.Fixed;
with Ada.Text_IO;           use Ada.Text_IO;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with ALedger.Journal;       use ALedger.Journal;
with ALedger.Journal_Evidence;
with ALedger.Ledger;
with ALedger.Recent_Journal;
with ALedger.Recent_Journal_Render;

procedure Test_Recent_Journal is
   use type ALedger.Recent_Journal.Observe_Status;

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

   Journal_Text : constant String :=
     "2026-06-10 First" & ASCII.LF &
     "    expenses:food       100 JPY" & ASCII.LF &
     "    assets:cash        -100 JPY" & ASCII.LF &
     "" & ASCII.LF &
     "2026-07-20 Second" & ASCII.LF &
     "    expenses:food       200 JPY" & ASCII.LF &
     "    assets:cash        -200 JPY" & ASCII.LF &
     "" & ASCII.LF &
     "2026-09-01 Future" & ASCII.LF &
     "    expenses:food       300 JPY" & ASCII.LF &
     "    assets:cash        -300 JPY" & ASCII.LF;

   L             : ALedger.Ledger.Ledger;
   Parse_Error   : Unbounded_String;
   Evidence      : ALedger.Journal_Evidence.Journal_Evidence;
   Evidence_Diag : ALedger.Journal_Evidence.Evidence_Diagnostic;
   Result        : ALedger.Recent_Journal.Observation;
   Status        : ALedger.Recent_Journal.Observe_Status;

begin
   Put_Line ("--- Testing ALedger.Recent_Journal ---");

   Assert
     (Parse_Journal_Text (Journal_Text, L, Parse_Error),
      "Setup: parse Actual Journal");
   Assert
     (ALedger.Journal_Evidence.Extract
        (Journal_Text,
         "fixtures/actual.journal",
         L,
         Evidence,
         Evidence_Diag),
      "Setup: retain aligned Actual source evidence");

   Assert
     (ALedger.Recent_Journal.Observe
        (L, Evidence, "2026-08-15", 2, Result, Status),
      "Observe bounded Recent Journal");
   Assert
     (Status = ALedger.Recent_Journal.Success
        and then Natural (Result.Entries.Length) = 2,
      "Recent Journal returns requested count when available");

   if Natural (Result.Entries.Length) = 2 then
      declare
         Newest : constant ALedger.Recent_Journal.Entry :=
           Result.Entries.Element (1);
         Older  : constant ALedger.Recent_Journal.Entry :=
           Result.Entries.Element (2);
         Rendered : constant String :=
           ALedger.Recent_Journal_Render.Render (Result);
      begin
         Assert
           (To_String (Newest.Value.Date_Text) = "2026-07-20"
              and then To_String (Older.Value.Date_Text) = "2026-06-10",
            "Selection excludes future Actual and returns newest source entry first");
         Assert
           (To_String (Newest.Source.Source_Path) = "fixtures/actual.journal"
              and then Newest.Source.Header_Line = 5,
            "Selected entry retains physical source path and header line");
         Assert
           (Index (Rendered, "2026-07-20 Second") > 0
              and then Index (Rendered, "2026-06-10 First") > 0
              and then Index (Rendered, "2026-09-01 Future") = 0,
            "Renderer consumes bounded semantic result instead of raw Ledger");
      end;
   end if;

   declare
      Bad_Evidence : ALedger.Journal_Evidence.Journal_Evidence := Evidence;
   begin
      Bad_Evidence.Transactions.Delete_Last;
      Assert
        (not ALedger.Recent_Journal.Observe
           (L, Bad_Evidence, "2026-08-15", 2, Result, Status)
           and then Status = ALedger.Recent_Journal.Evidence_Count_Mismatch,
         "Reject Ledger/Evidence count drift");
   end;

   declare
      Bad_Evidence : ALedger.Journal_Evidence.Journal_Evidence := Evidence;
      Source       : ALedger.Journal_Evidence.Transaction_Source :=
        Bad_Evidence.Transactions.Element (1);
   begin
      Source.Description := To_Unbounded_String ("not First");
      Bad_Evidence.Transactions.Replace_Element (1, Source);
      Assert
        (not ALedger.Recent_Journal.Observe
           (L, Bad_Evidence, "2026-08-15", 2, Result, Status)
           and then Status = ALedger.Recent_Journal.Evidence_Alignment_Mismatch,
         "Reject Ledger/Evidence transaction alignment drift");
   end;

   Put_Line
     (Natural'Image (Passed_Count) & " passed, " &
      Natural'Image (Failed_Count) & " failed");

   if Failed_Count > 0 then
      raise Program_Error with "Recent Journal tests failed";
   end if;
end Test_Recent_Journal;
