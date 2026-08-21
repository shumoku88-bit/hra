with Ada.Command_Line;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO; use Ada.Text_IO;
with HRA.Dates;
with HRA.Issue_Close;
with HRA.Issues;

procedure Test_Issue_Close is
   use type HRA.Dates.Date;
   use type HRA.Issue_Close.Close_Status;
   use type HRA.Issues.Admission_Status;
   use type HRA.Issues.Issue_Closed_Kind;
   use type HRA.Issues.Issue_Status;

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

   Header : constant String :=
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

   Open_Row : constant String :=
     "ISSUE-CHAIR" & ASCII.HT &
     "open" & ASCII.HT &
     "2026-08-10" & ASCII.HT &
     "2026-08-30" & ASCII.HT &
     "none" & ASCII.HT &
     "purchase" & ASCII.HT &
     "Chair" & ASCII.HT &
     "20000" & ASCII.HT &
     "JPY" & ASCII.HT &
     "compare two models";

   Closed_Row : constant String :=
     "ISSUE-OLD" & ASCII.HT &
     "resolved" & ASCII.HT &
     "2026-08-01" & ASCII.HT &
     "none" & ASCII.HT &
     "2026-08-05" & ASCII.HT &
     "purchase" & ASCII.HT &
     "Old item" & ASCII.HT &
     "" & ASCII.HT &
     "" & ASCII.HT &
     "already finished";

   Source : constant String :=
     Header & ASCII.CR & ASCII.LF &
     Open_Row & ASCII.CR & ASCII.LF &
     Closed_Row;

   Chair_ID : constant HRA.Issues.Issue_Id := HRA.Issues.Make_Issue_Id ("ISSUE-CHAIR");
   Old_ID   : constant HRA.Issues.Issue_Id := HRA.Issues.Make_Issue_Id ("ISSUE-OLD");
   Missing_ID : constant HRA.Issues.Issue_Id := HRA.Issues.Make_Issue_Id ("ISSUE-MISSING");

   Candidate : HRA.Issue_Close.Candidate_Source;
   Diag      : HRA.Issue_Close.Close_Diagnostic;

begin
   Put_Line ("--- Testing pure Issue close candidate ---");

   declare
      Expected : constant String :=
        Header & ASCII.CR & ASCII.LF &
        "ISSUE-CHAIR" & ASCII.HT &
        "resolved" & ASCII.HT &
        "2026-08-10" & ASCII.HT &
        "2026-08-30" & ASCII.HT &
        "2026-08-20" & ASCII.HT &
        "purchase" & ASCII.HT &
        "Chair" & ASCII.HT &
        "20000" & ASCII.HT &
        "JPY" & ASCII.HT &
        "compare two models" & ASCII.CR & ASCII.LF &
        Closed_Row;
      Inventory : HRA.Issues.Issues_Inventory;
      I_Diag    : HRA.Issues.Admission_Diagnostic;
   begin
      Assert
        (HRA.Issue_Close.Prepare_Close
           (Existing_Source => Source,
            Issue_ID        => Chair_ID,
            Disposition     => HRA.Issue_Close.Resolve_Issue,
            Closed_On       => D ("2026-08-20"),
            Candidate       => Candidate,
            Diag            => Diag),
         "Open Issue may prepare an explicit resolved candidate");

      Assert
        (HRA.Issue_Close.Text (Candidate) = Expected,
         "Only status and closed fields change while CRLF and other bytes remain");

      Assert
        (HRA.Issues.Admit_Issues_TSV
           (HRA.Issue_Close.Text (Candidate), Inventory, I_Diag)
           and then HRA.Issues.Count (Inventory) = 2
           and then HRA.Issues.Element (Inventory, 1).Status = HRA.Issues.Resolved
           and then HRA.Issues.Element (Inventory, 1).Closed.Kind = HRA.Issues.Closed_On
           and then HRA.Issues.Element (Inventory, 1).Closed.Closed_Date = D ("2026-08-20"),
         "Prepared candidate re-admits with explicit closure meaning");
   end;

   declare
      Inventory : HRA.Issues.Issues_Inventory;
      I_Diag    : HRA.Issues.Admission_Diagnostic;
   begin
      Assert
        (HRA.Issue_Close.Prepare_Close
           (Source,
            Chair_ID,
            HRA.Issue_Close.Drop_Issue,
            D ("2026-08-21"),
            Candidate,
            Diag)
           and then HRA.Issues.Admit_Issues_TSV
             (HRA.Issue_Close.Text (Candidate), Inventory, I_Diag)
           and then HRA.Issues.Element (Inventory, 1).Status = HRA.Issues.Dropped,
         "Drop is a distinct explicit close disposition");
   end;

   Assert
     (not HRA.Issue_Close.Prepare_Close
        (Source,
         Missing_ID,
         HRA.Issue_Close.Resolve_Issue,
         D ("2026-08-20"),
         Candidate,
         Diag)
        and then Diag.Status = HRA.Issue_Close.Issue_Not_Found,
      "Unknown Issue identity fails closed");

   Assert
     (not HRA.Issue_Close.Prepare_Close
        (Source,
         Old_ID,
         HRA.Issue_Close.Resolve_Issue,
         D ("2026-08-20"),
         Candidate,
         Diag)
        and then Diag.Status = HRA.Issue_Close.Issue_Not_Open,
      "Already closed Issue cannot be closed again");

   Assert
     (not HRA.Issue_Close.Prepare_Close
        (Source,
         Chair_ID,
         HRA.Issue_Close.Resolve_Issue,
         D ("2026-08-09"),
         Candidate,
         Diag)
        and then Diag.Status = HRA.Issue_Close.Close_Before_Recorded,
      "Close date before Issue recorded date is rejected");

   Assert
     (not HRA.Issue_Close.Prepare_Close
        ("wrong-header" & ASCII.LF,
         Chair_ID,
         HRA.Issue_Close.Resolve_Issue,
         D ("2026-08-20"),
         Candidate,
         Diag)
        and then Diag.Status = HRA.Issue_Close.Source_Admission_Failed
        and then Diag.Source.Status = HRA.Issues.Invalid_Header,
      "Invalid current source remains distinguishable from close policy failure");

   Put_Line
     ("Summary: Passed =" & Natural'Image (Passed_Count) &
      ", Failed =" & Natural'Image (Failed_Count));

   if Failed_Count > 0 then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Test_Issue_Close;
