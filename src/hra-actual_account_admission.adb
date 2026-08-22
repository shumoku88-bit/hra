with HRA.Ledger;

package body HRA.Actual_Account_Admission is

   use type HRA.Account.Account;

   function Observation_Of
     (Candidate : Account_Qualified_Graph)
      return HRA.Actual_Admission.Actual_Observation is
     (HRA.Actual_Graph_Admission.Observation_Of (Candidate.Graph_Value));

   function Graph_Of
     (Candidate : Account_Qualified_Graph)
      return HRA.Actual_Graph_Admission.Candidate_Graph is
     (Candidate.Graph_Value);

   function Admit
     (Registry  : HRA.Account.Account_Registry;
      Graph     : HRA.Actual_Graph_Admission.Candidate_Graph;
      Candidate : out Account_Qualified_Graph;
      Diag      : out Admission_Diagnostic) return Boolean
   is
      Observation : constant HRA.Actual_Admission.Actual_Observation :=
        HRA.Actual_Graph_Admission.Observation_Of (Graph);
   begin
      Diag :=
        (Status            => Success,
         Transaction_Index => 0,
         Posting_Index     => 0,
         Account_Name      => Null_Unbounded_String,
         Message           => Null_Unbounded_String);

      for Tx_Index in 1 .. HRA.Actual_Admission.Transaction_Count (Observation) loop
         declare
            Actual_Entry : constant HRA.Actual_Admission.Actual_Transaction_Entry :=
              HRA.Actual_Admission.Transaction_At (Observation, Tx_Index);
         begin
            for Posting_Index in 1 .. Natural (Actual_Entry.Tx.Postings.Length) loop
               declare
                  Posting : constant HRA.Ledger.Posting :=
                    Actual_Entry.Tx.Postings.Element (Posting_Index);
                  Decl    : HRA.Account.Account_Declaration;
               begin
                  if not HRA.Account.Lookup_Declaration
                    (Registry, Posting.Acc, Decl)
                    or else Decl.Acc /= Posting.Acc
                  then
                     Diag.Status := Undeclared_Account;
                     Diag.Transaction_Index := Tx_Index;
                     Diag.Posting_Index := Posting_Index;
                     Diag.Account_Name := To_Unbounded_String
                       (HRA.Account.Name (Posting.Acc));
                     Diag.Message := To_Unbounded_String
                       ("Actual candidate Account is not declared in the supplied canonical registry");
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

end HRA.Actual_Account_Admission;
