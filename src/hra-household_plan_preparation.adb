with HRA.Canonical_Source;
with HRA.Dates;
with HRA.Plan_Admission;

package body HRA.Household_Plan_Preparation is

   use type HRA.Plan.Plan_Id;
   use type HRA.Plan_Admission.Retirement_Kind;
   use type HRA.Ledger.Transaction;
   use type HRA.Dates.Date;

   function Prepare
     (State    : HRA.Household.Household_State;
      Plan_ID  : HRA.Plan.Plan_Id;
      Tx       : HRA.Ledger.Transaction;
      Prepared : out Prepared_Plan;
      Diag     : out Preparation_Diagnostic) return Boolean
   is
      Block          : HRA.Plan_Candidate.Candidate_Block;
      Candidate_Diag : HRA.Plan_Candidate.Candidate_Diagnostic;
      Root           : HRA.Plan_Root_Candidate.Candidate_Root;
      Root_Diag      : HRA.Plan_Root_Candidate.Candidate_Diagnostic;
      Graph          : HRA.Plan_Graph_Admission.Candidate_Graph;
      Graph_Diag     : HRA.Plan_Graph_Admission.Admission_Diagnostic;
      Qualified      : HRA.Plan_Account_Admission.Account_Qualified_Graph;
      Account_Diag   : HRA.Plan_Account_Admission.Admission_Diagnostic;

      Root_Path : constant String :=
        HRA.Canonical_Source.Path_For
          (State.Sources.Paths, HRA.Canonical_Source.Plan_Source);
      Root_Text : constant String :=
        HRA.Canonical_Source.Text_For
          (State.Sources, HRA.Canonical_Source.Plan_Source);
      Account_Path : constant String :=
        HRA.Canonical_Source.Path_For
          (State.Sources.Paths, HRA.Canonical_Source.Accounts_Source);
      Account_Text : constant String :=
        HRA.Canonical_Source.Text_For
          (State.Sources, HRA.Canonical_Source.Accounts_Source);
      Account_Guard : constant HRA.Writer.Source_Premise :=
        HRA.Writer.Make_Source_Premise
          (Path => Account_Path,
           Expected =>
             HRA.Writer.Make_Expected_Source (Account_Text));

      procedure Set_Diagnostic
        (Status  : Preparation_Status;
         Message : String)
      is
      begin
         Diag :=
           (Status    => Status,
            Candidate => Candidate_Diag,
            Root      => Root_Diag,
            Graph     => Graph_Diag,
            Account   => Account_Diag,
            Message   => To_Unbounded_String (Message));
      end Set_Diagnostic;

   begin
      Prepared :=
        (Target_Plan_ID     => Plan_ID,
         Target_Tx          => Tx,
         Target_Path        => To_Unbounded_String (Root_Path),
         Expected_Root_Text => To_Unbounded_String (Root_Text),
         Account_Guard_Path => To_Unbounded_String (Account_Path),
         Account_Guard_Text => To_Unbounded_String (Account_Text),
         Account_Guard      => Account_Guard,
         Qualified          => <>,
         Already_Present    => False);
      Set_Diagnostic (Success, "");

      if HRA.Plan.Is_Null (Plan_ID) then
         Set_Diagnostic (Candidate_Rejected, "Plan_Id must not be null");
         return False;
      end if;

      --  Check if Plan_ID is already present in admitted Plan_Journal (retry)
      if HRA.Plan.Contains
        (HRA.Plan_Admission.Plan_Ids_Of (State.Plan_Journal), Plan_ID)
      then
         declare
            Existing_Found : Boolean := False;
            Existing_Entry : HRA.Plan_Admission.Plan_Transaction_Entry;
         begin
            for I in 1 .. HRA.Plan_Admission.Transaction_Count (State.Plan_Journal) loop
               declare
                  Item : constant HRA.Plan_Admission.Plan_Transaction_Entry :=
                    HRA.Plan_Admission.Transaction_At (State.Plan_Journal, I);
               begin
                  if Item.ID = Plan_ID then
                     Existing_Entry := Item;
                     Existing_Found := True;
                     exit;
                  end if;
               end;
            end loop;

            if Existing_Found then
               declare
                  Expected_Tx : HRA.Ledger.Transaction := Tx;
               begin
                  Expected_Tx.Event_ID := Null_Unbounded_String;
                  Expected_Tx.Reverses_ID := Null_Unbounded_String;

                  if Existing_Entry.Retirement.Kind = HRA.Plan_Admission.No_Retirement
                    and then Existing_Entry.Tx.Date = Tx.Date
                    and then To_String (Existing_Entry.Tx.Code_Or_Payee) =
                      To_String (Tx.Code_Or_Payee)
                    and then Existing_Entry.Tx = Expected_Tx
                  then
                     Prepared.Already_Present := True;
                     Set_Diagnostic
                       (Already_Present_As_Requested,
                        "Plan already present with exact requested meaning");
                     return True;
                  else
                     Set_Diagnostic
                       (Conflicting_Plan_Already_Exists,
                        "Plan_Id already exists with conflicting transaction meaning or lifecycle state");
                     return False;
                  end if;
               end;
            end if;
         end;
      end if;

      if not HRA.Plan_Candidate.Prepare_Pending
        (Tx, Plan_ID, Block, Candidate_Diag)
      then
         Set_Diagnostic
           (Candidate_Rejected,
            "Plan candidate rejected: " &
            HRA.Plan_Candidate.Candidate_Status'Image (Candidate_Diag.Status) &
            (if Length (Candidate_Diag.Message) > 0
             then ": " & To_String (Candidate_Diag.Message)
             else ""));
         return False;
      end if;

      if not HRA.Plan_Root_Candidate.Prepare
        (Root_Path, Root_Text, Block, Root, Root_Diag)
      then
         Set_Diagnostic
           (Root_Candidate_Rejected,
            "Plan root candidate rejected: " &
            HRA.Plan_Root_Candidate.Candidate_Status'Image (Root_Diag.Status) &
            (if Length (Root_Diag.Message) > 0
             then ": " & To_String (Root_Diag.Message)
             else ""));
         return False;
      end if;

      if not HRA.Plan_Graph_Admission.Admit_Candidate_Root
        (State.Plan_Journal, Root, Graph, Graph_Diag)
      then
         Set_Diagnostic
           (Graph_Admission_Rejected,
            "Plan candidate graph rejected: " &
            HRA.Plan_Graph_Admission.Admission_Status'Image (Graph_Diag.Status) &
            (if Length (Graph_Diag.Message) > 0
             then ": " & To_String (Graph_Diag.Message)
             else ""));
         return False;
      end if;

      if not HRA.Plan_Account_Admission.Admit
        (State.Registry, Graph, Qualified, Account_Diag)
      then
         Set_Diagnostic
           (Account_Admission_Rejected,
            "Plan Account qualification rejected: " &
            HRA.Plan_Account_Admission.Admission_Status'Image
              (Account_Diag.Status) &
            (if Length (Account_Diag.Message) > 0
             then ": " & To_String (Account_Diag.Message)
             else ""));
         return False;
      end if;

      Prepared.Qualified := Qualified;
      Set_Diagnostic (Success, "");
      return True;
   end Prepare;

end HRA.Household_Plan_Preparation;
