with HRA.Canonical_Source;

package body HRA.Issue_Closure_Preparation is

   use type HRA.Dates.Date;
   use type HRA.Issue_Close.Close_Disposition;
   use type HRA.Issues.Issue_Closed_Kind;
   use type HRA.Issues.Issue_Id;
   use type HRA.Issues.Issue_Status;

   function Prepare
     (State       : HRA.Household.Household_State;
      Issue_ID    : HRA.Issues.Issue_Id;
      Disposition : HRA.Issue_Close.Close_Disposition;
      Closed_On   : HRA.Dates.Date;
      Prepared    : out Prepared_Closure;
      Diag        : out Preparation_Diagnostic) return Boolean
   is
      Current_Issues_Text : constant String :=
        HRA.Canonical_Source.Text_For
          (State.Sources, HRA.Canonical_Source.Issues_Source);
      Current_Issues_Path : constant String :=
        HRA.Canonical_Source.Path_For
          (State.Sources.Paths, HRA.Canonical_Source.Issues_Source);

      Target_Issue : HRA.Issues.Household_Issue;
      Found        : Boolean := False;
      Candidate    : HRA.Issue_Close.Candidate_Source;
      Close_Diag   : HRA.Issue_Close.Close_Diagnostic;
   begin
      Prepared :=
        (Target_Path        => To_Unbounded_String (Current_Issues_Path),
         Expected_Text      => To_Unbounded_String (Current_Issues_Text),
         Candidate          => Candidate,
         Target_Issue_ID    => Issue_ID,
         Target_Disposition => Disposition,
         Target_Closed_On   => Closed_On,
         Already_Closed     => False);

      Diag :=
        (Status      => Success,
         Issue_Close =>
           (Status  => HRA.Issue_Close.Success,
            Issue   => HRA.Issues.To_Unbounded (Issue_ID),
            Source  =>
              (Status      => HRA.Issues.Success,
               Line_Number => 0,
               Issue_ID    => Null_Unbounded_String,
               Message     => Null_Unbounded_String),
            Message => Null_Unbounded_String),
         Message     => Null_Unbounded_String);

      --  Locate the target Issue in the admitted Household State
      for I in 1 .. HRA.Issues.Count (State.Issues) loop
         if HRA.Issues.Element (State.Issues, I).ID = Issue_ID then
            Target_Issue := HRA.Issues.Element (State.Issues, I);
            Found := True;
            exit;
         end if;
      end loop;

      if not Found then
         Diag.Status := Issue_Close_Rejected;
         Diag.Issue_Close.Status := HRA.Issue_Close.Issue_Not_Found;
         Diag.Message := To_Unbounded_String
           ("Issue identity is not present in current source");
         return False;
      end if;

      --  If the Issue is Open, prepare a new close candidate
      if Target_Issue.Status = HRA.Issues.Open then
         if not HRA.Issue_Close.Prepare_Close
           (Existing_Source => Current_Issues_Text,
            Issue_ID        => Issue_ID,
            Disposition     => Disposition,
            Closed_On       => Closed_On,
            Candidate       => Candidate,
            Diag            => Close_Diag)
         then
            Diag :=
              (Status      => Issue_Close_Rejected,
               Issue_Close => Close_Diag,
               Message     => To_Unbounded_String
                 ("Issue close candidate preparation failed: " &
                  To_String (Close_Diag.Message)));
            return False;
         end if;

         Prepared.Candidate := Candidate;
         Prepared.Already_Closed := False;
         return True;
      end if;

      --  If the Issue is not Open, check exact retry recognition law:
      --  Must match requested disposition (Resolved / Dropped) and exact requested Closed_On.
      declare
         Expected_Status : constant HRA.Issues.Issue_Status :=
           (case Disposition is
               when HRA.Issue_Close.Resolve_Issue => HRA.Issues.Resolved,
               when HRA.Issue_Close.Drop_Issue    => HRA.Issues.Dropped);
         Is_Exact_Retry : constant Boolean :=
           Target_Issue.Status = Expected_Status
           and then Target_Issue.Closed.Kind = HRA.Issues.Closed_On
           and then Target_Issue.Closed.Closed_Date = Closed_On;
      begin
         if Is_Exact_Retry then
            Prepared.Already_Closed := True;
            Diag.Status := Already_Closed_As_Requested;
            Diag.Message := To_Unbounded_String
              ("Issue is already closed with exact requested disposition and closure date");
            return True;
         else
            --  Not open and does not match exact retry parameters -> reject closed
            Diag.Status := Issue_Close_Rejected;
            Diag.Issue_Close.Status := HRA.Issue_Close.Issue_Not_Open;
            Diag.Message := To_Unbounded_String
              ("Issue is not Open and does not match requested closure coordinates");
            return False;
         end if;
      end;
   end Prepare;

end HRA.Issue_Closure_Preparation;
