with HRA.Account;
with HRA.Dates;
with HRA.Money;

package body HRA.Actual_Candidate is

   use type HRA.Ledger.Transaction;

   function Text (Candidate : Candidate_Block) return String is
     (To_String (Candidate.Source_Text));

   function Contains_Line_Break (Value : String) return Boolean is
   begin
      for C of Value loop
         if C = ASCII.LF or else C = ASCII.CR then
            return True;
         end if;
      end loop;
      return False;
   end Contains_Line_Break;

   function Empty_Journal_Diagnostic return HRA.Journal.Parse_Diagnostic is
     ((File_Name   => Null_Unbounded_String,
       Line_Number => 0,
       Raw_Text    => Null_Unbounded_String,
       Message     => Null_Unbounded_String));

   function Empty_Evidence_Diagnostic
     return HRA.Journal_Evidence.Evidence_Diagnostic is
     ((Line_Number => 0,
       Message     => Null_Unbounded_String));

   function Empty_Actual_Diagnostic
     return HRA.Actual_Admission.Admission_Diagnostic is
     ((Status      => HRA.Actual_Admission.Success,
       Line_Number => 0,
       Actual_Id   => Null_Unbounded_String,
       Message     => Null_Unbounded_String));

   function Prepare
     (Tx        : HRA.Ledger.Transaction;
      Actual_ID : HRA.Actual_Admission.Actual_Id;
      Candidate : out Candidate_Block;
      Diag      : out Candidate_Diagnostic) return Boolean
   is
      Rendered       : Unbounded_String;
      Parsed         : HRA.Ledger.Ledger;
      Journal_Diag   : HRA.Journal.Parse_Diagnostic := Empty_Journal_Diagnostic;
      Evidence       : HRA.Journal_Evidence.Journal_Evidence;
      Evidence_Diag  : HRA.Journal_Evidence.Evidence_Diagnostic :=
        Empty_Evidence_Diagnostic;
      Observation    : HRA.Actual_Admission.Actual_Observation;
      Actual_Diag    : HRA.Actual_Admission.Admission_Diagnostic :=
        Empty_Actual_Diagnostic;
   begin
      Candidate := (Source_Text => Null_Unbounded_String);
      Diag :=
        (Status   => Success,
         Journal  => Empty_Journal_Diagnostic,
         Evidence => Empty_Evidence_Diagnostic,
         Actual   => Empty_Actual_Diagnostic,
         Message  => Null_Unbounded_String);

      if not HRA.Ledger.Is_Balanced (Tx) then
         Diag.Status := Unbalanced_Transaction;
         Diag.Message := To_Unbounded_String
           ("Actual candidate requires an already balanced Transaction");
         return False;
      end if;

      if Length (Tx.Event_ID) > 0 or else Length (Tx.Reverses_ID) > 0 then
         Diag.Status := Transaction_Already_Owns_Identity;
         Diag.Message := To_Unbounded_String
           ("Actual candidate identity must be supplied only through Actual_ID");
         return False;
      end if;

      if Contains_Line_Break (To_String (Tx.Code_Or_Payee)) then
         Diag.Status := Description_Contains_Line_Break;
         Diag.Message := To_Unbounded_String
           ("Actual transaction description cannot contain a line break");
         return False;
      end if;

      for Posting of Tx.Postings loop
         if Posting.Memo.Present then
            Diag.Status := Posting_Memo_Not_Representable;
            Diag.Message := To_Unbounded_String
              ("current Journal source grammar cannot retain posting memo losslessly");
            return False;
         end if;
      end loop;

      Append (Rendered, HRA.Dates.Image (Tx.Date));
      if Length (Tx.Code_Or_Payee) > 0 then
         Append (Rendered, " ");
         Append (Rendered, Tx.Code_Or_Payee);
      end if;
      Append (Rendered, ASCII.LF);
      Append
        (Rendered,
         "    ; event-id: " & HRA.Actual_Admission.Text (Actual_ID) & ASCII.LF);

      for Posting of Tx.Postings loop
         Append (Rendered, "    ");
         Append (Rendered, HRA.Account.Name (Posting.Acc));
         Append (Rendered, ASCII.HT);
         Append (Rendered, HRA.Money.Render_Quantity (Posting.Amt.Val));
         Append (Rendered, " ");
         Append (Rendered, HRA.Money.Code (Posting.Amt.Comm));
         Append (Rendered, ASCII.LF);
      end loop;

      if not HRA.Journal.Parse_Journal_Text
        (To_String (Rendered), "<actual-candidate>", Parsed, Journal_Diag)
      then
         Diag.Status := Journal_Admission_Failed;
         Diag.Journal := Journal_Diag;
         Diag.Message := To_Unbounded_String
           ("rendered Actual candidate is not admitted by Journal syntax");
         return False;
      end if;

      if not HRA.Journal_Evidence.Extract
        (To_String (Rendered),
         "<actual-candidate>",
         Parsed,
         Evidence,
         Evidence_Diag)
      then
         Diag.Status := Evidence_Admission_Failed;
         Diag.Evidence := Evidence_Diag;
         Diag.Message := To_Unbounded_String
           ("rendered Actual candidate does not retain aligned source evidence");
         return False;
      end if;

      if not HRA.Actual_Admission.Admit
        (Parsed, Evidence, Observation, Actual_Diag)
      then
         Diag.Status := Actual_Admission_Failed;
         Diag.Actual := Actual_Diag;
         Diag.Message := To_Unbounded_String
           ("rendered Actual candidate does not satisfy Actual admission");
         return False;
      end if;

      if HRA.Actual_Admission.Transaction_Count (Observation) /= 1
        or else not HRA.Actual_Admission.Has_Source_Durable_Identity
          (Observation, Actual_ID)
      then
         Diag.Status := Semantic_Roundtrip_Failed;
         Diag.Message := To_Unbounded_String
           ("Actual candidate did not round-trip to one source-durable transaction");
         return False;
      end if;

      declare
         Actual_Entry : constant HRA.Actual_Admission.Actual_Transaction_Entry :=
           HRA.Actual_Admission.Transaction_At (Observation, 1);
         Expected     : HRA.Ledger.Transaction := Tx;
      begin
         Expected.Event_ID :=
           To_Unbounded_String (HRA.Actual_Admission.Text (Actual_ID));
         if Actual_Entry.Tx /= Expected then
            Diag.Status := Semantic_Roundtrip_Failed;
            Diag.Message := To_Unbounded_String
              ("Actual candidate changed typed Transaction meaning during round-trip");
            return False;
         end if;
      end;

      Candidate := (Source_Text => Rendered);
      return True;
   end Prepare;

end HRA.Actual_Candidate;
