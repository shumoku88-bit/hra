with HRA.Ledger;

package body HRA.Actual_Root_Candidate is

   use type HRA.Ledger.Transaction;

   function Root_Path_Of (Candidate : Candidate_Root) return String is
     (To_String (Candidate.Root_Path));

   function Observed_Text (Candidate : Candidate_Root) return String is
     (To_String (Candidate.Observed_Source_Text));

   function Text (Candidate : Candidate_Root) return String is
     (To_String (Candidate.Candidate_Source_Text));

   function Empty_Journal_Diagnostic return HRA.Journal.Parse_Diagnostic is
     ((File_Name   => Null_Unbounded_String,
       Line_Number => 0,
       Raw_Text    => Null_Unbounded_String,
       Message     => Null_Unbounded_String));

   function Empty_Evidence_Diagnostic
     return HRA.Journal_Evidence.Evidence_Diagnostic is
     ((Line_Number => 0,
       Message     => Null_Unbounded_String));

   --  Compare source meaning while intentionally ignoring physical placement.
   --  Root placement changes Source_Path, Header_Line, and metadata line numbers,
   --  but it must not change the transaction text or metadata key/value meaning.
   function Same_Evidence_Meaning
     (Left  : HRA.Journal_Evidence.Transaction_Source;
      Right : HRA.Journal_Evidence.Transaction_Source) return Boolean
   is
      Left_Metadata_Count  : constant Natural := Natural (Left.Metadata.Length);
      Right_Metadata_Count : constant Natural := Natural (Right.Metadata.Length);
   begin
      if To_String (Left.Date_Text) /= To_String (Right.Date_Text)
        or else To_String (Left.Description) /= To_String (Right.Description)
        or else Left_Metadata_Count /= Right_Metadata_Count
      then
         return False;
      end if;

      for I in 1 .. Left_Metadata_Count loop
         declare
            Left_Entry  : constant HRA.Journal_Evidence.Metadata_Entry :=
              Left.Metadata.Element (I);
            Right_Entry : constant HRA.Journal_Evidence.Metadata_Entry :=
              Right.Metadata.Element (I);
         begin
            if To_String (Left_Entry.Key) /= To_String (Right_Entry.Key)
              or else To_String (Left_Entry.Value) /= To_String (Right_Entry.Value)
            then
               return False;
            end if;
         end;
      end loop;

      return True;
   end Same_Evidence_Meaning;

   function Prepare
     (Root_Path : String;
      Root_Text : String;
      Block     : HRA.Actual_Candidate.Candidate_Block;
      Candidate : out Candidate_Root;
      Diag      : out Candidate_Diagnostic) return Boolean
   is
      Existing_Ledger    : HRA.Ledger.Ledger;
      Existing_Evidence  : HRA.Journal_Evidence.Journal_Evidence;
      Candidate_Ledger   : HRA.Ledger.Ledger;
      Candidate_Evidence : HRA.Journal_Evidence.Journal_Evidence;
      Block_Ledger       : HRA.Ledger.Ledger;
      Block_Evidence     : HRA.Journal_Evidence.Journal_Evidence;
      Journal_Diag       : HRA.Journal.Parse_Diagnostic :=
        Empty_Journal_Diagnostic;
      Evidence_Diag      : HRA.Journal_Evidence.Evidence_Diagnostic :=
        Empty_Evidence_Diagnostic;
      Rendered           : Unbounded_String := To_Unbounded_String (Root_Text);
      Block_Text         : constant String := HRA.Actual_Candidate.Text (Block);
   begin
      Candidate :=
        (Root_Path             => Null_Unbounded_String,
         Observed_Source_Text  => Null_Unbounded_String,
         Candidate_Source_Text => Null_Unbounded_String);
      Diag :=
        (Status   => Success,
         Journal  => Empty_Journal_Diagnostic,
         Evidence => Empty_Evidence_Diagnostic,
         Message  => Null_Unbounded_String);

      if not HRA.Journal.Parse_Journal_Text
        (Root_Text, Root_Path, Existing_Ledger, Journal_Diag)
      then
         Diag.Status := Existing_Root_Journal_Admission_Failed;
         Diag.Journal := Journal_Diag;
         Diag.Message := To_Unbounded_String
           ("existing Actual root source is not admitted by Journal syntax");
         return False;
      end if;

      if not HRA.Journal_Evidence.Extract
        (Root_Text,
         Root_Path,
         Existing_Ledger,
         Existing_Evidence,
         Evidence_Diag)
      then
         Diag.Status := Existing_Root_Evidence_Admission_Failed;
         Diag.Evidence := Evidence_Diag;
         Diag.Message := To_Unbounded_String
           ("existing Actual root source does not retain aligned evidence");
         return False;
      end if;

      if Length (Rendered) > 0
        and then Element (Rendered, Length (Rendered)) /= ASCII.LF
      then
         Append (Rendered, ASCII.LF);
      end if;
      Append (Rendered, Block_Text);

      Journal_Diag := Empty_Journal_Diagnostic;
      if not HRA.Journal.Parse_Journal_Text
        (To_String (Rendered), Root_Path, Candidate_Ledger, Journal_Diag)
      then
         Diag.Status := Candidate_Root_Journal_Admission_Failed;
         Diag.Journal := Journal_Diag;
         Diag.Message := To_Unbounded_String
           ("Actual root candidate is not admitted by Journal syntax");
         return False;
      end if;

      Evidence_Diag := Empty_Evidence_Diagnostic;
      if not HRA.Journal_Evidence.Extract
        (To_String (Rendered),
         Root_Path,
         Candidate_Ledger,
         Candidate_Evidence,
         Evidence_Diag)
      then
         Diag.Status := Candidate_Root_Evidence_Admission_Failed;
         Diag.Evidence := Evidence_Diag;
         Diag.Message := To_Unbounded_String
           ("Actual root candidate does not retain aligned source evidence");
         return False;
      end if;

      --  Candidate_Block is private and already qualified by Actual_Candidate,
      --  but parse it once here as the suffix meaning against which the complete
      --  root candidate is checked. No include graph is involved.
      Journal_Diag := Empty_Journal_Diagnostic;
      if not HRA.Journal.Parse_Journal_Text
        (Block_Text, "<actual-root-block>", Block_Ledger, Journal_Diag)
      then
         Diag.Status := Semantic_Roundtrip_Failed;
         Diag.Journal := Journal_Diag;
         Diag.Message := To_Unbounded_String
           ("qualified Actual block no longer admits as one root-local suffix");
         return False;
      end if;

      Evidence_Diag := Empty_Evidence_Diagnostic;
      if not HRA.Journal_Evidence.Extract
        (Block_Text,
         "<actual-root-block>",
         Block_Ledger,
         Block_Evidence,
         Evidence_Diag)
      then
         Diag.Status := Semantic_Roundtrip_Failed;
         Diag.Evidence := Evidence_Diag;
         Diag.Message := To_Unbounded_String
           ("qualified Actual block lost root-local source evidence");
         return False;
      end if;

      declare
         Existing_Count  : constant Natural :=
           Natural (Existing_Ledger.Transactions.Length);
         Candidate_Count : constant Natural :=
           Natural (Candidate_Ledger.Transactions.Length);
         Block_Count     : constant Natural :=
           Natural (Block_Ledger.Transactions.Length);
         Existing_Evidence_Count : constant Natural :=
           Natural (Existing_Evidence.Transactions.Length);
         Candidate_Evidence_Count : constant Natural :=
           Natural (Candidate_Evidence.Transactions.Length);
         Block_Evidence_Count : constant Natural :=
           Natural (Block_Evidence.Transactions.Length);
      begin
         if Block_Count /= 1
           or else Block_Evidence_Count /= 1
           or else Candidate_Count /= Existing_Count + 1
           or else Candidate_Evidence_Count /= Existing_Evidence_Count + 1
         then
            Diag.Status := Semantic_Roundtrip_Failed;
            Diag.Message := To_Unbounded_String
              ("Actual root candidate did not add exactly one direct root transaction");
            return False;
         end if;

         for I in 1 .. Existing_Count loop
            if Candidate_Ledger.Transactions.Element (I) /=
              Existing_Ledger.Transactions.Element (I)
            then
               Diag.Status := Semantic_Roundtrip_Failed;
               Diag.Message := To_Unbounded_String
                 ("Actual root candidate changed existing direct transaction meaning");
               return False;
            end if;
         end loop;

         if Candidate_Ledger.Transactions.Element (Candidate_Count) /=
           Block_Ledger.Transactions.Element (1)
         then
            Diag.Status := Semantic_Roundtrip_Failed;
            Diag.Message := To_Unbounded_String
              ("Actual root candidate changed appended block transaction meaning");
            return False;
         end if;

         if not Same_Evidence_Meaning
           (Candidate_Evidence.Transactions.Element (Candidate_Evidence_Count),
            Block_Evidence.Transactions.Element (1))
         then
            Diag.Status := Semantic_Roundtrip_Failed;
            Diag.Message := To_Unbounded_String
              ("Actual root candidate changed appended block evidence meaning");
            return False;
         end if;
      end;

      Candidate :=
        (Root_Path             => To_Unbounded_String (Root_Path),
         Observed_Source_Text  => To_Unbounded_String (Root_Text),
         Candidate_Source_Text => Rendered);
      return True;
   end Prepare;

end HRA.Actual_Root_Candidate;
