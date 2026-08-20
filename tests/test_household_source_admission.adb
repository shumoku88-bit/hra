with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO; use Ada.Text_IO;
with HRA.Canonical_Source; use HRA.Canonical_Source;
with HRA.Household;

procedure Test_Household_Source_Admission is
   Passed_Count : Natural := 0;
   Failed_Count : Natural := 0;

   procedure Assert (Condition : Boolean; Test_Name : String) is
   begin
      if Condition then
         Put_Line ("[PASS] " & Test_Name);
         Passed_Count := Passed_Count + 1;
      else
         Put_Line ("[FAIL] " & Test_Name);
         Failed_Count := Failed_Count + 1;
      end if;
   end Assert;

   Observation : Source_Observation;
   Candidate   : Source_Observation;
   State       : HRA.Household.Household_State;
   Err         : Unbounded_String;

   Original_Entitlement : constant String :=
     "2026-08-01 origin JPY ; clean Envelope epoch" & ASCII.LF &
     "2026-08-01 transfer unallocated -> coffee 1000 JPY" & ASCII.LF;

begin
   Put_Line ("--- Testing source-observation Household admission ---");

   Observation.Root_Path := To_Unbounded_String ("/tmp/hra_candidate_admission");
   Observation.Paths :=
     HRA.Household.Resolve_Source_Paths
       (To_String (Observation.Root_Path));

   Observation.Texts (Accounts_Source) := To_Unbounded_String
     ("account assets:wallet" & ASCII.LF &
      "  ; type: Asset" & ASCII.LF &
      "account expenses:coffee" & ASCII.LF &
      "  ; type: Expense" & ASCII.LF &
      "account income:salary" & ASCII.LF &
      "  ; type: Income" & ASCII.LF);

   Observation.Texts (Actual_Source) := To_Unbounded_String
     ("2026-08-13 Coffee Purchase" & ASCII.LF &
      "    expenses:coffee         500 JPY" & ASCII.LF &
      "    assets:wallet          -500 JPY" & ASCII.LF);

   Observation.Texts (Plan_Source) := Null_Unbounded_String;
   Observation.Texts (Entitlement_Source) :=
     To_Unbounded_String (Original_Entitlement);

   Observation.Texts (Envelope_Config_Source) := To_Unbounded_String
     ("[[backing-pools]]" & ASCII.LF &
      "id = ""liquid""" & ASCII.LF &
      "asset-accounts = [""assets:wallet""]" & ASCII.LF &
      "[[envelopes]]" & ASCII.LF &
      "id = ""coffee""" & ASCII.LF &
      "label = ""Coffee""" & ASCII.LF &
      "pacing = ""daily""" & ASCII.LF &
      "backing-pool = ""liquid""" & ASCII.LF);

   Observation.Texts (Household_Config_Source) := To_Unbounded_String
     ("[cycle]" & ASCII.LF &
      "mode = ""income-anchor""" & ASCII.LF &
      "income-account = ""income:salary""" & ASCII.LF &
      "[money]" & ASCII.LF &
      "primary-commodity = ""JPY""" & ASCII.LF &
      "[envelope-history]" & ASCII.LF &
      "identities = [""coffee""]" & ASCII.LF &
      "[[envelope-history.expense-routing]]" & ASCII.LF &
      "effective-from = ""initial""" & ASCII.LF &
      "expense-account = ""expenses:coffee""" & ASCII.LF &
      "route = ""managed""" & ASCII.LF &
      "target = ""coffee""" & ASCII.LF &
      "note = ""candidate admission routing""" & ASCII.LF);

   Observation.Texts (Report_Config_Source) := To_Unbounded_String
     ("[presentation.amounts]" & ASCII.LF &
      "negative-style = ""parentheses""" & ASCII.LF &
      "[reports.trial-balance]" & ASCII.LF &
      "as-of = ""latest""" & ASCII.LF &
      "[reports.balance-sheet]" & ASCII.LF &
      "as-of = ""latest""" & ASCII.LF &
      "[reports.profit-and-loss]" & ASCII.LF &
      "from = ""beginning""" & ASCII.LF &
      "through = ""latest""" & ASCII.LF &
      "[reports.daily-flow]" & ASCII.LF &
      "from = ""beginning""" & ASCII.LF &
      "through = ""latest""" & ASCII.LF &
      "max-date-columns = 7" & ASCII.LF &
      "[reports.monthly-accounts]" & ASCII.LF &
      "from = ""beginning""" & ASCII.LF &
      "through = ""latest""" & ASCII.LF &
      "[reports.recent-transactions]" & ASCII.LF &
      "through = ""latest""" & ASCII.LF &
      "count = 10" & ASCII.LF);

   Observation.Texts (Issues_Source) := To_Unbounded_String
     ("issue_id" & ASCII.HT & "status" & ASCII.HT & "date" & ASCII.HT &
      "due" & ASCII.HT & "closed" & ASCII.HT & "category" & ASCII.HT &
      "title" & ASCII.HT & "amount" & ASCII.HT & "currency" & ASCII.HT &
      "details" & ASCII.LF);

   Assert
     (HRA.Household.Admit_Canonical_Household
        (Observation, State, Err),
      "Admit complete canonical Household from in-memory source observation");
   Assert
     (Text_For (State.Sources, Actual_Source) =
        Text_For (Observation, Actual_Source),
      "Admitted Household retains exact supplied source bytes");

   Candidate := Observation;
   Candidate.Texts (Entitlement_Source) := To_Unbounded_String
     (Original_Entitlement &
      "2026-08-02 transfer coffee -> rogue 1 JPY" & ASCII.LF);

   Assert
     (not HRA.Household.Admit_Canonical_Household
        (Candidate, State, Err)
      and then Index (To_String (Err), "unknown Envelope endpoint") > 0,
      "Candidate source set fails the same native Entitlement admission law");
   Assert
     (Text_For (Observation, Entitlement_Source) = Original_Entitlement,
      "Candidate replacement does not mutate the original source observation");
   Assert
     (HRA.Household.Admit_Canonical_Household
        (Observation, State, Err),
      "Original source observation remains admissible after rejected candidate");

   Put_Line
     (Natural'Image (Passed_Count) & " passed, " &
      Natural'Image (Failed_Count) & " failed");

   if Failed_Count > 0 then
      raise Program_Error with "Household source admission tests failed";
   end if;
end Test_Household_Source_Admission;
