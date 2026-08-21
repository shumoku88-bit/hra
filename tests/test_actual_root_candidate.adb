with Ada.Command_Line;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO; use Ada.Text_IO;
with HRA.Account;
with HRA.Actual_Admission;
with HRA.Actual_Candidate;
with HRA.Actual_Root_Candidate;
with HRA.Dates;
with HRA.Journal;
with HRA.Ledger;
with HRA.Money;

procedure Test_Actual_Root_Candidate is
   use type HRA.Actual_Root_Candidate.Candidate_Status;

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

   function Actual_ID (Value : String) return HRA.Actual_Admission.Actual_Id is
      Result : HRA.Actual_Admission.Actual_Id;
      Status : HRA.Actual_Admission.Actual_Id_Status;
   begin
      if not HRA.Actual_Admission.Create_Actual_Id (Value, Result, Status) then
         raise Program_Error with "invalid test Actual id: " & Value;
      end if;
      return Result;
   end Actual_ID;

   function Balanced_Transaction return HRA.Ledger.Transaction is
      Posts  : HRA.Ledger.Posting_Vectors.Vector;
      Tx     : HRA.Ledger.Transaction;
      Status : HRA.Ledger.Transaction_Error;
      JPY    : constant HRA.Money.Commodity := HRA.Money.Make_Commodity ("JPY");
   begin
      Posts.Append
        (HRA.Ledger.Make_Posting
           (HRA.Account.Make_Account ("assets:cash"),
            HRA.Money.Make_Amount (JPY, -20_000.0)));
      Posts.Append
        (HRA.Ledger.Make_Posting
           (HRA.Account.Make_Account ("expenses:household"),
            HRA.Money.Make_Amount (JPY, 20_000.0)));

      if not HRA.Ledger.Create_Transaction
        (D ("2026-08-20"), "Chair", Posts, Tx, Status)
      then
         raise Program_Error with "failed to create balanced test transaction";
      end if;
      return Tx;
   end Balanced_Transaction;

   Block      : HRA.Actual_Candidate.Candidate_Block;
   Block_Diag : HRA.Actual_Candidate.Candidate_Diagnostic;
   Candidate  : HRA.Actual_Root_Candidate.Candidate_Root;
   Diag       : HRA.Actual_Root_Candidate.Candidate_Diagnostic;

   Root_Path : constant String := "/household/actual.journal";

begin
   Put_Line ("--- Testing pure Actual root source candidate ---");

   Assert
     (HRA.Actual_Candidate.Prepare
        (Balanced_Transaction,
         Actual_ID ("chair-actual"),
         Block,
         Block_Diag),
      "Setup prepares one qualified Actual block");

   Assert
     (HRA.Actual_Root_Candidate.Prepare
        (Root_Path, "", Block, Candidate, Diag)
      and then HRA.Actual_Root_Candidate.Text (Candidate) =
        HRA.Actual_Candidate.Text (Block),
      "Empty root becomes exactly the qualified Actual block");

   declare
      Existing : constant String :=
        "; root bytes stay here" & ASCII.CR & ASCII.LF &
        "include definitely-missing-child.journal" & ASCII.CR & ASCII.LF &
        "2026-08-19 Existing" & ASCII.CR & ASCII.LF &
        "    assets:cash" & ASCII.HT & "-100 JPY" & ASCII.CR & ASCII.LF &
        "    expenses:household" & ASCII.HT & "100 JPY";
      Expected : constant String :=
        Existing & ASCII.LF & HRA.Actual_Candidate.Text (Block);
      Parsed   : HRA.Ledger.Ledger;
      Parse_Diag : HRA.Journal.Parse_Diagnostic;
   begin
      Assert
        (HRA.Actual_Root_Candidate.Prepare
           (Root_Path, Existing, Block, Candidate, Diag),
         "Root-local candidate does not resolve include paths");
      Assert
        (HRA.Actual_Root_Candidate.Text (Candidate) = Expected,
         "Existing CRLF root bytes are preserved and only one LF boundary is appended");
      Assert
        (HRA.Journal.Parse_Journal_Text
           (HRA.Actual_Root_Candidate.Text (Candidate),
            Root_Path,
            Parsed,
            Parse_Diag)
         and then Natural (Parsed.Transactions.Length) = 2
         and then To_String (Parsed.Transactions.Element (2).Event_ID) =
           "chair-actual",
         "Complete root candidate retains existing direct meaning and appended durable identity");
   end;

   declare
      Existing_With_LF : constant String :=
        "; include remains unresolved here" & ASCII.LF &
        "include another-missing-child.journal" & ASCII.LF;
      Expected : constant String :=
        Existing_With_LF & HRA.Actual_Candidate.Text (Block);
   begin
      Assert
        (HRA.Actual_Root_Candidate.Prepare
           (Root_Path, Existing_With_LF, Block, Candidate, Diag)
         and then HRA.Actual_Root_Candidate.Text (Candidate) = Expected,
         "Trailing LF is reused rather than inventing an extra blank line");
   end;

   declare
      Invalid_Root : constant String :=
        "2026-08-19 Broken" & ASCII.LF &
        "    assets:cash" & ASCII.HT & "-100 JPY" & ASCII.LF &
        "    expenses:household" & ASCII.HT & "50 JPY" & ASCII.LF;
   begin
      Assert
        (not HRA.Actual_Root_Candidate.Prepare
           (Root_Path, Invalid_Root, Block, Candidate, Diag)
         and then Diag.Status =
           HRA.Actual_Root_Candidate.Existing_Root_Journal_Admission_Failed,
         "Invalid existing root is rejected before candidate placement");
   end;

   Put_Line
     ("Summary: Passed =" & Natural'Image (Passed_Count) &
      ", Failed =" & Natural'Image (Failed_Count));

   if Failed_Count > 0 then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   else
      Put_Line ("RESULT: SUCCESS");
   end if;
end Test_Actual_Root_Candidate;
