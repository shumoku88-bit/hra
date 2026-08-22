with HRA.Dates;
with HRA.Issue_Close;
with HRA.Issues;

package body HRA.Issue_Closure_Preparation.Publication is

   use type HRA.Dates.Date;
   use type HRA.Issue_Close.Close_Disposition;
   use type HRA.Issues.Issue_Closed_Kind;
   use type HRA.Issues.Issue_Id;
   use type HRA.Issues.Issue_Status;
   use type HRA.Writer.Writer_Status;

   function Publish
     (Prepared : Prepared_Closure;
      Result   : out Publication_Result) return Boolean
   is
      Writer_Status : HRA.Writer.Writer_Status := HRA.Writer.Success;
      Writer_Error  : Unbounded_String;
      Inv           : HRA.Issues.Issues_Inventory;
      Issues_Diag   : HRA.Issues.Admission_Diagnostic;
      Target_Found  : Boolean := False;
      Target_Issue  : HRA.Issues.Household_Issue;
   begin
      --  Exact retry / already closed: no filesystem mutation
      if Is_Already_Closed (Prepared) then
         Result :=
           (Kind          => Completed,
            Writer_Status => HRA.Writer.Success,
            Message       => To_Unbounded_String
              ("Issue already closed with requested coordinates; publication skipped"),
            Completion    => Already_Closed);
         return True;
      end if;

      declare
         Guards : constant HRA.Writer.Source_Premise_Array (1 .. 0) :=
           [others => <>];
      begin
         --  Single-target atomic guarded replacement of issues.tsv
         if not HRA.Writer.Atomic_Replace_Exact_Guarded
           (Target_Path => To_String (Prepared.Target_Path),
            Expected    => HRA.Writer.Make_Expected_Source
              (To_String (Prepared.Expected_Text)),
            Candidate   => HRA.Writer.Make_Candidate_Source
              (HRA.Issue_Close.Text (Prepared.Candidate)),
            Guards      => Guards,
            Status      => Writer_Status,
            Error_Msg   => Writer_Error)
         then
            Result :=
              (Kind          => Failed,
               Writer_Status => Writer_Status,
               Message       => Writer_Error,
               Failure       => Writer_Failure);
            return False;
         end if;
      end;

      --  Post-publication domain validation
      if not HRA.Issues.Admit_Issues_TSV
        (HRA.Issue_Close.Text (Prepared.Candidate), Inv, Issues_Diag)
      then
         Result :=
           (Kind          => Failed,
            Writer_Status => HRA.Writer.Success,
            Message       => To_Unbounded_String
              ("post-publication issues admission failed"),
            Failure       => Post_Admission_Failure);
         return False;
      end if;

      for I in 1 .. HRA.Issues.Count (Inv) loop
         if HRA.Issues.Element (Inv, I).ID = Issue_Id_Of (Prepared) then
            Target_Issue := HRA.Issues.Element (Inv, I);
            Target_Found := True;
            exit;
         end if;
      end loop;

      declare
         Expected_Status : constant HRA.Issues.Issue_Status :=
           (case Disposition_Of (Prepared) is
               when HRA.Issue_Close.Resolve_Issue => HRA.Issues.Resolved,
               when HRA.Issue_Close.Drop_Issue    => HRA.Issues.Dropped);
      begin
         if not Target_Found
           or else Target_Issue.Status /= Expected_Status
           or else Target_Issue.Closed.Kind /= HRA.Issues.Closed_On
           or else Target_Issue.Closed.Closed_Date /= Closed_On_Of (Prepared)
         then
            Result :=
              (Kind          => Failed,
               Writer_Status => HRA.Writer.Success,
               Message       => To_Unbounded_String
                 ("post-publication Issue lifecycle verification failed"),
               Failure       => Post_Admission_Failure);
            return False;
         end if;
      end;

      Result :=
        (Kind          => Completed,
         Writer_Status => HRA.Writer.Success,
         Message       => To_Unbounded_String ("Issue closed successfully"),
         Completion    => Newly_Closed);
      return True;
   end Publish;

end HRA.Issue_Closure_Preparation.Publication;
