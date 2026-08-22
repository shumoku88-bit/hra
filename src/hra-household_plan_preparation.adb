with HRA.Account;
with HRA.Canonical_Source;
with HRA.Plan_Admission;

package body HRA.Household_Plan_Preparation is

   use type HRA.Plan.Plan_Id;
   use type HRA.Plan_Admission.Retirement_Kind;
   use type HRA.Ledger.Transaction;

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

      Plan_Root_Path : constant String :=
        HRA.Canonical_Source.Path_For
          (State.Sources.Paths, HRA.Canonical_Source.Plan_Source);
      Plan_Root_Text : constant String :=
        HRA.Canonical_Source.Text_For
          (State.Sources, HRA.Canonical_Source.Plan_Source);
      Account_Root_Path : constant String :=
        HRA.Canonical_Source.Path_For
          (State.Sources.Paths, HRA.Canonical_Source.Accounts_Source);
      Account_Root_Text : constant String :=
        HRA.Canonical_Source.Text_For
          (State.Sources, HRA.Canonical_Source.Accounts_Source);

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
        (Target_Plan_ID  => Plan_ID,
         Target_Tx       => Tx,
         Account_Sources => <>,
         Plan_Sources    => <>,
         Qualified       => <>,
         Already_Present => False);
      Set_Diagnostic (Success, "");

      --  1. Source-local complete request validation (shared for fresh & retry)
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

      --  2. Validate and retain complete fresh Accounts include graph
      declare
         Account_Loaded : HRA.Journal_Loader.Journal_Observation;
         Account_Error  : Unbounded_String;
      begin
         if not HRA.Journal_Loader.Load_From_Root_Source
           (Root_Path   => Account_Root_Path,
            Root_Text   => Account_Root_Text,
            Observation => Account_Loaded,
            Error_Msg   => Account_Error)
         then
            Set_Diagnostic
              (Account_Admission_Rejected,
               "accounts.journal include graph failed to load: " &
               To_String (Account_Error));
            return False;
         end if;

         if not HRA.Account.Same_Registry
           (Account_Loaded.Value.Registry, State.Registry)
         then
            Set_Diagnostic
              (Account_Admission_Rejected,
               "Accounts declaration authority drifted from loaded Household state");
            return False;
         end if;

         Prepared.Account_Sources := Account_Loaded.Sources;
      end;

      --  3. Validate and retain complete fresh Plan include graph
      declare
         Plan_Loaded      : HRA.Journal_Loader.Journal_Observation;
         Plan_Error       : Unbounded_String;
         Fresh_Plan       : HRA.Plan_Admission.Plan_Journal;
         Fresh_Admit_Diag : HRA.Plan_Admission.Admission_Diagnostic;
      begin
         if not HRA.Journal_Loader.Load_From_Root_Source
           (Root_Path   => Plan_Root_Path,
            Root_Text   => Plan_Root_Text,
            Observation => Plan_Loaded,
            Error_Msg   => Plan_Error)
         then
            Set_Diagnostic
              (Graph_Admission_Rejected,
               "plan.journal include graph failed to load: " &
               To_String (Plan_Error));
            return False;
         end if;

         if not HRA.Plan_Admission.Admit
           (Plan_Loaded.Value, Plan_Loaded.Evidence, Fresh_Plan, Fresh_Admit_Diag)
         then
            Set_Diagnostic
              (Graph_Admission_Rejected,
               "plan.journal admission failed: " &
               To_String (Fresh_Admit_Diag.Message));
            return False;
         end if;

         if not HRA.Plan_Admission.Same_Journal (Fresh_Plan, State.Plan_Journal) then
            Set_Diagnostic
              (Graph_Admission_Rejected,
               "Plan include graph drifted from loaded Household state");
            return False;
         end if;

         --  Check if Plan_ID already exists in the admitted graph (Retry path)
         if HRA.Plan.Contains
           (HRA.Plan_Admission.Plan_Ids_Of (Fresh_Plan), Plan_ID)
         then
            declare
               Existing_Found : Boolean := False;
               Existing_Entry : HRA.Plan_Admission.Plan_Transaction_Entry;
            begin
               for I in 1 .. HRA.Plan_Admission.Transaction_Count (Fresh_Plan) loop
                  declare
                     Item : constant HRA.Plan_Admission.Plan_Transaction_Entry :=
                       HRA.Plan_Admission.Transaction_At (Fresh_Plan, I);
                  begin
                     if Item.ID = Plan_ID then
                        Existing_Entry := Item;
                        Existing_Found := True;
                        exit;
                     end if;
                  end;
               end loop;

               if Existing_Found
                 and then Existing_Entry.Retirement.Kind = HRA.Plan_Admission.No_Retirement
                 and then Existing_Entry.Tx = Tx
               then
                  Prepared.Already_Present := True;
                  Prepared.Plan_Sources := Plan_Loaded.Sources;
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

      --  4. Fresh creation: prepare root candidate, graph admission, and account qualification
      if not HRA.Plan_Root_Candidate.Prepare
        (Plan_Root_Path, Plan_Root_Text, Block, Root, Root_Diag)
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
