with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO; use Ada.Text_IO;
with HRA.Canonical_Source; use HRA.Canonical_Source;
with HRA.Cycle_Observation;
with HRA.Dates;
with HRA.Envelope_Consumption;
with HRA.Household;
with HRA.Household_Envelope_Cycle_Comparison;
with HRA.Money;

procedure Test_Envelope_Cycle_Comparison is
   use type HRA.Dates.Date;
   use type HRA.Household_Envelope_Cycle_Comparison.Observe_Status;
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

   function W
     (First, Limit : String) return HRA.Cycle_Observation.Cycle_Window
   is
      Result : HRA.Dates.Half_Open_Period;
   begin
      if not HRA.Dates.Make_Half_Open_Period
        (D (First), D (Limit), Result)
      then
         raise Program_Error with "invalid test cycle: " & First & ".." & Limit;
      end if;
      return Result;
   end W;

   function JPY_Amount (Balance : HRA.Money.Balance) return HRA.Money.Quantity is
   begin
      return HRA.Money.Lookup_Balance
        (Balance, HRA.Money.Make_Commodity ("JPY"));
   end JPY_Amount;

   Observation : HRA.Canonical_Source.Source_Observation;
   State       : HRA.Household.Household_State;
   Err         : Unbounded_String;

   Current_Window  : constant HRA.Cycle_Observation.Cycle_Window :=
     W ("2026-08-01", "2026-09-01");
   Baseline_Window : constant HRA.Cycle_Observation.Cycle_Window :=
     W ("2026-07-01", "2026-08-01");

   Result : Comparison.Comparison_Observation;
   Diag   : Comparison.Observe_Diagnostic;

begin
   Put_Line ("--- Testing aligned Envelope cycle comparison ---");

   Observation.Root_Path := To_Unbounded_String ("/tmp/hra_cycle_comparison");
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
      "2026-07-05 July Coffee" & ASCII.LF &
      "    expenses:coffee          10 JPY" & ASCII.LF &
      "    assets:wallet           -10 JPY" & ASCII.LF & ASCII.LF &
      "2026-08-03 August Coffee" & ASCII.LF &
      "    expenses:coffee          40 JPY" & ASCII.LF &
      "    assets:wallet           -40 JPY" & ASCII.LF & ASCII.LF &
      "2026-08-04 August Refund" & ASCII.LF &
      "    expenses:coffee         -10 JPY" & ASCII.LF &
      "    assets:wallet            10 JPY" & ASCII.LF);

   Observation.Texts (Plan_Source) := Null_Unbounded_String;

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
      "note = ""aligned cycle comparison routing""" & ASCII.LF);

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
      "Setup: admit synthetic Household without historical cycle re-inference");

   declare
      Succeeded : constant Boolean := Comparison.Observe_Aligned
        (D ("2026-08-10"),
         Current_Window,
         Baseline_Window,
         State,
         Result,
         Diag);
   begin
      if not Succeeded then
         Put_Line
           ("[DIAG] " & Comparison.Observe_Status'Image (Diag.Status) &
            " " & To_String (Diag.Message));
      end if;
      Assert
        (Succeeded and then Diag.Status = Comparison.Success,
         "Compare two explicit cycles without weakening same-cycle Change");

      if Succeeded then
         Assert
           (Result.Current_Through = D ("2026-08-10")
              and then Result.Baseline_Through = D ("2026-07-10"),
            "Aligned comparison preserves equal elapsed cycle day");
         Assert
           (Natural (Result.Lines.Length) = 1,
            "Comparison follows current Envelope membership and order");

         if Natural (Result.Lines.Length) = 1 then
            declare
               Line : constant Comparison.Comparison_Line :=
                 Result.Lines.Element (1);
            begin
               Assert
                 (JPY_Amount (Line.Current_Consumption.Charges) = 40.0
                    and then JPY_Amount (Line.Current_Consumption.Refunds) = 10.0,
                  "Current cycle activity retains gross 40 charge / 10 refund");
               Assert
                 (JPY_Amount (Line.Baseline_Consumption.Charges) = 10.0
                    and then JPY_Amount (Line.Baseline_Consumption.Refunds) = 0.0,
                  "Baseline cycle activity is bounded to its own window");
               Assert
                 (JPY_Amount (Comparison.Consumption_Net_Difference (Line)) = 20.0,
                  "Aligned activity difference compares 30 current net with 10 baseline net");

               Assert
                 (JPY_Amount (Line.Current_Entitlement) = 150.0
                    and then JPY_Amount (Line.Baseline_Entitlement) = 50.0,
                  "Point-in-time Entitlement retains cumulative stock position");
               Assert
                 (JPY_Amount (Line.Current_Remaining) = 105.0
                    and then JPY_Amount (Line.Baseline_Remaining) = 35.0,
                  "Remaining keeps pre-cycle stock consumption while activity does not");
               Assert
                 (JPY_Amount (Comparison.Entitlement_Difference (Line)) = 100.0
                    and then JPY_Amount (Comparison.Remaining_Difference (Line)) = 70.0,
                  "Position differences remain derived from stored current/baseline values");
               Assert
                 (JPY_Amount (Line.Current_Headroom) = 105.0
                    and then JPY_Amount (Line.Baseline_Headroom) = 35.0
                    and then JPY_Amount (Comparison.Headroom_Difference (Line)) = 70.0,
                  "Zero commitment leaves aligned Headroom equal to Remaining");
               Assert
                 (JPY_Amount
                    (HRA.Envelope_Consumption.Net_Consumption
                       (Line.Current_Consumption)) = 30.0
                    and then JPY_Amount (Line.Current_Remaining) /= 120.0,
                  "Cycle activity is not reused as cumulative Remaining evidence");
            end;
         end if;
      end if;
   end;

   declare
      Short_Baseline : constant HRA.Cycle_Observation.Cycle_Window :=
        W ("2026-09-01", "2026-10-01");
      Long_Current : constant HRA.Cycle_Observation.Cycle_Window :=
        W ("2026-10-01", "2026-11-01");
      Succeeded : constant Boolean := Comparison.Observe_Aligned
        (D ("2026-10-31"),
         Long_Current,
         Short_Baseline,
         State,
         Result,
         Diag);
   begin
      Assert
        (not Succeeded
           and then Diag.Status = Comparison.Aligned_Baseline_Outside_Window,
         "Aligned day fails closed when baseline cycle is shorter");
   end;

   declare
      Succeeded : constant Boolean := Comparison.Observe_Aligned
        (D ("2026-08-10"),
         Current_Window,
         Current_Window,
         State,
         Result,
         Diag);
   begin
      Assert
        (not Succeeded and then Diag.Status = Comparison.Period_Order_Invalid,
         "Baseline cycle must start strictly before current cycle");
   end;

   declare
      Succeeded : constant Boolean := Comparison.Observe_Aligned
        (D ("2026-09-01"),
         Current_Window,
         Baseline_Window,
         State,
         Result,
         Diag);
   begin
      Assert
        (not Succeeded
           and then Diag.Status = Comparison.Current_Observation_Outside_Window,
         "Current comparison day must belong to explicit current cycle");
   end;

   Put_Line
     (Natural'Image (Passed_Count) & " passed, " &
      Natural'Image (Failed_Count) & " failed");

   if Failed_Count > 0 then
      raise Program_Error with "aligned Envelope cycle comparison tests failed";
   end if;
end Test_Envelope_Cycle_Comparison;
