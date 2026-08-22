with HRA.Household_Actual_Preparation.Publication;

package body HRA.Household_Actual_Record is

   function Record_Status_For
     (Status : HRA.Household_Actual_Preparation.Preparation_Status)
      return Record_Status
   is
   begin
      case Status is
         when HRA.Household_Actual_Preparation.Success =>
            return Success;
         when HRA.Household_Actual_Preparation.Candidate_Rejected =>
            return Candidate_Rejected;
         when HRA.Household_Actual_Preparation.Root_Candidate_Rejected =>
            return Root_Candidate_Rejected;
         when HRA.Household_Actual_Preparation.Graph_Admission_Rejected =>
            return Graph_Admission_Rejected;
         when HRA.Household_Actual_Preparation.Account_Admission_Rejected =>
            return Account_Admission_Rejected;
      end case;
   end Record_Status_For;

   function Publish_Prepared
     (Prepared         : HRA.Household_Actual_Preparation.Prepared_Actual;
      Preparation_Diag : HRA.Household_Actual_Preparation.Preparation_Diagnostic;
      Diag             : out Record_Diagnostic) return Boolean
   is
      Publication_Diag : HRA.Actual_Publication.Publication_Diagnostic;
   begin
      if not HRA.Household_Actual_Preparation.Publication.Publish
        (Prepared, Publication_Diag)
      then
         Diag :=
           (Status      => Publication_Rejected,
            Preparation => Preparation_Diag,
            Publication => Publication_Diag,
            Message     => To_Unbounded_String
              ("Actual publication rejected: " &
               HRA.Actual_Publication.Publication_Status'Image
                 (Publication_Diag.Status) &
               (if Length (Publication_Diag.Message) > 0
                then ": " & To_String (Publication_Diag.Message)
                else "")));
         return False;
      end if;

      Diag :=
        (Status      => Success,
         Preparation => Preparation_Diag,
         Publication => Publication_Diag,
         Message     => Null_Unbounded_String);
      return True;
   end Publish_Prepared;

   function Record_Ordinary
     (State : HRA.Household.Household_State;
      Tx    : HRA.Ledger.Transaction;
      Diag  : out Record_Diagnostic) return Boolean
   is
      Prepared        : HRA.Household_Actual_Preparation.Prepared_Actual;
      Preparation_Diag : HRA.Household_Actual_Preparation.Preparation_Diagnostic;
   begin
      if not HRA.Household_Actual_Preparation.Prepare_Ordinary
        (State, Tx, Prepared, Preparation_Diag)
      then
         Diag :=
           (Status      => Record_Status_For (Preparation_Diag.Status),
            Preparation => Preparation_Diag,
            Publication => <>,
            Message     => Preparation_Diag.Message);
         return False;
      end if;

      return Publish_Prepared (Prepared, Preparation_Diag, Diag);
   end Record_Ordinary;

   function Record_Identified
     (State     : HRA.Household.Household_State;
      Tx        : HRA.Ledger.Transaction;
      Actual_ID : HRA.Actual_Admission.Actual_Id;
      Diag      : out Record_Diagnostic) return Boolean
   is
      Prepared        : HRA.Household_Actual_Preparation.Prepared_Actual;
      Preparation_Diag : HRA.Household_Actual_Preparation.Preparation_Diagnostic;
   begin
      if not HRA.Household_Actual_Preparation.Prepare_Identified
        (State, Tx, Actual_ID, Prepared, Preparation_Diag)
      then
         Diag :=
           (Status      => Record_Status_For (Preparation_Diag.Status),
            Preparation => Preparation_Diag,
            Publication => <>,
            Message     => Preparation_Diag.Message);
         return False;
      end if;

      return Publish_Prepared (Prepared, Preparation_Diag, Diag);
   end Record_Identified;

end HRA.Household_Actual_Record;
