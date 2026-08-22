with HRA.Account;
with HRA.Dates;
with HRA.Money;

package body HRA.Plan_Candidate is

   use type HRA.Plan.Plan_Id;
   use type HRA.Plan_Admission.Retirement_Kind;
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

   function Is_Description_Whitespace (C : Character) return Boolean is
     (C = ' ' or else C = ASCII.HT);

   function Is_Whitespace_Only (Value : String) return Boolean is
   begin
      if Value'Length = 0 then
         return True;
      end if;

      for C of Value loop
         if not Is_Description_Whitespace (C) then
            return False;
         end if;
      end loop;

      return True;
   end Is_Whitespace_Only;

   function Has_Surrounding_Whitespace (Value : String) return Boolean is
     (Value'Length > 0
      and then
        (Is_Description_Whitespace (Value (Value'First))
         or else Is_Description_Whitespace (Value (Value'Last))));

   function Empty_Journal_Diagnostic return HRA.Journal.Parse_Diagnostic is
     ((File_Name   => Null_Unbounded_String,
       Line_Number => 0,
       Raw_Text    => Null_Unbounded_String,
       Message     => Null_Unbounded_String));

   function Empty_Evidence_Diagnostic
     return HRA.Journal_Evidence.Evidence_Diagnostic is
     ((Line_Number => 0,
       Message     => Null_Unbounded_String));

   function Empty_Plan_Diagnostic
     return HRA.Plan_Admission.Admission_Diagnostic is
     ((Status      => HRA.Plan_Admission.Success,
       Line_Number => 0,
       Plan_Id     => Null_Unbounded_String,
       Message     => Null_Unbounded_String));

   function Prepare_Pending
     (Tx        : HRA.Ledger.Transaction;
      Plan_ID   : HRA.Plan.Plan_Id;
      Candidate : out Candidate_Block;
      Diag      : out Candidate_Diagnostic) return Boolean
   is
      Rendered      : Unbounded_String;
      Parsed        : HRA.Ledger.Ledger;
      Journal_Diag  : HRA.Journal.Parse_Diagnostic := Empty_Journal_Diagnostic;
      Evidence      : HRA.Journal_Evidence.Journal_Evidence;
      Evidence_Diag : HRA.Journal_Evidence.Evidence_Diagnostic :=
        Empty_Evidence_Diagnostic;
      Journal_Plan  : HRA.Plan_Admission.Plan_Journal;
      Plan_Diag     : HRA.Plan_Admission.Admission_Diagnostic :=
        Empty_Plan_Diagnostic;
   begin
      Candidate := (Source_Text => Null_Unbounded_String);
      Diag :=
        (Status   => Success,
         Journal  => Empty_Journal_Diagnostic,
         Evidence => Empty_Evidence_Diagnostic,
         Plan     => Empty_Plan_Diagnostic,
         Message  => Null_Unbounded_String);

      if HRA.Plan.Is_Null (Plan_ID) then
         Diag.Status := Invalid_Plan_Id;
         Diag.Message := To_Unbounded_String
           ("Plan candidate requires a non-null Plan_Id");
         return False;
      end if;

      if not HRA.Ledger.Is_Balanced (Tx) then
         Diag.Status := Unbalanced_Transaction;
         Diag.Message := To_Unbounded_String
           ("Plan candidate requires an already balanced Transaction");
         return False;
      end if;

      if Length (Tx.Event_ID) > 0 or else Length (Tx.Reverses_ID) > 0 then
         Diag.Status := Transaction_Already_Owns_Identity;
         Diag.Message := To_Unbounded_String
           ("Plan candidate identity must be supplied only through Plan_Id");
         return False;
      end if;

      declare
         Description : constant String := To_String (Tx.Code_Or_Payee);
      begin
         if Is_Whitespace_Only (Description) then
            Diag.Status := Description_Required;
            Diag.Message := To_Unbounded_String
              ("Plan transaction description is required by canonical Journal syntax");
            return False;
         elsif Has_Surrounding_Whitespace (Description) then
            Diag.Status := Description_Has_Surrounding_Whitespace;
            Diag.Message := To_Unbounded_String
              ("Plan transaction description cannot have surrounding whitespace");
            return False;
         elsif Contains_Line_Break (Description) then
            Diag.Status := Description_Contains_Line_Break;
            Diag.Message := To_Unbounded_String
              ("Plan transaction description cannot contain a line break");
            return False;
         end if;
      end;

      for Posting of Tx.Postings loop
         if Posting.Memo.Present then
            Diag.Status := Posting_Memo_Not_Representable;
            Diag.Message := To_Unbounded_String
              ("current Journal source grammar cannot retain posting memo losslessly");
            return False;
         end if;
      end loop;

      --  Render transaction header
      Append (Rendered, HRA.Dates.Image (Tx.Date));
      Append (Rendered, " ");
      Append (Rendered, Tx.Code_Or_Payee);
      Append (Rendered, ASCII.LF);

      --  Render plan-id metadata
      Append
        (Rendered,
         "    ; plan-id: " &
         HRA.Plan.Text (Plan_ID) & ASCII.LF);

      --  Render postings
      for Posting of Tx.Postings loop
         Append (Rendered, "    ");
         Append (Rendered, HRA.Account.Name (Posting.Acc));
         Append (Rendered, ASCII.HT);
         Append (Rendered, HRA.Money.Render_Source_Quantity (Posting.Amt.Val));
         Append (Rendered, " ");
         Append (Rendered, HRA.Money.Code (Posting.Amt.Comm));
         Append (Rendered, ASCII.LF);
      end loop;

      if not HRA.Journal.Parse_Journal_Text
        (To_String (Rendered), "<plan-candidate>", Parsed, Journal_Diag)
      then
         Diag.Status := Journal_Admission_Failed;
         Diag.Journal := Journal_Diag;
         Diag.Message := To_Unbounded_String
           ("rendered Plan candidate is not admitted by Journal syntax");
         return False;
      end if;

      if not HRA.Journal_Evidence.Extract
        (To_String (Rendered),
         "<plan-candidate>",
         Parsed,
         Evidence,
         Evidence_Diag)
      then
         Diag.Status := Evidence_Admission_Failed;
         Diag.Evidence := Evidence_Diag;
         Diag.Message := To_Unbounded_String
           ("rendered Plan candidate does not retain aligned source evidence");
         return False;
      end if;

      if not HRA.Plan_Admission.Admit
        (Parsed, Evidence, Journal_Plan, Plan_Diag)
      then
         Diag.Status := Plan_Admission_Failed;
         Diag.Plan := Plan_Diag;
         Diag.Message := To_Unbounded_String
           ("rendered Plan candidate does not satisfy Plan admission");
         return False;
      end if;

      if HRA.Plan_Admission.Transaction_Count (Journal_Plan) /= 1 then
         Diag.Status := Semantic_Roundtrip_Failed;
         Diag.Message := To_Unbounded_String
           ("Plan candidate did not round-trip to exactly one transaction");
         return False;
      end if;

      declare
         Plan_Entry : constant HRA.Plan_Admission.Plan_Transaction_Entry :=
           HRA.Plan_Admission.Transaction_At (Journal_Plan, 1);
         Expected   : constant HRA.Ledger.Transaction := Tx;
      begin
         if Plan_Entry.ID /= Plan_ID then
            Diag.Status := Semantic_Roundtrip_Failed;
            Diag.Message := To_Unbounded_String
              ("Plan candidate did not round-trip to requested Plan_Id");
            return False;
         end if;

         if Plan_Entry.Retirement.Kind /= HRA.Plan_Admission.No_Retirement then
            Diag.Status := Semantic_Roundtrip_Failed;
            Diag.Message := To_Unbounded_String
              ("pending Plan candidate acquired unexpected retirement evidence during round-trip");
            return False;
         end if;

         if Plan_Entry.Tx /= Expected then
            Diag.Status := Semantic_Roundtrip_Failed;
            Diag.Message := To_Unbounded_String
              ("Plan candidate changed typed Transaction meaning during round-trip");
            return False;
         end if;
      end;

      Candidate := (Source_Text => Rendered);
      return True;
   end Prepare_Pending;

end HRA.Plan_Candidate;
