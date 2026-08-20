with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA.Account;

package body HRA.Household_Home_Observation is

   use type HRA.Dates.Date;
   use type HRA.Cycle_Observation.Resolve_Status;
   use type HRA.Plan_Observation.Admission_Status;

   function Is_Available (Obs : Actual_Home_Observation) return Boolean is
     (Obs.Status = Available);

   function Transaction_Count (Obs : Actual_Home_Observation) return Natural is
     (Natural (Obs.Transactions.Length));

   function Is_Available (Obs : Plan_Home_Observation) return Boolean is
     (Obs.Status = Available);

   function Open_Plan_Count (Obs : Plan_Home_Observation) return Natural is
     (Natural (Obs.Open_Plans.Length));

   function Is_Available (Obs : Issue_Home_Observation) return Boolean is
     (Obs.Status = Available);

   function Due_Issue_Count (Obs : Issue_Home_Observation) return Natural is
     (Natural (Obs.Due_Issues.Length));

   function Is_Available (Obs : Cycle_Home_Observation) return Boolean is
     (Obs.Status = Available);

   function Observed_Through (Obs : Home_Observation) return HRA.Dates.Date is
     (Obs.Observed_Through);

   function Selected_Day (Obs : Home_Observation) return HRA.Dates.Date is
     (Obs.Selected_Day);

   function Actual (Obs : Home_Observation) return Actual_Home_Observation is
     (Obs.Actual);

   function Plan (Obs : Home_Observation) return Plan_Home_Observation is
     (Obs.Plan);

   function Issue (Obs : Home_Observation) return Issue_Home_Observation is
     (Obs.Issue);

   function Cycle (Obs : Home_Observation) return Cycle_Home_Observation is
     (Obs.Cycle);

   function Selected_Attention (Obs : Home_Observation) return Attention_Observation is
     (Day_Attention (Obs, Obs.Selected_Day));

   function Day_Attention
     (Obs : Home_Observation;
      Day : HRA.Dates.Date) return Attention_Observation
   is
      Result : Attention_Observation;
   begin
      --  Plan Attention
      if Obs.Plan.Status = Unavailable then
         Result.Plan_Scheduled := Unavailable;
      else
         Result.Plan_Scheduled := Absent;
         for P of Obs.All_Open_Plans loop
            if P.Tx.Date = Day then
               Result.Plan_Scheduled := Present;
               exit;
            end if;
         end loop;
      end if;

      --  Issue Attention
      if HRA.Issue_Observation.Has_Undetermined_Due_On (Obs.Issue_Context, Day) then
         Result.Issue_Due := Unavailable;
      else
         declare
            Dues : constant HRA.Issue_Observation.Observed_Issue_Vectors.Vector :=
              HRA.Issue_Observation.Due_Issues_On (Obs.Issue_Context, Day);
         begin
            if not Dues.Is_Empty then
               Result.Issue_Due := Present;
            else
               Result.Issue_Due := Absent;
            end if;
         end;
      end if;

      --  Cycle Attention
      if Obs.Cycle.Status = Unavailable then
         Result.Cycle_End := Unavailable;
      else
         declare
            Prev_Win : constant HRA.Cycle_Observation.Cycle_Window :=
              Obs.Cycle.Observation.Previous_Window;
            Curr_Win : constant HRA.Cycle_Observation.Cycle_Window :=
              Obs.Cycle.Observation.Current_Window;
            Prev_End : constant HRA.Dates.Date :=
              HRA.Dates.Previous (HRA.Cycle_Observation.End_Exclusive (Prev_Win));
            Curr_End : constant HRA.Dates.Date :=
              HRA.Dates.Previous (HRA.Cycle_Observation.End_Exclusive (Curr_Win));
         begin
            if Day = Prev_End or else Day = Curr_End then
               Result.Cycle_End := Present;
            elsif HRA.Cycle_Observation.Contains (Prev_Win, Day)
              or else HRA.Cycle_Observation.Contains (Curr_Win, Day)
            then
               Result.Cycle_End := Absent;
            else
               Result.Cycle_End := Unavailable;
            end if;
         end;
      end if;

      return Result;
   end Day_Attention;

   function Observe
     (Observed_Through : HRA.Dates.Date;
      Selected_Day     : HRA.Dates.Date;
      State            : HRA.Household.Household_State) return Home_Observation
   is
      Result : Home_Observation;

      --  Plan evaluation
      Plan_Diag : HRA.Plan_Observation.Admission_Diagnostic;
      Plan_Ok   : Boolean := False;

      --  Cycle evaluation
      Income_Acc : HRA.Account.Account;
      Cycle_Obs  : HRA.Cycle_Observation.Observation;
      Cycle_Stat : HRA.Cycle_Observation.Resolve_Status;
   begin
      Result.Observed_Through := Observed_Through;
      Result.Selected_Day     := Selected_Day;

      --  1. Actual Projection:
      --  Day-local projection is only available when Selected_Day <= Observed_Through.
      --  If Selected_Day > Observed_Through, Actual is Unavailable (never leak future Actuals).
      if Selected_Day <= Observed_Through then
         declare
            Selected_Txs : HRA.Ledger.Transaction_Vectors.Vector;
         begin
            for Tx of State.Actual_Ledger.Transactions loop
               if Tx.Date = Selected_Day then
                  Selected_Txs.Append (Tx);
               end if;
            end loop;
            Result.Actual :=
              (Status       => Available,
               Transactions => Selected_Txs);
         end;
      else
         Result.Actual :=
           (Status => Unavailable,
            Reason => Observation_Horizon_Exceeded);
      end if;

      --  2. Plan Projection:
      --  Evaluate role-neutral Plan observation as of Observed_Through.
      Plan_Ok := HRA.Plan_Observation.Observe_Open_Plans
        (Plan_Ledger     => State.Plan_Ledger,
         Plan_Evidence   => State.Plan_Evidence,
         Actual_Ledger   => State.Actual_Ledger,
         Actual_Evidence => State.Actual_Evidence,
         As_Of_Date      => Observed_Through,
         Result          => Result.All_Open_Plans,
         Diag            => Plan_Diag);

      if Plan_Ok then
         declare
            Selected_Plans : HRA.Plan_Observation.Open_Plan_Vectors.Vector;
         begin
            for P of Result.All_Open_Plans loop
               if P.Tx.Date = Selected_Day then
                  Selected_Plans.Append (P);
               end if;
            end loop;
            Result.Plan :=
              (Status     => Available,
               Open_Plans => Selected_Plans);
         end;
      else
         Result.Plan :=
           (Status => Unavailable,
            Error  => Plan_Diag);
      end if;

      --  3. Issue Projection:
      --  Evaluate temporal Issue lifecycle state as of Observed_Through.
      Result.Issue_Context :=
        HRA.Issue_Observation.Observe (State.Issues, Observed_Through);

      if HRA.Issue_Observation.Has_Undetermined_Due_On
           (Result.Issue_Context, Selected_Day)
      then
         Result.Issue :=
           (Status => Unavailable,
            Reason => Closure_Timing_Undetermined);
      else
         declare
            Selected_Due_Issues : constant
              HRA.Issue_Observation.Observed_Issue_Vectors.Vector :=
                HRA.Issue_Observation.Due_Issues_On
                  (Result.Issue_Context, Selected_Day);
         begin
            Result.Issue :=
              (Status     => Available,
               Due_Issues => Selected_Due_Issues);
         end;
      end if;

      --  4. Cycle Projection:
      --  Evaluate cycle observation as of Observed_Through.
      if not Plan_Ok then
         Result.Cycle :=
           (Status  => Unavailable,
            Failure =>
              (Reason     => Plan_Dependency_Unavailable,
               Plan_Error => Plan_Diag));
      else
         Income_Acc :=
           HRA.Account.Make_Account
             (To_String (State.Household_Policy.Cycle_Income_Account));

         if HRA.Cycle_Observation.Observe
              (Observed_Through => Observed_Through,
               Actual_Ledger    => State.Actual_Ledger,
               Open_Plans       => Result.All_Open_Plans,
               Registry         => State.Registry,
               Income_Account   => Income_Acc,
               Result           => Cycle_Obs,
               Status           => Cycle_Stat)
         then
            Result.Cycle :=
              (Status      => Available,
               Observation => Cycle_Obs);
         else
            Result.Cycle :=
              (Status  => Unavailable,
               Failure =>
                 (Reason      => Cycle_Resolution_Failed,
                  Cycle_Error => Cycle_Stat));
         end if;
      end if;

      return Result;
   end Observe;

end HRA.Household_Home_Observation;
