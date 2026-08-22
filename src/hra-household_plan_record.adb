with HRA.Household_Plan_Preparation.Publication;

package body HRA.Household_Plan_Record is

   use type HRA.Household_Plan_Preparation.Publication.Completion_Kind;

   function Record_Status_For
     (Status : HRA.Household_Plan_Preparation.Preparation_Status)
      return Record_Status
   is
   begin
      case Status is
         when HRA.Household_Plan_Preparation.Success =>
            return Success;
         when HRA.Household_Plan_Preparation.Already_Present_As_Requested =>
            return Already_Present;
         when HRA.Household_Plan_Preparation.Candidate_Rejected =>
            return Candidate_Rejected;
         when HRA.Household_Plan_Preparation.Root_Candidate_Rejected =>
            return Root_Candidate_Rejected;
         when HRA.Household_Plan_Preparation.Graph_Admission_Rejected =>
            return Graph_Admission_Rejected;
         when HRA.Household_Plan_Preparation.Account_Admission_Rejected =>
            return Account_Admission_Rejected;
         when HRA.Household_Plan_Preparation.Conflicting_Plan_Already_Exists =>
            return Conflicting_Plan_Already_Exists;
      end case;
   end Record_Status_For;

   function Record_Pending
     (State   : HRA.Household.Household_State;
      Plan_ID : HRA.Plan.Plan_Id;
      Tx      : HRA.Ledger.Transaction;
      Diag    : out Record_Diagnostic) return Boolean
   is
      Prepared : HRA.Household_Plan_Preparation.Prepared_Plan;
      Prep_Diag : HRA.Household_Plan_Preparation.Preparation_Diagnostic;
      Pub_Result :
        HRA.Household_Plan_Preparation.Publication.Publication_Result;
   begin
      if not HRA.Household_Plan_Preparation.Prepare
        (State, Plan_ID, Tx, Prepared, Prep_Diag)
      then
         Diag :=
           (Status      => Record_Status_For (Prep_Diag.Status),
            Preparation => Prep_Diag,
            Publication => <>,
            Message     => Prep_Diag.Message);
         return False;
      end if;

      if not HRA.Household_Plan_Preparation.Publication.Publish
        (Prepared, Pub_Result)
      then
         Diag :=
           (Status      => Publication_Rejected,
            Preparation => Prep_Diag,
            Publication => Pub_Result,
            Message     =>
              (if Length (Pub_Result.Message) > 0
               then Pub_Result.Message
               else To_Unbounded_String ("Plan publication rejected")));
         return False;
      end if;

      Diag :=
        (Status      =>
           (if Pub_Result.Completion =
                 HRA.Household_Plan_Preparation.Publication.Already_Present
            then Already_Present
            else Success),
         Preparation => Prep_Diag,
         Publication => Pub_Result,
         Message     => Null_Unbounded_String);
      return True;
   end Record_Pending;

end HRA.Household_Plan_Record;
