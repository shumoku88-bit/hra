with Ada.Command_Line;
with Ada.Text_IO;           use Ada.Text_IO;
with Ada.Strings.Fixed;     use Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA.Dates;             use HRA.Dates;
with HRA.Money;             use HRA.Money;
with HRA.Issues;            use HRA.Issues;

procedure Test_Issues_Admission is
   use type HRA.Issues.Admission_Status;
   use type HRA.Issues.Issue_Status;
   use type HRA.Issues.Issue_Due_Kind;
   use type HRA.Issues.Issue_Closed_Kind;

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

   function D (Str : String) return HRA.Dates.Date is
      Val  : HRA.Dates.Date;
      Stat : HRA.Dates.Date_Status;
   begin
      if not HRA.Dates.Parse (Str, Val, Stat) then
         raise Program_Error with "invalid test date: " & Str;
      end if;
      return Val;
   end D;

   Canonical_Header : constant String :=
     "issue_id"   & ASCII.HT &
     "status"     & ASCII.HT &
     "date"       & ASCII.HT &
     "due"        & ASCII.HT &
     "closed"     & ASCII.HT &
     "category"   & ASCII.HT &
     "title"      & ASCII.HT &
     "amount"     & ASCII.HT &
     "currency"   & ASCII.HT &
     "details";

   Inv  : Issues_Inventory;
   Diag : Admission_Diagnostic;
begin
   Put_Line ("--- Testing typed Issue temporal admission ---");

   --  1. exact current 10-column header (empty inventory)
   Assert
     (Admit_Issues_TSV (Canonical_Header & ASCII.LF, Inv, Diag)
      and then Natural (Inv.Items.Length) = 0,
      "exact current 10-column header admits empty inventory");

   --  2. Open + Due_On + Amount present
   declare
      Source : constant String :=
        Canonical_Header & ASCII.LF &
        "ISSUE-1" & ASCII.HT & "open" & ASCII.HT & "2026-08-01" & ASCII.HT &
        "2026-08-15" & ASCII.HT & "none" & ASCII.HT & "taxes" & ASCII.HT &
        "Resident Tax" & ASCII.HT & "15000" & ASCII.HT & "JPY" & ASCII.HT &
        "city office payment" & ASCII.LF;
   begin
      Assert
        (Admit_Issues_TSV (Source, Inv, Diag)
         and then Natural (Inv.Items.Length) = 1
         and then Text (Inv.Items.Element (1).ID) = "ISSUE-1"
         and then Inv.Items.Element (1).Status = Open
         and then Inv.Items.Element (1).Recorded_On = D ("2026-08-01")
         and then Inv.Items.Element (1).Due.Kind = Due_On
         and then Inv.Items.Element (1).Due.Due_Date = D ("2026-08-15")
         and then Inv.Items.Element (1).Closed.Kind = Not_Closed
         and then Inv.Items.Element (1).Amt.Has_Amount
         and then Inv.Items.Element (1).Amt.Value.Val = 15000.0
         and then Code (Inv.Items.Element (1).Amt.Value.Comm) = "JPY"
         and then To_String (Inv.Items.Element (1).Category) = "taxes"
         and then To_String (Inv.Items.Element (1).Title) = "Resident Tax"
         and then To_String (Inv.Items.Element (1).Details) = "city office payment",
         "Open + Due_On + optional Amount present admits full typed facts");
   end;

   --  3. No_Due_Date
   declare
      Source : constant String :=
        Canonical_Header & ASCII.LF &
        "ISSUE-2" & ASCII.HT & "open" & ASCII.HT & "2026-08-02" & ASCII.HT &
        "none" & ASCII.HT & "none" & ASCII.HT & "misc" & ASCII.HT &
        "No due issue" & ASCII.HT & "" & ASCII.HT & "" & ASCII.HT &
        "" & ASCII.LF;
   begin
      Assert
        (Admit_Issues_TSV (Source, Inv, Diag)
         and then Natural (Inv.Items.Length) = 1
         and then Inv.Items.Element (1).Due.Kind = No_Due_Date
         and then not Inv.Items.Element (1).Amt.Has_Amount,
         "No_Due_Date admits due=none and optional amount absent");
   end;

   --  4. Due_Undetermined
   declare
      Source : constant String :=
        Canonical_Header & ASCII.LF &
        "ISSUE-3" & ASCII.HT & "open" & ASCII.HT & "2026-08-03" & ASCII.HT &
        "undetermined" & ASCII.HT & "none" & ASCII.HT & "misc" & ASCII.HT &
        "Undetermined due" & ASCII.HT & "" & ASCII.HT & "" & ASCII.HT &
        "" & ASCII.LF;
   begin
      Assert
        (Admit_Issues_TSV (Source, Inv, Diag)
         and then Natural (Inv.Items.Length) = 1
         and then Inv.Items.Element (1).Due.Kind = Due_Undetermined,
         "Due_Undetermined admits due=undetermined");
   end;

   --  5. Resolved + Closed_On
   declare
      Source : constant String :=
        Canonical_Header & ASCII.LF &
        "ISSUE-4" & ASCII.HT & "resolved" & ASCII.HT & "2026-08-01" & ASCII.HT &
        "2026-08-05" & ASCII.HT & "2026-08-04" & ASCII.HT & "repairs" & ASCII.HT &
        "Fixed lock" & ASCII.HT & "5000" & ASCII.HT & "JPY" & ASCII.HT &
        "resolved cleanly" & ASCII.LF;
   begin
      Assert
        (Admit_Issues_TSV (Source, Inv, Diag)
         and then Natural (Inv.Items.Length) = 1
         and then Inv.Items.Element (1).Status = Resolved
         and then Inv.Items.Element (1).Closed.Kind = Closed_On
         and then Inv.Items.Element (1).Closed.Closed_Date = D ("2026-08-04"),
         "Resolved + Closed_On admits closed date >= recorded date");
   end;

   --  6. historical Closed_Undetermined
   declare
      Source : constant String :=
        Canonical_Header & ASCII.LF &
        "ISSUE-5" & ASCII.HT & "resolved" & ASCII.HT & "2026-08-01" & ASCII.HT &
        "none" & ASCII.HT & "undetermined" & ASCII.HT & "hist" & ASCII.HT &
        "Historical resolved issue" & ASCII.HT & "" & ASCII.HT & "" & ASCII.HT &
        "old closure" & ASCII.LF;
   begin
      Assert
        (Admit_Issues_TSV (Source, Inv, Diag)
         and then Natural (Inv.Items.Length) = 1
         and then Inv.Items.Element (1).Status = Resolved
         and then Inv.Items.Element (1).Closed.Kind = Closed_Undetermined,
         "historical Closed_Undetermined admits closed=undetermined");
   end;

   --  7. Dropped + Closed_On
   declare
      Source : constant String :=
        Canonical_Header & ASCII.LF &
        "ISSUE-6" & ASCII.HT & "dropped" & ASCII.HT & "2026-08-01" & ASCII.HT &
        "none" & ASCII.HT & "2026-08-02" & ASCII.HT & "ideas" & ASCII.HT &
        "Dropped purchase" & ASCII.HT & "" & ASCII.HT & "" & ASCII.HT &
        "decided against" & ASCII.LF;
   begin
      Assert
        (Admit_Issues_TSV (Source, Inv, Diag)
         and then Natural (Inv.Items.Length) = 1
         and then Inv.Items.Element (1).Status = Dropped
         and then Inv.Items.Element (1).Closed.Kind = Closed_On
         and then Inv.Items.Element (1).Closed.Closed_Date = D ("2026-08-02"),
         "Dropped admits status=dropped with valid closure");
   end;

   --  8. duplicate Issue identity reject
   declare
      Source : constant String :=
        Canonical_Header & ASCII.LF &
        "DUP-1" & ASCII.HT & "open" & ASCII.HT & "2026-08-01" & ASCII.HT &
        "none" & ASCII.HT & "none" & ASCII.HT & "cat" & ASCII.HT &
        "First" & ASCII.HT & "" & ASCII.HT & "" & ASCII.HT & "" & ASCII.LF &
        "DUP-1" & ASCII.HT & "open" & ASCII.HT & "2026-08-02" & ASCII.HT &
        "none" & ASCII.HT & "none" & ASCII.HT & "cat" & ASCII.HT &
        "Second" & ASCII.HT & "" & ASCII.HT & "" & ASCII.HT & "" & ASCII.LF;
   begin
      Assert
        (not Admit_Issues_TSV (Source, Inv, Diag)
         and then Diag.Status = Duplicate_Issue_Id
         and then Diag.Line_Number = 3
         and then To_String (Diag.Issue_ID) = "DUP-1",
         "duplicate Issue identity is rejected with line number and ID");
   end;

   --  9. unknown status reject
   declare
      Source : constant String :=
        Canonical_Header & ASCII.LF &
        "ISS-1" & ASCII.HT & "in_progress" & ASCII.HT & "2026-08-01" & ASCII.HT &
        "none" & ASCII.HT & "none" & ASCII.HT & "cat" & ASCII.HT &
        "Unknown stat" & ASCII.HT & "" & ASCII.HT & "" & ASCII.HT & "" & ASCII.LF;
   begin
      Assert
        (not Admit_Issues_TSV (Source, Inv, Diag)
         and then Diag.Status = Unknown_Status
         and then Diag.Line_Number = 2,
         "unknown status is rejected");
   end;

   --  10. invalid recorded date reject
   declare
      Source : constant String :=
        Canonical_Header & ASCII.LF &
        "ISS-2" & ASCII.HT & "open" & ASCII.HT & "2026-02-30" & ASCII.HT &
        "none" & ASCII.HT & "none" & ASCII.HT & "cat" & ASCII.HT &
        "Invalid rec date" & ASCII.HT & "" & ASCII.HT & "" & ASCII.HT & "" & ASCII.LF;
   begin
      Assert
        (not Admit_Issues_TSV (Source, Inv, Diag)
         and then Diag.Status = Invalid_Recorded_Date
         and then Diag.Line_Number = 2,
         "invalid recorded date is rejected");
   end;

   --  11. invalid due reject
   declare
      Source : constant String :=
        Canonical_Header & ASCII.LF &
        "ISS-3" & ASCII.HT & "open" & ASCII.HT & "2026-08-01" & ASCII.HT &
        "next-week" & ASCII.HT & "none" & ASCII.HT & "cat" & ASCII.HT &
        "Invalid due" & ASCII.HT & "" & ASCII.HT & "" & ASCII.HT & "" & ASCII.LF;
   begin
      Assert
        (not Admit_Issues_TSV (Source, Inv, Diag)
         and then Diag.Status = Invalid_Due_Date
         and then Diag.Line_Number = 2,
         "invalid due date is rejected");
   end;

   --  12. invalid closed reject
   declare
      Source : constant String :=
        Canonical_Header & ASCII.LF &
        "ISS-4" & ASCII.HT & "resolved" & ASCII.HT & "2026-08-01" & ASCII.HT &
        "none" & ASCII.HT & "2026-04-31" & ASCII.HT & "cat" & ASCII.HT &
        "Invalid closed" & ASCII.HT & "" & ASCII.HT & "" & ASCII.HT & "" & ASCII.LF;
   begin
      Assert
        (not Admit_Issues_TSV (Source, Inv, Diag)
         and then Diag.Status = Invalid_Closed_Date
         and then Diag.Line_Number = 2,
         "invalid closed date is rejected");
   end;

   --  13. closed-before-recorded reject
   declare
      Source : constant String :=
        Canonical_Header & ASCII.LF &
        "ISS-5" & ASCII.HT & "resolved" & ASCII.HT & "2026-08-10" & ASCII.HT &
        "none" & ASCII.HT & "2026-08-05" & ASCII.HT & "cat" & ASCII.HT &
        "Closed too early" & ASCII.HT & "" & ASCII.HT & "" & ASCII.HT & "" & ASCII.LF;
   begin
      Assert
        (not Admit_Issues_TSV (Source, Inv, Diag)
         and then Diag.Status = Closed_Before_Recorded
         and then Diag.Line_Number = 2,
         "closed date earlier than recorded date is rejected");
   end;

   --  14. Open + Closed_On reject
   declare
      Source : constant String :=
        Canonical_Header & ASCII.LF &
        "ISS-6" & ASCII.HT & "open" & ASCII.HT & "2026-08-01" & ASCII.HT &
        "none" & ASCII.HT & "2026-08-10" & ASCII.HT & "cat" & ASCII.HT &
        "Open with closed date" & ASCII.HT & "" & ASCII.HT & "" & ASCII.HT & "" & ASCII.LF;
   begin
      Assert
        (not Admit_Issues_TSV (Source, Inv, Diag)
         and then Diag.Status = Open_Issue_With_Closure
         and then Diag.Line_Number = 2,
         "Open issue with Closed_On is rejected");
   end;

   --  15. Open + Closed_Undetermined reject
   declare
      Source : constant String :=
        Canonical_Header & ASCII.LF &
        "ISS-7" & ASCII.HT & "open" & ASCII.HT & "2026-08-01" & ASCII.HT &
        "none" & ASCII.HT & "undetermined" & ASCII.HT & "cat" & ASCII.HT &
        "Open with undetermined closed" & ASCII.HT & "" & ASCII.HT & "" & ASCII.HT & "" & ASCII.LF;
   begin
      Assert
        (not Admit_Issues_TSV (Source, Inv, Diag)
         and then Diag.Status = Open_Issue_With_Closure
         and then Diag.Line_Number = 2,
         "Open issue with Closed_Undetermined is rejected");
   end;

   --  16. closed status + Not_Closed reject
   declare
      Source_Resolved : constant String :=
        Canonical_Header & ASCII.LF &
        "ISS-8" & ASCII.HT & "resolved" & ASCII.HT & "2026-08-01" & ASCII.HT &
        "none" & ASCII.HT & "none" & ASCII.HT & "cat" & ASCII.HT &
        "Resolved without closure" & ASCII.HT & "" & ASCII.HT & "" & ASCII.HT & "" & ASCII.LF;

      Source_Dropped : constant String :=
        Canonical_Header & ASCII.LF &
        "ISS-9" & ASCII.HT & "dropped" & ASCII.HT & "2026-08-01" & ASCII.HT &
        "none" & ASCII.HT & "none" & ASCII.HT & "cat" & ASCII.HT &
        "Dropped without closure" & ASCII.HT & "" & ASCII.HT & "" & ASCII.HT & "" & ASCII.LF;
   begin
      Assert
        (not Admit_Issues_TSV (Source_Resolved, Inv, Diag)
         and then Diag.Status = Closed_Issue_Without_Closure
         and then Diag.Line_Number = 2,
         "Resolved issue with Not_Closed is rejected");
      Assert
        (not Admit_Issues_TSV (Source_Dropped, Inv, Diag)
         and then Diag.Status = Closed_Issue_Without_Closure
         and then Diag.Line_Number = 2,
         "Dropped issue with Not_Closed is rejected");
   end;

   --  17. optional amount present
   declare
      Source : constant String :=
        Canonical_Header & ASCII.LF &
        "ISS-10" & ASCII.HT & "open" & ASCII.HT & "2026-08-01" & ASCII.HT &
        "none" & ASCII.HT & "none" & ASCII.HT & "cat" & ASCII.HT &
        "Amt test" & ASCII.HT & "123.45" & ASCII.HT & "USD" & ASCII.HT & "" & ASCII.LF;
   begin
      Assert
        (Admit_Issues_TSV (Source, Inv, Diag)
         and then Inv.Items.Element (1).Amt.Has_Amount
         and then Inv.Items.Element (1).Amt.Value.Val = 123.45
         and then Code (Inv.Items.Element (1).Amt.Value.Comm) = "USD",
         "optional amount present preserves exact quantity and commodity");
   end;

   --  18. optional amount absent
   declare
      Source : constant String :=
        Canonical_Header & ASCII.LF &
        "ISS-11" & ASCII.HT & "open" & ASCII.HT & "2026-08-01" & ASCII.HT &
        "none" & ASCII.HT & "none" & ASCII.HT & "cat" & ASCII.HT &
        "No amt" & ASCII.HT & "" & ASCII.HT & "" & ASCII.HT & "" & ASCII.LF;
   begin
      Assert
        (Admit_Issues_TSV (Source, Inv, Diag)
         and then not Inv.Items.Element (1).Amt.Has_Amount,
         "optional amount absent preserves blank amount/currency");
   end;

   --  19. amount/currency partial reject
   declare
      Source_Amt_Only : constant String :=
        Canonical_Header & ASCII.LF &
        "ISS-12" & ASCII.HT & "open" & ASCII.HT & "2026-08-01" & ASCII.HT &
        "none" & ASCII.HT & "none" & ASCII.HT & "cat" & ASCII.HT &
        "Partial" & ASCII.HT & "1000" & ASCII.HT & "" & ASCII.HT & "" & ASCII.LF;

      Source_Curr_Only : constant String :=
        Canonical_Header & ASCII.LF &
        "ISS-13" & ASCII.HT & "open" & ASCII.HT & "2026-08-01" & ASCII.HT &
        "none" & ASCII.HT & "none" & ASCII.HT & "cat" & ASCII.HT &
        "Partial" & ASCII.HT & "" & ASCII.HT & "JPY" & ASCII.HT & "" & ASCII.LF;
   begin
      Assert
        (not Admit_Issues_TSV (Source_Amt_Only, Inv, Diag)
         and then Diag.Status = Partial_Amount_Currency
         and then Diag.Line_Number = 2,
         "amount present without currency is rejected");
      Assert
        (not Admit_Issues_TSV (Source_Curr_Only, Inv, Diag)
         and then Diag.Status = Partial_Amount_Currency
         and then Diag.Line_Number = 2,
         "currency present without amount is rejected");
   end;

   --  20. invalid amount reject
   declare
      Source : constant String :=
        Canonical_Header & ASCII.LF &
        "ISS-14" & ASCII.HT & "open" & ASCII.HT & "2026-08-01" & ASCII.HT &
        "none" & ASCII.HT & "none" & ASCII.HT & "cat" & ASCII.HT &
        "Bad amt" & ASCII.HT & "not_a_number" & ASCII.HT & "JPY" & ASCII.HT & "" & ASCII.LF;
   begin
      Assert
        (not Admit_Issues_TSV (Source, Inv, Diag)
         and then Diag.Status = Invalid_Amount
         and then Diag.Line_Number = 2,
         "invalid amount quantity is rejected without fallback");
   end;

   --  21. invalid Commodity reject
   declare
      Source : constant String :=
        Canonical_Header & ASCII.LF &
        "ISS-15" & ASCII.HT & "open" & ASCII.HT & "2026-08-01" & ASCII.HT &
        "none" & ASCII.HT & "none" & ASCII.HT & "cat" & ASCII.HT &
        "Bad comm" & ASCII.HT & "100" & ASCII.HT & "BAD CODE" & ASCII.HT & "" & ASCII.LF;
   begin
      Assert
        (not Admit_Issues_TSV (Source, Inv, Diag)
         and then Diag.Status = Invalid_Commodity
         and then Diag.Line_Number = 2,
         "invalid commodity code is rejected without fallback");
   end;

   --  22. wrong column count / header reject
   declare
      Bad_Header : constant String :=
        "issue_id" & ASCII.HT & "status" & ASCII.LF;

      Too_Few_Cols : constant String :=
        Canonical_Header & ASCII.LF &
        "ISS-16" & ASCII.HT & "open" & ASCII.HT & "2026-08-01" & ASCII.HT &
        "none" & ASCII.HT & "none" & ASCII.LF;

      Too_Many_Cols : constant String :=
        Canonical_Header & ASCII.LF &
        "ISS-17" & ASCII.HT & "open" & ASCII.HT & "2026-08-01" & ASCII.HT &
        "none" & ASCII.HT & "none" & ASCII.HT & "cat" & ASCII.HT &
        "title" & ASCII.HT & "100" & ASCII.HT & "JPY" & ASCII.HT &
        "details" & ASCII.HT & "extra_col" & ASCII.LF;
   begin
      Assert
        (not Admit_Issues_TSV (Bad_Header, Inv, Diag)
         and then Diag.Status = Invalid_Header
         and then Diag.Line_Number = 1,
         "non-10-column header is rejected");
      Assert
        (not Admit_Issues_TSV (Too_Few_Cols, Inv, Diag)
         and then Diag.Status = Malformed_Column_Count
         and then Diag.Line_Number = 2,
         "row with fewer than 10 columns is rejected");
      Assert
        (not Admit_Issues_TSV (Too_Many_Cols, Inv, Diag)
         and then Diag.Status = Malformed_Column_Count
         and then Diag.Line_Number = 2,
         "row with more than 10 columns is rejected");
   end;

   --  23. Open_Issues excludes Resolved/Dropped
   declare
      Source : constant String :=
        Canonical_Header & ASCII.LF &
        "OPEN-1" & ASCII.HT & "open" & ASCII.HT & "2026-08-01" & ASCII.HT &
        "none" & ASCII.HT & "none" & ASCII.HT & "cat" & ASCII.HT &
        "Open 1" & ASCII.HT & "" & ASCII.HT & "" & ASCII.HT & "" & ASCII.LF &
        "RES-1"  & ASCII.HT & "resolved" & ASCII.HT & "2026-08-01" & ASCII.HT &
        "none" & ASCII.HT & "2026-08-03" & ASCII.HT & "cat" & ASCII.HT &
        "Res 1" & ASCII.HT & "" & ASCII.HT & "" & ASCII.HT & "" & ASCII.LF &
        "OPEN-2" & ASCII.HT & "open" & ASCII.HT & "2026-08-02" & ASCII.HT &
        "2026-08-10" & ASCII.HT & "none" & ASCII.HT & "cat" & ASCII.HT &
        "Open 2" & ASCII.HT & "" & ASCII.HT & "" & ASCII.HT & "" & ASCII.LF &
        "DROP-1" & ASCII.HT & "dropped" & ASCII.HT & "2026-08-01" & ASCII.HT &
        "none" & ASCII.HT & "2026-08-04" & ASCII.HT & "cat" & ASCII.HT &
        "Drop 1" & ASCII.HT & "" & ASCII.HT & "" & ASCII.HT & "" & ASCII.LF;
      Admit_OK : constant Boolean := Admit_Issues_TSV (Source, Inv, Diag);
      Opens    : Issue_Vectors.Vector;
   begin
      Assert (Admit_OK and then Natural (Inv.Items.Length) = 4, "Admit 4 mixed lifecycle issues");
      Opens := Open_Issues (Inv);
      Assert
        (Natural (Opens.Length) = 2
         and then Text (Opens.Element (1).ID) = "OPEN-1"
         and then Text (Opens.Element (2).ID) = "OPEN-2",
         "Open_Issues excludes Resolved and Dropped issues");
   end;

   --  24. Diagnostics safety check (safe short diagnostic without private content)
   declare
      Source : constant String :=
        Canonical_Header & ASCII.LF &
        "SEC-1" & ASCII.HT & "open" & ASCII.HT & "invalid-date" & ASCII.HT &
        "none" & ASCII.HT & "none" & ASCII.HT & "private-category" & ASCII.HT &
        "Super Secret Title" & ASCII.HT & "" & ASCII.HT & "" & ASCII.HT &
        "Confidential notes" & ASCII.LF;
   begin
      Assert
        (not Admit_Issues_TSV (Source, Inv, Diag)
         and then Diag.Status = Invalid_Recorded_Date
         and then Diag.Line_Number = 2
         and then To_String (Diag.Issue_ID) = "SEC-1"
         and then Index (To_String (Diag.Message), "Super Secret") = 0
         and then Index (To_String (Diag.Message), "Confidential") = 0,
         "Diagnostic message contains safe reason without echoing private fields");
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
end Test_Issues_Admission;
