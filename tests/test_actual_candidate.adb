with Ada.Command_Line;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO; use Ada.Text_IO;
with HRA.Account;
with HRA.Actual_Admission;
with HRA.Actual_Candidate;
with HRA.Dates;
with HRA.Journal;
with HRA.Journal_Evidence;
with HRA.Ledger;
with HRA.Money;

procedure Test_Actual_Candidate is
   use type HRA.Actual_Admission.Actual_Id;
   use type HRA.Actual_Candidate.Candidate_Status;
   use type HRA.Ledger.Transaction;
   use type HRA.Money.Quantity;

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
      Tx    : HRA.Ledger.Transaction;
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

   --  =====================================================================
   --  Identified Actual candidate
   --  =====================================================================

   declare
      Tx : constant HRA.Ledger.Transaction := Balanced_Transaction;
      Expected : constant String :=
        "2026-08-20 Chair" & ASCII.LF &
        "    ; event-id: chair-actual" & ASCII.LF &
        "    assets:cash" & ASCII.HT & "-20000 JPY" & ASCII.LF &
        "    expenses:household" & ASCII.HT & "20000 JPY" & ASCII.LF;
   begin
      Assert
        (HRA.Actual_Candidate.Prepare_Identified (Tx, ID, Candidate, Diag),
         "Identified: balanced transaction prepares a source-durable Actual block");
      Assert
        (HRA.Actual_Candidate.Text (Candidate) = Expected,
         "Identified: uses one canonical event-id metadata, comma-free amount, and exact posting order");

      declare
         Parsed      : HRA.Ledger.Ledger;
         Parse_Diag  : HRA.Journal.Parse_Diagnostic;
         Evidence    : HRA.Journal_Evidence.Journal_Evidence;
         Ev_Diag     : HRA.Journal_Evidence.Evidence_Diagnostic;
         Observation : HRA.Actual_Admission.Actual_Observation;
         Adm_Diag    : HRA.Actual_Admission.Admission_Diagnostic;
      begin
         if not HRA.Journal.Parse_Journal_Text
           (HRA.Actual_Candidate.Text (Candidate), "<test>", Parsed, Parse_Diag)
           or else not HRA.Journal_Evidence.Extract
             (HRA.Actual_Candidate.Text (Candidate),
              "<test>", Parsed, Evidence, Ev_Diag)
           or else not HRA.Actual_Admission.Admit
             (Parsed, Evidence, Observation, Adm_Diag)
         then
            Assert (False, "Identified: canonical source re-admits");
         else
            declare
               Entry_Item : constant HRA.Actual_Admission.Actual_Transaction_Entry :=
                 HRA.Actual_Admission.Transaction_At (Observation, 1);
               Expected_Tx : HRA.Ledger.Transaction := Tx;
            begin
               Expected_Tx.Event_ID :=
                 To_Unbounded_String (HRA.Actual_Admission.Text (ID));
               Assert
                 (HRA.Actual_Admission.Transaction_Count (Observation) = 1
                  and then Entry_Item.Identity.Present
                  and then Entry_Item.Source_Durable_Identity.Present
                  and then Entry_Item.Identity.Value = ID
                  and then Entry_Item.Source_Durable_Identity.Value = ID
                  and then Entry_Item.Tx = Expected_Tx,
                  "Identified: exact id and typed Transaction meaning round-trip");
            end;
         end if;
      end;
   end;

   --  =====================================================================
   --  Ordinary identity-free Actual candidate
   --  =====================================================================

   declare
      Tx : constant HRA.Ledger.Transaction := Balanced_Transaction;
      Expected : constant String :=
        "2026-08-20 Chair" & ASCII.LF &
        "    assets:cash" & ASCII.HT & "-20000 JPY" & ASCII.LF &
        "    expenses:household" & ASCII.HT & "20000 JPY" & ASCII.LF;
   begin
      Assert
        (HRA.Actual_Candidate.Prepare_Ordinary (Tx, Candidate, Diag),
         "Ordinary: balanced transaction prepares an identity-free Actual block");
      Assert
        (HRA.Actual_Candidate.Text (Candidate) = Expected,
         "Ordinary: no event-id metadata, comma-free amount, and exact posting order");

      declare
         Parsed      : HRA.Ledger.Ledger;
         Parse_Diag  : HRA.Journal.Parse_Diagnostic;
         Evidence    : HRA.Journal_Evidence.Journal_Evidence;
         Ev_Diag     : HRA.Journal_Evidence.Evidence_Diagnostic;
         Observation : HRA.Actual_Admission.Actual_Observation;
         Adm_Diag    : HRA.Actual_Admission.Admission_Diagnostic;
      begin
         if not HRA.Journal.Parse_Journal_Text
           (HRA.Actual_Candidate.Text (Candidate), "<test>", Parsed, Parse_Diag)
           or else not HRA.Journal_Evidence.Extract
             (HRA.Actual_Candidate.Text (Candidate),
              "<test>", Parsed, Evidence, Ev_Diag)
           or else not HRA.Actual_Admission.Admit
             (Parsed, Evidence, Observation, Adm_Diag)
         then
            Assert (False, "Ordinary: canonical source re-admits");
         else
            declare
               Entry_Item : constant HRA.Actual_Admission.Actual_Transaction_Entry :=
                 HRA.Actual_Admission.Transaction_At (Observation, 1);
            begin
               Assert
                 (HRA.Actual_Admission.Transaction_Count (Observation) = 1
                  and then not Entry_Item.Identity.Present
                  and then not Entry_Item.Source_Durable_Identity.Present
                  and then Entry_Item.Tx = Tx,
                  "Ordinary: identity-free typed Transaction meaning round-trips");
            end;
         end if;
      end;
   end;

   --  =====================================================================
   --  Description law (shared by both modes)
   --  =====================================================================

   --  Empty description
   declare
      Tx : HRA.Ledger.Transaction := Balanced_Transaction;
   begin
      Tx.Code_Or_Payee := Null_Unbounded_String;
      Assert
        (not HRA.Actual_Candidate.Prepare_Identified (Tx, ID, Candidate, Diag)
           and then Diag.Status = HRA.Actual_Candidate.Description_Required,
         "Identified: empty description is rejected");
      Assert
        (not HRA.Actual_Candidate.Prepare_Ordinary (Tx, Candidate, Diag)
           and then Diag.Status = HRA.Actual_Candidate.Description_Required,
         "Ordinary: empty description is rejected");
   end;

   --  Spaces-only description
   declare
      Tx : HRA.Ledger.Transaction := Balanced_Transaction;
   begin
      Tx.Code_Or_Payee := To_Unbounded_String ("   ");
      Assert
        (not HRA.Actual_Candidate.Prepare_Identified (Tx, ID, Candidate, Diag)
           and then Diag.Status = HRA.Actual_Candidate.Description_Required,
         "Identified: spaces-only description is rejected");
      Assert
        (not HRA.Actual_Candidate.Prepare_Ordinary (Tx, Candidate, Diag)
           and then Diag.Status = HRA.Actual_Candidate.Description_Required,
         "Ordinary: spaces-only description is rejected");
   end;

   --  Tabs-only description
   declare
      Tx : HRA.Ledger.Transaction := Balanced_Transaction;
   begin
      Tx.Code_Or_Payee := To_Unbounded_String (ASCII.HT & ASCII.HT);
      Assert
        (not HRA.Actual_Candidate.Prepare_Identified (Tx, ID, Candidate, Diag)
           and then Diag.Status = HRA.Actual_Candidate.Description_Required,
         "Identified: tabs-only description is rejected");
      Assert
        (not HRA.Actual_Candidate.Prepare_Ordinary (Tx, Candidate, Diag)
           and then Diag.Status = HRA.Actual_Candidate.Description_Required,
         "Ordinary: tabs-only description is rejected");
   end;

   --  Leading whitespace
   declare
      Tx : HRA.Ledger.Transaction := Balanced_Transaction;
   begin
      Tx.Code_Or_Payee := To_Unbounded_String (" Chair");
      Assert
        (not HRA.Actual_Candidate.Prepare_Identified (Tx, ID, Candidate, Diag)
           and then Diag.Status =
             HRA.Actual_Candidate.Description_Has_Surrounding_Whitespace,
         "Identified: leading whitespace is rejected");
      Assert
        (not HRA.Actual_Candidate.Prepare_Ordinary (Tx, Candidate, Diag)
           and then Diag.Status =
             HRA.Actual_Candidate.Description_Has_Surrounding_Whitespace,
         "Ordinary: leading whitespace is rejected");
   end;

   --  Trailing whitespace
   declare
      Tx : HRA.Ledger.Transaction := Balanced_Transaction;
   begin
      Tx.Code_Or_Payee := To_Unbounded_String ("Chair ");
      Assert
        (not HRA.Actual_Candidate.Prepare_Identified (Tx, ID, Candidate, Diag)
           and then Diag.Status =
             HRA.Actual_Candidate.Description_Has_Surrounding_Whitespace,
         "Identified: trailing whitespace is rejected");
      Assert
        (not HRA.Actual_Candidate.Prepare_Ordinary (Tx, Candidate, Diag)
           and then Diag.Status =
             HRA.Actual_Candidate.Description_Has_Surrounding_Whitespace,
         "Ordinary: trailing whitespace is rejected");
   end;

   --  Line break injection
   declare
      Tx : HRA.Ledger.Transaction := Balanced_Transaction;
   begin
      Tx.Code_Or_Payee := To_Unbounded_String ("Chair" & ASCII.LF & "Injected");
      Assert
        (not HRA.Actual_Candidate.Prepare_Identified (Tx, ID, Candidate, Diag)
           and then Diag.Status =
             HRA.Actual_Candidate.Description_Contains_Line_Break,
         "Identified: line break injection is rejected");
      Assert
        (not HRA.Actual_Candidate.Prepare_Ordinary (Tx, Candidate, Diag)
           and then Diag.Status =
             HRA.Actual_Candidate.Description_Contains_Line_Break,
         "Ordinary: line break injection is rejected");
   end;

   --  =====================================================================
   --  Unbalanced transaction
   --  =====================================================================

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
        (not HRA.Actual_Candidate.Prepare_Identified (Tx, ID, Candidate, Diag)
           and then Diag.Status = HRA.Actual_Candidate.Unbalanced_Transaction,
         "Identified: unbalanced transaction is rejected before rendering");
      Assert
        (not HRA.Actual_Candidate.Prepare_Ordinary (Tx, Candidate, Diag)
           and then Diag.Status = HRA.Actual_Candidate.Unbalanced_Transaction,
         "Ordinary: unbalanced transaction is rejected before rendering");
   end;

   --  =====================================================================
   --  Pre-owned identity
   --  =====================================================================

   declare
      Tx : HRA.Ledger.Transaction := Balanced_Transaction;
   begin
      Tx.Event_ID := To_Unbounded_String ("already-owned");
      Assert
        (not HRA.Actual_Candidate.Prepare_Identified (Tx, ID, Candidate, Diag)
           and then Diag.Status =
             HRA.Actual_Candidate.Transaction_Already_Owns_Identity,
         "Identified: cannot smuggle a second source identity owner");
      Assert
        (not HRA.Actual_Candidate.Prepare_Ordinary (Tx, Candidate, Diag)
           and then Diag.Status =
             HRA.Actual_Candidate.Transaction_Already_Owns_Identity,
         "Ordinary: cannot have pre-existing Event_ID");
   end;

   --  =====================================================================
   --  Posting memo fail closed
   --  =====================================================================

   declare
      Tx : HRA.Ledger.Transaction := Balanced_Transaction;
      P  : HRA.Ledger.Posting := Tx.Postings.Element (1);
   begin
      P.Memo :=
        (Present => True,
         Text    => To_Unbounded_String ("cash leg memo"));
      Tx.Postings.Replace_Element (1, P);
      Assert
        (not HRA.Actual_Candidate.Prepare_Identified (Tx, ID, Candidate, Diag)
           and then Diag.Status =
             HRA.Actual_Candidate.Posting_Memo_Not_Representable,
         "Identified: posting memo is rejected rather than silently lost");
      Assert
        (not HRA.Actual_Candidate.Prepare_Ordinary (Tx, Candidate, Diag)
           and then Diag.Status =
             HRA.Actual_Candidate.Posting_Memo_Not_Representable,
         "Ordinary: posting memo is rejected rather than silently lost");
   end;

   --  =====================================================================
   --  Ordinary roundtrip: no effective identity, no source-durable identity
   --  =====================================================================

   declare
      Tx : constant HRA.Ledger.Transaction := Balanced_Transaction;
   begin
      Assert
        (HRA.Actual_Candidate.Prepare_Ordinary (Tx, Candidate, Diag)
           and then Diag.Status = HRA.Actual_Candidate.Success,
         "Ordinary: successful roundtrip has no unexpected identity");
   end;

   --  =====================================================================
   --  Identified roundtrip: explicit Actual_Id
   --  =====================================================================

   declare
      Tx : constant HRA.Ledger.Transaction := Balanced_Transaction;
   begin
      Assert
        (HRA.Actual_Candidate.Prepare_Identified (Tx, ID, Candidate, Diag)
           and then Diag.Status = HRA.Actual_Candidate.Success,
         "Identified: successful roundtrip with source-durable identity");
   end;

   Put_Line
     ("Summary: Passed =" & Natural'Image (Passed_Count) &
      ", Failed =" & Natural'Image (Failed_Count));

   if Failed_Count > 0 then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Test_Actual_Candidate;
