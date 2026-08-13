with ALedger.Journal;          use ALedger.Journal;
with ALedger.Canonical_Source; use ALedger.Canonical_Source;

package body ALedger.Household is

   function Empty_Household_State return Household_State is
      State : Household_State;
   begin
      State.Registry        := Empty_Registry;
      State.Actual_Ledger   := Empty_Ledger;
      State.Plan_Ledger     := Empty_Ledger;
      State.Budget_Ledger   := Empty_Ledger;
      State.Combined_Ledger := Empty_Ledger;
      return State;
   end Empty_Household_State;

   function Load_Canonical_Household
     (Root_Dir  : String;
      State     : out Household_State;
      Error_Msg : out Unbounded_String) return Boolean
   is
      Result      : Household_State := Empty_Household_State;
      Observation : Source_Observation;
      Diag        : Parse_Diagnostic;

      procedure Merge_Declarations (From : Ledger.Ledger) is
      begin
         for Decl of Declarations (From.Registry) loop
            Register_Or_Update_Account (Result.Registry, Decl);
         end loop;
      end Merge_Declarations;

      function Merge_Transactions (From : Ledger.Ledger) return Boolean is
      begin
         for Tx of From.Transactions loop
            declare
               Status : Transaction_Error;
            begin
               if not Add_Transaction (Result.Combined_Ledger, Tx, Status) then
                  Error_Msg := To_Unbounded_String
                    ("validated source produced an inadmissible transaction");
                  return False;
               end if;
            end;
         end loop;
         return True;
      end Merge_Transactions;

      function Parse_Named_Journal
        (Source : Source_Name;
         Target : out Ledger.Ledger) return Boolean
      is
      begin
         if not Parse_Journal_Text
           (Text_For (Observation, Source),
            Path_For (Observation.Paths, Source),
            Target,
            Diag)
         then
            Error_Msg := To_Unbounded_String (Format_Diagnostic (Diag));
            return False;
         end if;
         return True;
      end Parse_Named_Journal;
   begin
      --  One complete eight-source observation precedes semantic admission.
      --  No source-specific fallback or second filesystem read is allowed.
      if not Observe_Canonical_Sources
        (Root_Dir, Observation, Error_Msg)
      then
         return False;
      end if;

      Result.Root_Path := Observation.Root_Path;
      Result.Paths     := Observation.Paths;
      Result.Sources   := Observation;

      declare
         Accounts : Ledger.Ledger;
      begin
         if not Parse_Named_Journal (Accounts_Source, Accounts) then
            return False;
         end if;
         Result.Registry := Accounts.Registry;
      end;

      if not Parse_Named_Journal (Actual_Source, Result.Actual_Ledger) then
         return False;
      end if;
      Merge_Declarations (Result.Actual_Ledger);
      if not Merge_Transactions (Result.Actual_Ledger) then
         return False;
      end if;

      if not Parse_Named_Journal (Plan_Source, Result.Plan_Ledger) then
         return False;
      end if;
      Merge_Declarations (Result.Plan_Ledger);

      if not Parse_Named_Journal
        (Budget_Journal_Source, Result.Budget_Ledger)
      then
         return False;
      end if;
      Merge_Declarations (Result.Budget_Ledger);
      if not Merge_Transactions (Result.Budget_Ledger) then
         return False;
      end if;

      if not Parse_Issues_TSV
        (Text_For (Observation, Issues_Source), Result.Issues)
      then
         Error_Msg := To_Unbounded_String
           (Path_For (Observation.Paths, Issues_Source) &
            ": invalid issues.tsv");
         return False;
      end if;

      --  budget.toml, household.toml, and report.toml are part of the exact
      --  observation now.  Typed semantic admission is the next migration
      --  chapter; callers must not treat their presence as parsed policy.
      Result.Combined_Ledger.Registry := Result.Registry;
      Result.Actual_Ledger.Registry   := Result.Registry;
      Result.Plan_Ledger.Registry     := Result.Registry;
      Result.Budget_Ledger.Registry   := Result.Registry;

      State := Result;
      Error_Msg := Null_Unbounded_String;
      return True;
   end Load_Canonical_Household;

end ALedger.Household;
