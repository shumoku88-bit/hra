with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO; use Ada.Text_IO;
with HRA.Canonical_Source; use HRA.Canonical_Source;
with HRA.Cycle_Observation;
with HRA.Dates;
with HRA.Envelope_Consumption;
with HRA.Household;
with HRA.Household_Envelope_Cycle_Comparison;
with HRA.Household_Temporal;
with HRA.Money;

procedure Test_Household_Temporal_Cycle_Context is
   use type HRA.Dates.Date;
   use type HRA.Household_Temporal.Cycle_Comparison_View_Status;
   use type HRA.Money.Quantity;

   package Comparison renames HRA.Household_Envelope_Cycle_Comparison;

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

   function D (S : String) return HRA.Dates.Date is
      Value  : HRA.Dates.Date;
      Status : HRA.Dates.Date_Status;
   begin
      if not HRA.Dates.Parse (S, Value, Status) then
         raise Program_Error with "invalid test date: " & S;
      end if;
      return Value;
   end D;

   function JPY_Amount (Balance : HRA.Money.Balance) return HRA.Money.Quantity is
   begin
      return HRA.Money.Lookup_Balance
        (Balance, HRA.Money.Make_Commodity ("JPY"));
   end JPY_Amount;

   Observation : HRA.Canonical_Source.Source_Observation;
   State       : HRA.Household.Household_State;
   Err         : Unbounded_String;
   Result      : Comparison.Comparison_Observation;
   Diag        : HRA.Household_Temporal.Cycle_Comparison_View_Diagnostic;

begin
   Put_Line ("--- Testing Household temporal cycle context ---");

   Observation.Root_Path := To_Unbounded_String ("/tmp/hra_temporal_cycle_context");
   Observation.Paths :=
     HRA.Household.Resolve_Source_Paths (To_String (Observation.Root_Path));

   Observation.Texts (Accounts_Source) := To_Unbounded_String
     ("account assets:wallet" & ASCII.LF &
      "  ; type: Asset" & ASCII.LF &
      "account expenses:coffee" & ASCII.LF &
      "  ; type: Expense" & ASCII.LF &
      "account income:salary" & ASCII.LF &
      "  ; type: Income" & ASCII.LF &
      "account budget:coffee" & ASCII.LF &
      "  ; type: Budget" & ASCII.LF &
      "account budget:unassigned" & ASCII.LF &
      "  ; type: Budget" & ASCII.LF &
      "account budget:opening" & ASCII.LF &
      "  ; type: Budget" & ASCII.LF);

   Observation.Texts (Actual_Source) := To_Unbounded_String
     ("2026-06-20 Pre-cycle Coffee" & ASCII.LF &
      "    expenses:coffee           5 JPY" & ASCII.LF &
      "    assets:wallet            -5 JPY" & ASCII.LF & ASCII.LF &
      "2026-07-01 July Salary" & ASCII.LF &
      "    assets:wallet          1000 JPY" & ASCII.LF &
      "    income:salary         -1000 JPY" & ASCII.LF & ASCII.LF &
      "2026-07-05 July Coffee" & ASCII.LF &
      "    expenses:coffee          10 JPY" & ASCII.LF &
      "    assets:wallet           -10 JPY" & ASCII.LF & ASCII.LF &
      "2026-08-01 August Salary" & ASCII.LF &
      "    assets:wallet          1000 JPY" & ASCII.LF &
      "    income:salary         -1000 JPY" & ASCII.LF & ASCII.LF &
      "2026-08-03 August Coffee" & ASCII.LF &
      "    expenses:coffee          40 JPY" & ASCII.LF &
      "    assets:wallet           -40 JPY" & ASCII.LF & ASCII.LF &
      "2026-08-04 August Refund" & ASCII.LF &
      "    expenses:coffee         -10 JPY" & ASCII.LF &
      "    assets:wallet            10 JPY" & ASCII.LF);

   Observation.Texts (Plan_Source) := To_Unbounded_String
     ("2026-09-01 September Salary" & ASCII.LF &
      "    ; plan-id: plan-september-salary" & ASCII.LF &
      "    assets:wallet          1000 JPY" & ASCII.LF &
      "    income:salary         -1000 JPY" & ASCII.LF);

   Observation.Texts (Budget_Journal_Source) := To_Unbounded_String
     ("2026-06-15 Envelope stock epoch" & ASCII.LF &
      "    budget:opening             0 JPY" & ASCII.LF &
      "    budget:unassigned          0 JPY" & ASCII.LF & ASCII.LF &
      "2026-07-01 July Coffee grant" & ASCII.LF &
      "    budget:unassigned        -50 JPY" & ASCII.LF &
      "    budget:coffee             50 JPY" & ASCII.LF & ASCII.LF &
      "2026-08-01 August Coffee grant" & ASCII.LF &
      "    budget:unassigned       -100 JPY" & ASCII.LF &
      "    budget:coffee            100 JPY" & ASCII.LF);

   Observation.Texts (Budget_Config_Source) := To_Unbounded_String
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
      "[budget]" & ASCII.LF &
      "opening-accounts = [""budget:opening""]" & ASCII.LF &
      "unassigned-accounts = [""budget:unassigned""]" & ASCII.LF &
      "[[budget.envelopes]]" & ASCII.LF &
      "id = ""coffee""" & ASCII.LF &
      "allocation-account = ""budget:coffee""" & ASCII.LF &
      "[envelope-history]" & ASCII.LF &
      "identities = [""coffee""]" & ASCII.LF &
      "[[envelope-history.expense-routing]]" & ASCII.LF &
      "effective-from = ""initial""" & ASCII.LF &
      "expense-account = ""expenses:coffee""" & ASCII.LF &
      "route = ""managed""" & ASCII.LF &
      "target = ""coffee""" & ASCII.LF &
      "note = ""temporal cycle context routing""" & ASCII.LF);

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
     ("issue_id" & ASCII.HT & "status" & ASCII.LF);

   Assert
     (HRA.Household.Admit_Canonical_Household
        (Observation, State, Err),
      "Setup: admit Household with previous/current/future income anchors");

   declare
      Succeeded : constant Boolean :=
        HRA.Household_Temporal.Observe_Envelope_Aligned_Previous_Cycle
          (D ("2026-08-10"), State, Result, Diag);
   begin
      if not Succeeded then
         Put_Line
           ("[DIAG] temporal cycle-comparison status = " &
            HRA.Household_Temporal.Cycle_Comparison_View_Status'Image
              (Diag.Status));
      end if;

      Assert
        (Succeeded
           and then Diag.Status =
             HRA.Household_Temporal.Cycle_Comparison_View_Success,
         "Household Temporal selects aligned previous cycle from admitted anchors");

      if Succeeded then
         Assert
           (HRA.Cycle_Observation.Start_Date (Result.Current_Window) =
              D ("2026-08-01")
              and then HRA.Cycle_Observation.End_Exclusive
                (Result.Current_Window) = D ("2026-09-01"),
            "Temporal current cycle uses latest Actual and future Plan anchors");
         Assert
           (HRA.Cycle_Observation.Start_Date (Result.Baseline_Window) =
              D ("2026-07-01")
              and then HRA.Cycle_Observation.End_Exclusive
                (Result.Baseline_Window) = D ("2026-08-01"),
            "Cycle observation retains immediately previous Actual-anchor window");
         Assert
           (Result.Current_Through = D ("2026-08-10")
              and then Result.Baseline_Through = D ("2026-07-10"),
            "Temporal view aligns previous cycle by equal elapsed day");
         Assert
           (Natural (Result.Lines.Length) = 1,
            "Temporal view preserves current Envelope membership and order");

         if Natural (Result.Lines.Length) = 1 then
            declare
               Line : constant Comparison.Comparison_Line :=
                 Result.Lines.Element (1);
            begin
               Assert
                 (JPY_Amount
                    (HRA.Envelope_Consumption.Net_Consumption
                       (Line.Current_Consumption)) = 30.0
                    and then JPY_Amount
                      (HRA.Envelope_Consumption.Net_Consumption
                         (Line.Baseline_Consumption)) = 10.0,
                  "Temporal view keeps current/baseline cycle activity bounded");
               Assert
                 (JPY_Amount (Comparison.Consumption_Net_Difference (Line)) = 20.0,
                  "Temporal view derives aligned cycle activity difference");
               Assert
                 (JPY_Amount (Line.Current_Remaining) = 105.0
                    and then JPY_Amount (Line.Baseline_Remaining) = 35.0,
                  "Temporal view keeps point-in-time stock positions distinct from activity");
            end;
         end if;
      end if;
   end;

   Put_Line
     (Natural'Image (Passed_Count) & " passed, " &
      Natural'Image (Failed_Count) & " failed");

   if Failed_Count > 0 then
      raise Program_Error with "Household temporal cycle-context tests failed";
   end if;
end Test_Household_Temporal_Cycle_Context;
