with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO;           use Ada.Text_IO;
with HRA.Account;
with HRA.Dates;
with HRA.Household;
with HRA.Household_Check_Observation;
with HRA.Issues;
with HRA.Ledger;
with HRA.Money;

procedure Test_Household_Check_Observation is
   use type HRA.Money.Quantity;
   use type HRA.Issues.Issue_Status;

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

   function D (Text : String) return HRA.Dates.Date is
      Value  : HRA.Dates.Date;
      Status : HRA.Dates.Date_Status;
   begin
      if not HRA.Dates.Parse (Text, Value, Status) then
         raise Program_Error with "invalid synthetic date";
      end if;
      return Value;
   end D;

   procedure Register
     (Registry : in out HRA.Account.Account_Registry;
      Name     : String;
      Kind     : HRA.Account.Account_Type)
   is
      Status : HRA.Account.Registry_Status;
   begin
      if not HRA.Account.Register_Account
        (Registry,
         HRA.Account.Declare_Account
           (HRA.Account.Make_Account (Name), Kind),
         Status)
      then
         raise Program_Error with "synthetic Account registration failed";
      end if;
   end Register;

   function Make_Dummy_Tx
     (Date_Str : String;
      Payee    : String;
      Acc1     : String;
      Acc2     : String) return HRA.Ledger.Transaction
   is
      Postings : HRA.Ledger.Posting_Vectors.Vector;
      Tx       : HRA.Ledger.Transaction;
      Status   : HRA.Ledger.Transaction_Error;
      JPY      : constant HRA.Money.Commodity := HRA.Money.Make_Commodity ("JPY");
   begin
      Postings.Append
        (HRA.Ledger.Make_Posting
           (HRA.Account.Make_Account (Acc1),
            HRA.Money.Make_Amount (JPY, 100.0)));
      Postings.Append
        (HRA.Ledger.Make_Posting
           (HRA.Account.Make_Account (Acc2),
            HRA.Money.Make_Amount (JPY, -100.0)));
      if not HRA.Ledger.Create_Transaction
        (D (Date_Str), Payee, Postings, Tx, Status)
      then
         raise Program_Error with "failed to create dummy transaction";
      end if;
      return Tx;
   end Make_Dummy_Tx;

   procedure Add_Issue
     (Inv      : in out HRA.Issues.Issues_Inventory;
      Issue_ID : String;
      Status   : HRA.Issues.Issue_Status;
      Title    : String)
   is
      JPY : constant HRA.Money.Commodity := HRA.Money.Make_Commodity ("JPY");
   begin
      Inv.Items.Append
        (HRA.Issues.Household_Issue'
           (ID          => HRA.Issues.Make_Issue_Id (Issue_ID),
            Status      => Status,
            Recorded_On => D ("2026-08-01"),
            Due         => HRA.Issues.No_Due,
            Closed      =>
              (if Status = HRA.Issues.Open
               then HRA.Issues.Not_Closed
               else HRA.Issues.Make_Closed_On (D ("2026-08-01"))),
            Title       => To_Unbounded_String (Title),
            Amt         =>
              HRA.Issues.Make_Optional_Amount (HRA.Money.Make_Amount (JPY, 0.0)),
            Category    => To_Unbounded_String ("test"),
            Details     => To_Unbounded_String ("details")));
   end Add_Issue;

   Empty_State : constant HRA.Household.Household_State :=
     HRA.Household.Empty_Household_State;
   Empty_Obs   : constant HRA.Household_Check_Observation.Observation :=
     HRA.Household_Check_Observation.Observe (Empty_State);

   Populated_State : HRA.Household.Household_State :=
     HRA.Household.Empty_Household_State;
   Populated_Obs   : HRA.Household_Check_Observation.Observation;

   Resolved_Only_State : HRA.Household.Household_State :=
     HRA.Household.Empty_Household_State;
   Resolved_Only_Obs   : HRA.Household_Check_Observation.Observation;

begin
   Put_Line ("--- Testing focused Household check observation ---");

   --  1. Empty admitted-shaped State produces all zero counts
   Assert
     (Empty_Obs.Actual_Transactions = 0,
      "Empty state observes 0 Actual transactions");
   Assert
     (Empty_Obs.Plan_Transactions = 0,
      "Empty state observes 0 Plan transactions");
   Assert
     (Empty_Obs.Budget_Transactions = 0,
      "Empty state observes 0 Budget transactions");
   Assert
     (Empty_Obs.Registered_Accounts = 0,
      "Empty state observes 0 Registered accounts");
   Assert
     (Empty_Obs.Open_Issues = 0,
      "Empty state observes 0 Open issues");

   --  2. Setup populated state with synthetic facts
   Register (Populated_State.Registry, "assets:cash", HRA.Account.Asset);
   Register (Populated_State.Registry, "expenses:food", HRA.Account.Expense);
   Register (Populated_State.Registry, "income:salary", HRA.Account.Income);
   Register (Populated_State.Registry, "budget:food", HRA.Account.Budget);

   Populated_State.Actual_Ledger.Transactions.Append
     (Make_Dummy_Tx ("2026-08-01", "Actual Tx 1", "assets:cash", "expenses:food"));
   Populated_State.Actual_Ledger.Transactions.Append
     (Make_Dummy_Tx ("2026-08-02", "Actual Tx 2", "assets:cash", "expenses:food"));

   Populated_State.Plan_Ledger.Transactions.Append
     (Make_Dummy_Tx ("2026-08-10", "Plan Tx 1", "assets:cash", "expenses:food"));
   Populated_State.Plan_Ledger.Transactions.Append
     (Make_Dummy_Tx ("2026-08-11", "Plan Tx 2", "assets:cash", "expenses:food"));
   Populated_State.Plan_Ledger.Transactions.Append
     (Make_Dummy_Tx ("2026-08-12", "Plan Tx 3", "assets:cash", "expenses:food"));

   Populated_State.Budget_Ledger.Transactions.Append
     (Make_Dummy_Tx ("2026-08-01", "Budget Tx 1", "budget:food", "budget:food"));

   Add_Issue (Populated_State.Issues, "ISSUE-1", HRA.Issues.Open, "First open issue");
   Add_Issue (Populated_State.Issues, "ISSUE-2", HRA.Issues.Resolved, "Resolved issue");
   Add_Issue (Populated_State.Issues, "ISSUE-3", HRA.Issues.Open, "Second open issue");
   Add_Issue (Populated_State.Issues, "ISSUE-4", HRA.Issues.Resolved, "Another resolved issue");

   Populated_Obs := HRA.Household_Check_Observation.Observe (Populated_State);

   --  3. Verify transaction and account counts
   Assert
     (Populated_Obs.Actual_Transactions = 2,
      "Projects exact Actual transaction count");
   Assert
     (Populated_Obs.Plan_Transactions = 3,
      "Projects exact Plan transaction count");
   Assert
     (Populated_Obs.Budget_Transactions = 1,
      "Projects exact Budget transaction count");
   Assert
     (Populated_Obs.Registered_Accounts = 4,
      "Projects exact Registered accounts count");

   --  4. Verify open vs resolved issues
   Assert
     (Populated_Obs.Open_Issues = 2,
      "Projects only open issues count, excluding resolved issues");

   Add_Issue (Resolved_Only_State.Issues, "ISSUE-R1", HRA.Issues.Resolved, "Resolved 1");
   Add_Issue (Resolved_Only_State.Issues, "ISSUE-R2", HRA.Issues.Resolved, "Resolved 2");
   Resolved_Only_Obs :=
     HRA.Household_Check_Observation.Observe (Resolved_Only_State);
   Assert
     (Resolved_Only_Obs.Open_Issues = 0,
      "State with only resolved issues projects 0 open issues");

   Put_Line
     (Natural'Image (Passed_Count) & " passed, " &
      Natural'Image (Failed_Count) & " failed");

   if Failed_Count > 0 then
      raise Program_Error with "Household check observation tests failed";
   end if;
end Test_Household_Check_Observation;
