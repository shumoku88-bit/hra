with ALedger.Journal;          use ALedger.Journal;
with ALedger.Canonical_Source; use ALedger.Canonical_Source;
with ALedger.Config_Support;

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
      Config_Diag : ALedger.Config_Support.Config_Diagnostic;

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

      function Validate_Account
        (Name : String; Expected : Account_Type; Path : String) return Boolean
      is
         Acc    : Account.Account;
         Status : Account_Status;
         Decl   : Account_Declaration;
      begin
         if not Create_Account (Name, Acc, Status)
           or else not Lookup_Declaration (Result.Registry, Acc, Decl)
         then
            Error_Msg := To_Unbounded_String
              (Path & ": Account is not declared in accounts.journal: " & Name);
            return False;
         elsif Decl.Acc_Type /= Expected then
            Error_Msg := To_Unbounded_String
              (Path & ": expected " & Account_Type_Image (Expected) &
               " Account, got " & Account_Type_Image (Decl.Acc_Type) & ": " & Name);
            return False;
         end if;
         return True;
      end Validate_Account;

      function Validate_Declared_Account
        (Name : String; Path : String) return Boolean
      is
         Acc    : Account.Account;
         Status : Account_Status;
         Decl   : Account_Declaration;
      begin
         if not Create_Account (Name, Acc, Status)
           or else not Lookup_Declaration (Result.Registry, Acc, Decl)
         then
            Error_Msg := To_Unbounded_String
              (Path & ": Account is not declared in accounts.journal: " & Name);
            return False;
         end if;
         return True;
      end Validate_Declared_Account;

      function Validate_Config_Accounts return Boolean is
         H : ALedger.Household_Config.Household_Configuration
           renames Result.Household_Policy;
      begin
         for Pool of Result.Budget_Policy.Backing_Pools loop
            for Name of Pool.Asset_Accounts loop
               if not Validate_Account (Name, Asset, "budget.toml backing pool") then return False; end if;
            end loop;
         end loop;
         for Envelope of Result.Budget_Policy.Envelopes loop
            for Name of Envelope.Expense_Accounts loop
               if not Validate_Account (Name, Expense, "budget.toml envelope") then return False; end if;
            end loop;
         end loop;
         if not Validate_Account (To_String (H.Cycle_Income_Account), Income, "household.toml cycle") then return False; end if;
         for Name of H.Unassigned_Accounts loop
            if not Validate_Account (Name, Budget, "household.toml unassigned account") then return False; end if;
         end loop;
         for Envelope of H.Envelopes loop
            if not Validate_Account (To_String (Envelope.Allocation_Account), Budget, "household.toml allocation account") then return False; end if;
            for Name of Envelope.Plan_Destination_Accounts loop
               if not Validate_Declared_Account (Name, "household.toml Plan destination") then return False; end if;
            end loop;
         end loop;
         for Selection of H.Daily_Target_Assets loop
            if not Validate_Account (To_String (Selection.Account), Asset, "household.toml Daily Target") then return False; end if;
         end loop;
         if H.Has_Account_Policy then
            for Name of H.Accounts.Liquid_Assets loop if not Validate_Account (Name, Asset, "household.toml Asset policy") then return False; end if; end loop;
            for Name of H.Accounts.Savings_Assets loop if not Validate_Account (Name, Asset, "household.toml Asset policy") then return False; end if; end loop;
            for Name of H.Accounts.Investment_Assets loop if not Validate_Account (Name, Asset, "household.toml Asset policy") then return False; end if; end loop;
            for Name of H.Accounts.Opening_Budget loop if not Validate_Account (Name, Budget, "household.toml Budget policy") then return False; end if; end loop;
            for Name of H.Accounts.Unassigned_Budget loop if not Validate_Account (Name, Budget, "household.toml Budget policy") then return False; end if; end loop;
            for Name of H.Accounts.Spent_Budget loop if not Validate_Account (Name, Budget, "household.toml Budget policy") then return False; end if; end loop;
            for Name of H.Accounts.Envelope_Budget loop if not Validate_Account (Name, Budget, "household.toml Budget policy") then return False; end if; end loop;
            for Name of H.Accounts.Unassigned_Role loop if not Validate_Account (Name, Budget, "household.toml Budget role") then return False; end if; end loop;
            for Name of H.Accounts.Dynamic_Role loop if not Validate_Account (Name, Budget, "household.toml Budget role") then return False; end if; end loop;
            for Name of H.Accounts.Execution_Role loop if not Validate_Account (Name, Budget, "household.toml Budget role") then return False; end if; end loop;
            for Name of H.Accounts.Daily_Group loop if not Validate_Account (Name, Budget, "household.toml Budget group") then return False; end if; end loop;
            for Name of H.Accounts.Flex_Group loop if not Validate_Account (Name, Budget, "household.toml Budget group") then return False; end if; end loop;
            for Name of H.Accounts.Reserve_Group loop if not Validate_Account (Name, Budget, "household.toml Budget group") then return False; end if; end loop;
            for Name of H.Accounts.Fixed_Expenses loop if not Validate_Account (Name, Expense, "household.toml Expense policy") then return False; end if; end loop;
            for Name of H.Accounts.Variable_Expenses loop if not Validate_Account (Name, Expense, "household.toml Expense policy") then return False; end if; end loop;
         end if;
         return True;
      end Validate_Config_Accounts;
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

      if not ALedger.Budget_Config.Parse_Budget_Policy
        (Text_For (Observation, Budget_Config_Source),
         Result.Budget_Policy, Config_Diag)
      then
         Error_Msg := To_Unbounded_String
           (ALedger.Config_Support.Format_Diagnostic (Config_Diag));
         return False;
      end if;

      if not ALedger.Household_Config.Parse_Household_Configuration
        (Text_For (Observation, Household_Config_Source),
         Result.Budget_Policy, Result.Household_Policy, Config_Diag)
      then
         Error_Msg := To_Unbounded_String
           (ALedger.Config_Support.Format_Diagnostic (Config_Diag));
         return False;
      end if;

      if not ALedger.Report_Config.Parse_Report_Configuration
        (Text_For (Observation, Report_Config_Source),
         Result.Report_Policy, Config_Diag)
      then
         Error_Msg := To_Unbounded_String
           (ALedger.Config_Support.Format_Diagnostic (Config_Diag));
         return False;
      end if;

      if not Validate_Config_Accounts then
         return False;
      end if;

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

      Result.Combined_Ledger.Registry := Result.Registry;
      Result.Actual_Ledger.Registry   := Result.Registry;
      Result.Plan_Ledger.Registry     := Result.Registry;
      Result.Budget_Ledger.Registry   := Result.Registry;

      State := Result;
      Error_Msg := Null_Unbounded_String;
      return True;
   end Load_Canonical_Household;

end ALedger.Household;
