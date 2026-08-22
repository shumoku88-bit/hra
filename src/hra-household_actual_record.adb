with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA.Canonical_Source;
with HRA.Writer;

package body HRA.Household_Actual_Record is

   function Record_Actual
     (State     : HRA.Household.Household_State;
      Tx        : HRA.Ledger.Transaction;
      Actual_ID : HRA.Actual_Admission.Actual_Id;
      Diag      : out Record_Diagnostic) return Boolean
   is
      Block            : HRA.Actual_Candidate.Candidate_Block;
      Candidate_Diag   : HRA.Actual_Candidate.Candidate_Diagnostic;
      Root             : HRA.Actual_Root_Candidate.Candidate_Root;
      Root_Diag        : HRA.Actual_Root_Candidate.Candidate_Diagnostic;
      Graph            : HRA.Actual_Graph_Admission.Candidate_Graph;
      Graph_Diag       : HRA.Actual_Graph_Admission.Admission_Diagnostic;
      Qualified        : HRA.Actual_Account_Admission.Account_Qualified_Graph;
      Account_Diag     : HRA.Actual_Account_Admission.Admission_Diagnostic;
      Publication_Diag : HRA.Actual_Publication.Publication_Diagnostic;

      Root_Path : constant String :=
        HRA.Canonical_Source.Path_For
          (State.Sources.Paths, HRA.Canonical_Source.Actual_Source);
      Root_Text : constant String :=
        HRA.Canonical_Source.Text_For
          (State.Sources, HRA.Canonical_Source.Actual_Source);
      Account_Guards : constant HRA.Writer.Source_Premise_Array (1 .. 1) :=
        (1 =>
           HRA.Writer.Make_Source_Premise
             (Path =>
                HRA.Canonical_Source.Path_For
                  (State.Sources.Paths, HRA.Canonical_Source.Accounts_Source),
              Expected =>
                HRA.Writer.Make_Expected_Source
                  (HRA.Canonical_Source.Text_For
                     (State.Sources, HRA.Canonical_Source.Accounts_Source))));

      procedure Set_Diagnostic
        (Status  : Record_Status;
         Message : String)
      is
      begin
         Diag :=
           (Status      => Status,
            Candidate   => Candidate_Diag,
            Root        => Root_Diag,
            Graph       => Graph_Diag,
            Account     => Account_Diag,
            Publication => Publication_Diag,
            Message     => To_Unbounded_String (Message));
      end Set_Diagnostic;
   begin
      if not HRA.Actual_Candidate.Prepare
        (Tx, Actual_ID, Block, Candidate_Diag)
      then
         Set_Diagnostic
           (Candidate_Rejected,
            "ordinary Actual candidate rejected: " &
            HRA.Actual_Candidate.Candidate_Status'Image
              (Candidate_Diag.Status) &
            (if Length (Candidate_Diag.Message) > 0
             then ": " & To_String (Candidate_Diag.Message)
             else ""));
         return False;
      end if;

      if not HRA.Actual_Root_Candidate.Prepare
        (Root_Path, Root_Text, Block, Root, Root_Diag)
      then
         Set_Diagnostic
           (Root_Candidate_Rejected,
            "Actual root candidate rejected: " &
            HRA.Actual_Root_Candidate.Candidate_Status'Image
              (Root_Diag.Status) &
            (if Length (Root_Diag.Message) > 0
             then ": " & To_String (Root_Diag.Message)
             else ""));
         return False;
      end if;

      if not HRA.Actual_Graph_Admission.Admit_Candidate_Root
        (State.Actual_Identity, Root, Graph, Graph_Diag)
      then
         Set_Diagnostic
           (Graph_Admission_Rejected,
            "Actual candidate graph rejected: " &
            HRA.Actual_Graph_Admission.Admission_Status'Image
              (Graph_Diag.Status) &
            (if Length (Graph_Diag.Message) > 0
             then ": " & To_String (Graph_Diag.Message)
             else ""));
         return False;
      end if;

      if not HRA.Actual_Account_Admission.Admit
        (State.Registry, Graph, Qualified, Account_Diag)
      then
         Set_Diagnostic
           (Account_Admission_Rejected,
            "Actual Account qualification rejected: " &
            HRA.Actual_Account_Admission.Admission_Status'Image
              (Account_Diag.Status) &
            (if Length (Account_Diag.Message) > 0
             then ": " & To_String (Account_Diag.Message)
             else ""));
         return False;
      end if;

      if not HRA.Actual_Publication.Publish_With_Guards
        (Qualified, Account_Guards, Publication_Diag)
      then
         Set_Diagnostic
           (Publication_Rejected,
            "Actual publication rejected: " &
            HRA.Actual_Publication.Publication_Status'Image
              (Publication_Diag.Status) &
            (if Length (Publication_Diag.Message) > 0
             then ": " & To_String (Publication_Diag.Message)
             else ""));
         return False;
      end if;

      Set_Diagnostic (Success, "");
      return True;
   end Record_Actual;

end HRA.Household_Actual_Record;
