with Ada.Command_Line;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO; use Ada.Text_IO;
with HRA.Account;
with HRA.Actual_Admission;
with HRA.Actual_Candidate;
with HRA.Dates;
with HRA.Ledger;
with HRA.Money;

procedure Test_Actual_Candidate is
   use type HRA.Actual_Candidate.Candidate_Status;

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

   ID        : constant HRA.Actual_Admission.Actual_Id := Actual_ID ("chair-actual");
   Candidate : HRA.Actual_Candidate.Candidate_Block;
   Diag      : HRA.Actual_Candidate.Candidate_Diagnostic;

begin
   Put_Line ("--- Testing Actual source candidate ---");

   declare
      Tx : constant HRA.Ledger.Transaction := Balanced_Transaction;
      Expected : constant String :=
        "2026-08-20 Chair" & ASCII.LF &
        "    ; event-id: chair-actual" & ASCII.LF &
        "    assets:cash" & ASCII.HT & "-20000 JPY" & ASCII.LF &
        "    expenses:household" & ASCII.HT & "20000 JPY" & ASCII.LF;
   begin
      Assert
        (HRA.Actual_Candidate.Prepare (Tx, ID, Candidate, Diag),
         "Balanced transaction prepares a source-durable Actual block");
      Assert
        (HRA.Actual_Candidate.Text (Candidate) = Expected,
         "Candidate uses one canonical event-id metadata and exact posting order");
   end;

   declare
      JPY   : constant HRA.Money.Commodity := HRA.Money.Make_Commodity ("JPY");
      Posts : HRA.Ledger.Posting_Vectors.Vector;
      Tx    : HRA.Ledger.Transaction := Balanced_Transaction;
   begin
      Posts.Append
        (HRA.Ledger.Make_Posting
           (HRA.Account.Make_Account ("expenses:household"),
            HRA.Money.Make_Amount (JPY, 100.0)));
      Tx.Postings := Posts;
      Assert
        (not HRA.Actual_Candidate.Prepare (Tx, ID, Candidate, Diag)
           and then Diag.Status = HRA.Actual_Candidate.Unbalanced_Transaction,
         "Unbalanced typed transaction is rejected before rendering");
   end;

   declare
      Tx : HRA.Ledger.Transaction := Balanced_Transaction;
   begin
      Tx.Event_ID := To_Unbounded_String ("already-owned");
      Assert
        (not HRA.Actual_Candidate.Prepare (Tx, ID, Candidate, Diag)
           and then Diag.Status =
             HRA.Actual_Candidate.Transaction_Already_Owns_Identity,
         "Transaction cannot smuggle a second source identity owner");
   end;

   declare
      Tx : HRA.Ledger.Transaction := Balanced_Transaction;
   begin
      Tx.Code_Or_Payee := To_Unbounded_String ("Chair" & ASCII.LF & "Injected");
      Assert
        (not HRA.Actual_Candidate.Prepare (Tx, ID, Candidate, Diag)
           and then Diag.Status =
             HRA.Actual_Candidate.Description_Contains_Line_Break,
         "Description line break cannot inject additional Journal source");
   end;

   declare
      Tx : HRA.Ledger.Transaction := Balanced_Transaction;
      P  : HRA.Ledger.Posting := Tx.Postings.Element (1);
   begin
      P.Memo :=
        (Present => True,
         Text    => To_Unbounded_String ("cash leg memo"));
      Tx.Postings.Replace_Element (1, P);
      Assert
        (not HRA.Actual_Candidate.Prepare (Tx, ID, Candidate, Diag)
           and then Diag.Status =
             HRA.Actual_Candidate.Posting_Memo_Not_Representable,
         "Posting memo is rejected rather than silently lost");
   end;

   Put_Line
     ("Summary: Passed =" & Natural'Image (Passed_Count) &
      ", Failed =" & Natural'Image (Failed_Count));

   if Failed_Count > 0 then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Test_Actual_Candidate;
