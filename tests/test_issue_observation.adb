with Ada.Command_Line;
with Ada.Containers;
with Ada.Text_IO;           use Ada.Text_IO;
with HRA.Dates;             use HRA.Dates;
with HRA.Issue_Observation; use HRA.Issue_Observation;
with HRA.Issues;            use HRA.Issues;

procedure Test_Issue_Observation is
   use type Ada.Containers.Count_Type;

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
   Obs  : HRA.Issue_Observation.Observation;
begin
   Put_Line ("--- Testing Issue temporal observation ---");

   --  1. Empty inventory observation
   declare
      Source : constant String := Canonical_Header & ASCII.LF;
   begin
      Assert (Admit_Issues_TSV (Source, Inv, Diag), "Admit empty issues TSV");
      Obs := Observe (Inv, D ("2026-08-19"));
      Assert
        (Obs.All_Observed.Is_Empty
         and then Obs.Open_Issues.Is_Empty
         and then Obs.Resolved_Issues.Is_Empty
         and then Obs.Dropped_Issues.Is_Empty
         and then Obs.Undetermined.Is_Empty,
         "Empty inventory produces empty observation vectors");
   end;

   --  2. Temporal coordinates & lifecycle projection
   --  TSV with 7 issues:
   --  1: Recorded 2026-08-25 (> 2026-08-19): Not visible as of 2026-08-19
   --  2: Recorded 2026-08-01, open, due 2026-08-25
   --  3: Recorded 2026-08-01, resolved, closed 2026-08-20 (> 2026-08-19), due 2026-08-25 (open as-of)
   --  4: Recorded 2026-08-01, dropped, closed 2026-08-20 (> 2026-08-19), due 2026-08-25 (open as-of)
   --  5: Recorded 2026-08-01, resolved, closed 2026-08-15 (<= 2026-08-19), due 2026-08-25 (closed as-of)
   --  6: Recorded 2026-08-01, dropped, closed 2026-08-10 (<= 2026-08-19), no due
   --  7: Recorded 2026-08-01, resolved, closed undetermined, due 2026-08-25
   declare
      Source : constant String :=
        Canonical_Header & ASCII.LF &
        "ISSUE-FUTURE" & ASCII.HT & "open" & ASCII.HT & "2026-08-25" & ASCII.HT &
        "2026-08-30" & ASCII.HT & "none" & ASCII.HT & "tax" & ASCII.HT &
        "Future Issue" & ASCII.HT & "" & ASCII.HT & "" & ASCII.HT & "" & ASCII.LF &
        "ISSUE-OPEN" & ASCII.HT & "open" & ASCII.HT & "2026-08-01" & ASCII.HT &
        "2026-08-25" & ASCII.HT & "none" & ASCII.HT & "bill" & ASCII.HT &
        "Open Bill" & ASCII.HT & "5000" & ASCII.HT & "JPY" & ASCII.HT & "" & ASCII.LF &
        "ISSUE-RES-LATER" & ASCII.HT & "resolved" & ASCII.HT & "2026-08-01" & ASCII.HT &
        "2026-08-25" & ASCII.HT & "2026-08-20" & ASCII.HT & "bill" & ASCII.HT &
        "Resolved Later" & ASCII.HT & "" & ASCII.HT & "" & ASCII.HT & "" & ASCII.LF &
        "ISSUE-DROP-LATER" & ASCII.HT & "dropped" & ASCII.HT & "2026-08-01" & ASCII.HT &
        "2026-08-25" & ASCII.HT & "2026-08-20" & ASCII.HT & "misc" & ASCII.HT &
        "Dropped Later" & ASCII.HT & "" & ASCII.HT & "" & ASCII.HT & "" & ASCII.LF &
        "ISSUE-RES-EARLIER" & ASCII.HT & "resolved" & ASCII.HT & "2026-08-01" & ASCII.HT &
        "2026-08-25" & ASCII.HT & "2026-08-15" & ASCII.HT & "bill" & ASCII.HT &
        "Resolved Earlier" & ASCII.HT & "" & ASCII.HT & "" & ASCII.HT & "" & ASCII.LF &
        "ISSUE-DROP-EARLIER" & ASCII.HT & "dropped" & ASCII.HT & "2026-08-01" & ASCII.HT &
        "none" & ASCII.HT & "2026-08-10" & ASCII.HT & "misc" & ASCII.HT &
        "Dropped Earlier" & ASCII.HT & "" & ASCII.HT & "" & ASCII.HT & "" & ASCII.LF &
        "ISSUE-RES-UNDET" & ASCII.HT & "resolved" & ASCII.HT & "2026-08-01" & ASCII.HT &
        "2026-08-25" & ASCII.HT & "undetermined" & ASCII.HT & "tax" & ASCII.HT &
        "Resolved Undetermined" & ASCII.HT & "" & ASCII.HT & "" & ASCII.HT & "" & ASCII.LF;
   begin
      Assert (Admit_Issues_TSV (Source, Inv, Diag), "Admit 7 mixed lifecycle issues");
      Obs := Observe (Inv, D ("2026-08-19"));

      --  Future recorded issue is not visible
      Assert (Obs.All_Observed.Length = 6, "6 issues visible as of 2026-08-19 (1 future excluded)");

      --  Open issues vector: ISSUE-OPEN, ISSUE-RES-LATER, ISSUE-DROP-LATER
      Assert (Obs.Open_Issues.Length = 3, "3 issues open as of 2026-08-19");
      Assert
        (Text (Obs.Open_Issues.Element (1).Issue.ID) = "ISSUE-OPEN"
         and then Obs.Open_Issues.Element (1).Status_As_Of = Open,
         "ISSUE-OPEN is Open as-of 2026-08-19");
      Assert
        (Text (Obs.Open_Issues.Element (2).Issue.ID) = "ISSUE-RES-LATER"
         and then Obs.Open_Issues.Element (2).Status_As_Of = Open,
         "ISSUE-RES-LATER (closed 2026-08-20) is Open as-of 2026-08-19");
      Assert
        (Text (Obs.Open_Issues.Element (3).Issue.ID) = "ISSUE-DROP-LATER"
         and then Obs.Open_Issues.Element (3).Status_As_Of = Open,
         "ISSUE-DROP-LATER (closed 2026-08-20) is Open as-of 2026-08-19");

      --  Resolved as-of: ISSUE-RES-EARLIER
      Assert (Obs.Resolved_Issues.Length = 1, "1 issue resolved as of 2026-08-19");
      Assert
        (Text (Obs.Resolved_Issues.Element (1).Issue.ID) = "ISSUE-RES-EARLIER"
         and then Obs.Resolved_Issues.Element (1).Status_As_Of = Resolved,
         "ISSUE-RES-EARLIER is Resolved as-of 2026-08-19");

      --  Dropped as-of: ISSUE-DROP-EARLIER
      Assert (Obs.Dropped_Issues.Length = 1, "1 issue dropped as of 2026-08-19");
      Assert
        (Text (Obs.Dropped_Issues.Element (1).Issue.ID) = "ISSUE-DROP-EARLIER"
         and then Obs.Dropped_Issues.Element (1).Status_As_Of = Dropped,
         "ISSUE-DROP-EARLIER is Dropped as-of 2026-08-19");

      --  Undetermined: ISSUE-RES-UNDET
      Assert (Obs.Undetermined.Length = 1, "1 issue undetermined closure as of 2026-08-19");
      Assert
        (Text (Obs.Undetermined.Element (1).Issue.ID) = "ISSUE-RES-UNDET"
         and then Obs.Undetermined.Element (1).Status_As_Of = Closure_Undetermined,
         "ISSUE-RES-UNDET retains Closure_Undetermined as-of 2026-08-19");

      --  Due_Issues_On for 2026-08-25: returns the 3 open-as-of issues due on that day
      declare
         Dues : constant Observed_Issue_Vectors.Vector :=
           Due_Issues_On (Obs, D ("2026-08-25"));
      begin
         Assert (Dues.Length = 3, "3 open-as-of issues due on 2026-08-25");
      end;

      --  Due_Issues_On for another day (2026-08-26): 0
      declare
         Dues : constant Observed_Issue_Vectors.Vector :=
           Due_Issues_On (Obs, D ("2026-08-26"));
      begin
         Assert (Dues.Is_Empty, "0 issues due on 2026-08-26");
      end;

      --  Has_Undetermined_Due_On for 2026-08-25: True (ISSUE-RES-UNDET has due 2026-08-25)
      Assert
        (Has_Undetermined_Due_On (Obs, D ("2026-08-25")),
         "Has_Undetermined_Due_On is True for 2026-08-25");

      --  Has_Undetermined_Due_On for 2026-08-26: False
      Assert
        (not Has_Undetermined_Due_On (Obs, D ("2026-08-26")),
         "Has_Undetermined_Due_On is False for 2026-08-26");
   end;

   --  3. Observation at later horizon (2026-08-26)
   --  Now ISSUE-FUTURE is visible, ISSUE-RES-LATER is resolved, ISSUE-DROP-LATER is dropped.
   declare
      Obs_Later : constant HRA.Issue_Observation.Observation :=
        Observe (Inv, D ("2026-08-26"));
   begin
      Assert (Obs_Later.All_Observed.Length = 7, "All 7 issues visible as of 2026-08-26");
      Assert (Obs_Later.Open_Issues.Length = 2, "2 issues open as of 2026-08-26 (ISSUE-FUTURE and ISSUE-OPEN)");
      Assert (Obs_Later.Resolved_Issues.Length = 2, "2 issues resolved as of 2026-08-26");
      Assert (Obs_Later.Dropped_Issues.Length = 2, "2 issues dropped as of 2026-08-26");
      Assert (Obs_Later.Undetermined.Length = 1, "1 issue undetermined closure as of 2026-08-26");
   end;

   Put_Line ("--------------------------------------------------");
   Put_Line ("Summary: Passed =" & Natural'Image (Passed_Count) &
             ", Failed =" & Natural'Image (Failed_Count));
   if Failed_Count > 0 then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Test_Issue_Observation;
