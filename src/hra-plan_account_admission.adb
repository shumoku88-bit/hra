with HRA.Ledger;

package body HRA.Plan_Account_Admission is

   use type HRA.Account.Account;

   function Plan_Journal_Of
     (Candidate : Account_Qualified_Graph)
      return HRA.Plan_Admission.Plan_Journal is
     (HRA.Plan_Graph_Admission.Plan_Journal_Of (Candidate.Graph_Value));

   function Graph_Of
     (Candidate : Account_Qualified_Graph)
      return HRA.Plan_Graph_Admission.Candidate_Graph is
     (Candidate.Graph_Value);

   function Admit
     (Registry  : HRA.Account.Account_Registry;
      Graph     : HRA.Plan_Graph_Admission.Candidate_Graph;
      Candidate : out Account_Qualified_Graph;
      Diag      : out Admission_Diagnostic) return Boolean
   is
      Plan_Journal : constant HRA.Plan_Admission.Plan_Journal :=
        HRA.Plan_Graph_Admission.Plan_Journal_Of (Graph);
      L            : constant HRA.Ledger.Ledger :=
        HRA.Plan_Admission.Ledger_Of (Plan_Journal);
   begin
      Candidate :=
        (Registry_Premise => HRA.Account.Empty_Registry,
         Graph_Value      => Graph);
      Diag :=
        (Status            => Success,
         Transaction_Index => 0,
         Posting_Index     => 0,
         Account_Name      => Null_Unbounded_String,
         Message           => Null_Unbounded_String);

      for Tx_Index in 1 .. Natural (L.Transactions.Length) loop
         declare
            Tx : constant HRA.Ledger.Transaction :=
              L.Transactions.Element (Tx_Index);
         begin
            for Posting_Index in 1 .. Natural (Tx.Postings.Length) loop
               declare
                  Posting : constant HRA.Ledger.Posting :=
                    Tx.Postings.Element (Posting_Index);
                  Decl    : HRA.Account.Account_Declaration;
               begin
                  if not HRA.Account.Lookup_Declaration
                    (Registry, Posting.Acc, Decl)
                    or else Decl.Acc /= Posting.Acc
                  then
                     Diag :=
                       (Status            => Undeclared_Account,
                        Transaction_Index => Tx_Index,
                        Posting_Index     => Posting_Index,
                        Account_Name      => To_Unbounded_String
                          (HRA.Account.Name (Posting.Acc)),
                        Message           => To_Unbounded_String
                          ("Posting references an undeclared Account: " &
                           HRA.Account.Name (Posting.Acc)));
                     return False;
                  end if;
               end;
            end loop;
         end;
      end loop;

      Candidate :=
        (Registry_Premise => Registry,
         Graph_Value      => Graph);
      return True;
   end Admit;

end HRA.Plan_Account_Admission;
