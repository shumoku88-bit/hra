with Ada.Strings.Fixed;     use Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO;           use Ada.Text_IO;
with HRA.Account;
with HRA.Actual_Admission;
with HRA.Backing_Policy;
with HRA.Cycle_Accounts_Observation;
with HRA.Cycle_Observation;
with HRA.Envelope_Config;
with HRA.Config_Support;
with HRA.Dates;
with HRA.Entitlement_Journal;
with HRA.Envelope;
with HRA.Envelope_Report_Render;
with HRA.Household;
with HRA.Household_Config;
with HRA.Household_Report_Observation;
with HRA.Issues;
with HRA.Journal;
with HRA.Journal_Evidence;
with HRA.Ledger;
with HRA.Money;
with HRA.Plan_Admission;
with HRA.Plan_Completion;
with HRA.Planned_Payments;
with HRA.Planned_Payments_Render;
with HRA.Report_Config;
with HRA.Report_Cycle_Accounts;

procedure Test_Household_Report_Observation is
   use type HRA.Dates.Date;
   use type HRA.Backing_Policy.Backing_Condition;
   use type HRA.Household_Report_Observation.Current_Report_Section_Order;
   use type HRA.Household_Report_Observation.Planned_Payments_Availability;
   use type HRA.Planned_Payments.Projection_Status;
   use type HRA.Report_Cycle_Accounts.Comparison_Availability;
   use type HRA.Money.Quantity;

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

   Envelope_TOML : constant String :=
     "[[backing-pools]]" & ASCII.LF &
     "id = ""liquid""" & ASCII.LF &
     "asset-accounts = [""assets:cash""]" & ASCII.LF &
     "[[envelopes]]" & ASCII.LF &
     "id = ""food""" & ASCII.LF &
     "label = ""Food""" & ASCII.LF &
     "pacing = ""daily""" & ASCII.LF &
     "backing-pool = ""liquid""" & ASCII.LF;

   Household_TOML : constant String :=
     "[cycle]" & ASCII.LF &
     "mode = ""income-anchor""" & ASCII.LF &
     "income-account = ""income:salary""" & ASCII.LF &
     "[money]" & ASCII.LF &
     "primary-commodity = ""JPY""" & ASCII.LF &
     "[envelope-history]" & ASCII.LF &
     "identities = [""food""]" & ASCII.LF &
     "expense-routing = []" & ASCII.LF &
     "fulfillment-routing = []" & ASCII.LF;

   Report_TOML : constant String :=
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
     "count = 2" & ASCII.LF;

   Actual_Text : constant String :=
     "2026-07-01 Previous salary" & ASCII.LF &
     "    assets:cash             1000 JPY" & ASCII.LF &
     "    income:salary          -1000 JPY" & ASCII.LF & ASCII.LF &
     "2026-08-01 Current salary" & ASCII.LF &
     "    assets:cash             1000 JPY" & ASCII.LF &
     "    income:salary          -1000 JPY" & ASCII.LF;

   Plan_Text : constant String :=
     "2026-08-15 Planned food" & ASCII.LF &
     "    ; plan-id: plan-food" & ASCII.LF &
     "    assets:cash              -25 JPY" & ASCII.LF &
     "    expenses:food             25 JPY" & ASCII.LF & ASCII.LF &
     "2026-09-01 Next salary" & ASCII.LF &
     "    ; plan-id: plan-next-salary" & ASCII.LF &
     "    assets:cash             1000 JPY" & ASCII.LF &
     "    income:salary          -1000 JPY" & ASCII.LF;

   Multi_Post_Plan_Text : constant String :=
     "2026-08-15 Split planned food" & ASCII.LF &
     "    ; plan-id: plan-food" & ASCII.LF &
     "    assets:cash              -25 JPY" & ASCII.LF &
     "    expenses:food             15 JPY" & ASCII.LF &
     "    expenses:food             10 JPY" & ASCII.LF & ASCII.LF &
     "2026-09-01 Next salary" & ASCII.LF &
     "    ; plan-id: plan-next-salary" & ASCII.LF &
     "    assets:cash             1000 JPY" & ASCII.LF &
     "    income:salary          -1000 JPY" & ASCII.LF;

   Entitlement_Text : constant String :=
     "2026-08-01 origin JPY" & ASCII.LF &
     "2026-08-01 transfer unallocated -> food 100 JPY" & ASCII.LF &
     "2026-08-02 origin USD" & ASCII.LF &
     "2026-08-02 transfer unallocated -> food 10 USD" & ASCII.LF;

   State        : HRA.Household.Household_State :=
     HRA.Household.Empty_Household_State;
   Empty_State  : HRA.Household.Household_State;
   Failed_State : HRA.Household.Household_State;
   Observation  : HRA.Household_Report_Observation.Report_Observation;
   Empty_Book   : HRA.Household_Report_Observation.Report_Observation;
   Failed_Book  : HRA.Household_Report_Observation.Report_Observation;
   Error_Msg    : Unbounded_String;
   Config_Diag  : HRA.Config_Support.Config_Diagnostic;
   Policy_State : HRA.Backing_Policy.Policy_Status;
   Journal_Diag : HRA.Journal.Parse_Diagnostic;
   Evidence_Diag : HRA.Journal_Evidence.Evidence_Diagnostic;
   Entitlement_Diag : HRA.Entitlement_Journal.Admission_Diagnostic;
   Actual_Diag  : HRA.Actual_Admission.Admission_Diagnostic;
   Plan_Diag    : HRA.Plan_Admission.Admission_Diagnostic;
   Completion_Diag : HRA.Plan_Completion.Admission_Diagnostic;
   Plan_Ledger  : HRA.Ledger.Ledger;
   Plan_Evidence : HRA.Journal_Evidence.Journal_Evidence;
   Ids          : HRA.Config_Support.String_Vectors.Vector;
   JPY          : constant HRA.Money.Commodity := HRA.Money.Make_Commodity ("JPY");
   USD          : constant HRA.Money.Commodity := HRA.Money.Make_Commodity ("USD");

begin
   Put_Line ("--- Testing complete Household report observation ---");

   Register (State.Registry, "assets:cash", HRA.Account.Asset);
   Register (State.Registry, "income:salary", HRA.Account.Income);
   Register (State.Registry, "expenses:food", HRA.Account.Expense);

   Assert
     (HRA.Envelope_Config.Parse_Envelope_Policy
        (Envelope_TOML, State.Envelope_Policy, Config_Diag),
      "setup admits current Envelope policy");
   Ids.Append ("food");
   Assert
     (HRA.Envelope.Admit_Registry
        (Ids, State.Envelope_Registry, Config_Diag),
      "setup admits stable Envelope identity");
   Assert
     (HRA.Household_Config.Parse_Household_Configuration
        (Household_TOML,
         State.Household_Policy,
         Config_Diag),
      "setup admits Household policy without Budget coordinates");
   Assert
     (HRA.Report_Config.Parse_Report_Configuration
        (Report_TOML, State.Report_Policy, Config_Diag),
      "setup admits Report policy");
   Assert
     (HRA.Backing_Policy.Admit_Backing_Policy
        (State.Envelope_Policy,
         State.Envelope_Registry,
         State.Backing_Policy_Spec,
         Policy_State),
      "setup admits Backing policy");

   Assert
     (HRA.Journal.Parse_Journal_Text
        (Actual_Text, "actual.journal", State.Actual_Ledger, Journal_Diag),
      "setup parses Actual");
   Assert
     (HRA.Journal_Evidence.Extract
        (Actual_Text,
         State.Actual_Ledger,
         State.Actual_Evidence,
         Evidence_Diag),
      "setup retains Actual evidence");
   State.Actual_Ledger.Registry := State.Registry;
   Assert
     (HRA.Actual_Admission.Admit
        (State.Actual_Ledger,
         State.Actual_Evidence,
         State.Actual_Identity,
         Actual_Diag),
      "setup admits Actual authority");

   Assert
     (HRA.Journal.Parse_Journal_Text
        (Plan_Text, "plan.journal", Plan_Ledger, Journal_Diag),
      "setup parses Plan");
   Assert
     (HRA.Journal_Evidence.Extract
        (Plan_Text,
         Plan_Ledger,
         Plan_Evidence,
         Evidence_Diag),
      "setup retains Plan evidence locally for admission");
   Plan_Ledger.Registry := State.Registry;
   Assert
     (HRA.Plan_Admission.Admit
        (Plan_Ledger,
         Plan_Evidence,
         State.Plan_Journal,
         Plan_Diag),
      "setup admits Plan Journal authority");
   Assert
     (HRA.Plan_Completion.Admit
        (State.Plan_Journal,
         State.Actual_Identity,
         State.Plan_Completions,
         Completion_Diag),
      "setup admits typed Plan completion relations");

   Assert
     (HRA.Entitlement_Journal.Admit
        (Entitlement_Text,
         State.Envelope_Registry,
         State.Entitlement_History,
         Entitlement_Diag),
      "setup admits multi-Commodity native Entitlement history");

   HRA.Issues.Append
     (State.Issues,
      HRA.Issues.Household_Issue'
        (ID          => HRA.Issues.Make_Issue_Id ("issue-open"),
         Status      => HRA.Issues.Open,
         Recorded_On => D ("2026-08-02"),
         Due         => HRA.Issues.No_Due,
         Closed      => HRA.Issues.Not_Closed,
         Title       => To_Unbounded_String ("Synthetic open issue"),
         Amt         =>
           HRA.Issues.Make_Optional_Amount (HRA.Money.Make_Amount (USD, 3.0)),
         Category    => To_Unbounded_String ("test"),
         Details     => To_Unbounded_String ("typed observation only")));
   HRA.Issues.Append
     (State.Issues,
      HRA.Issues.Household_Issue'
        (ID          => HRA.Issues.Make_Issue_Id ("issue-resolved"),
         Status      => HRA.Issues.Resolved,
         Recorded_On => D ("2026-08-01"),
         Due         => HRA.Issues.No_Due,
         Closed      => HRA.Issues.Make_Closed_On (D ("2026-08-05")),
         Title       => To_Unbounded_String ("Synthetic resolved issue"),
         Amt         =>
           HRA.Issues.Make_Optional_Amount (HRA.Money.Make_Amount (JPY, 0.0)),
         Category    => To_Unbounded_String ("test"),
         Details     => To_Unbounded_String ("not displayed")));

   Assert
     (HRA.Household_Report_Observation.Observe
        (D ("2026-08-10"), State, Observation, Error_Msg),
      "explicit day produces one complete report book");
   Assert
     (Observation.Observed_Through = D ("2026-08-10")
      and then Observation.Query_Plan.Trial_Balance_As_Of = D ("2026-08-10")
      and then Observation.Query_Plan.Balance_Sheet_As_Of = D ("2026-08-10")
      and then Observation.Account_Balances.As_Of =
        Observation.Query_Plan.Trial_Balance_As_Of
      and then Observation.Balance_Sheet.As_Of =
        Observation.Query_Plan.Balance_Sheet_As_Of
      and then HRA.Dates.Last (Observation.Query_Plan.Profit_And_Loss) =
        D ("2026-08-10")
      and then HRA.Dates.Last (Observation.Profit_And_Loss.Period) =
        D ("2026-08-10")
      and then HRA.Dates.Last (Observation.Query_Plan.Daily_Flow) =
        D ("2026-08-10")
      and then HRA.Dates.Last (Observation.Daily_Flow.Period) =
        D ("2026-08-10")
      and then HRA.Dates.Last (Observation.Query_Plan.Monthly_Accounts) =
        D ("2026-08-10")
      and then HRA.Dates.Last (Observation.Monthly_Accounts.Period) =
        D ("2026-08-10")
      and then Observation.Recent_Journal.Through_Date = D ("2026-08-10"),
      "TB, BS, P&L, Daily, Monthly, and Recent retain exact resolved coordinates");
   Assert
     (Observation.Cycle_Accounts.Current.Observed_Through = D ("2026-08-10")
      and then HRA.Cycle_Observation.Start_Date
        (Observation.Cycle_Accounts.Current.Window) = D ("2026-08-01")
      and then HRA.Cycle_Observation.End_Exclusive
        (Observation.Cycle_Accounts.Current.Window) = D ("2026-09-01")
      and then Natural (Observation.Cycle_Accounts.Current.Rows.Length) = 3
      and then HRA.Cycle_Accounts_Observation.Is_Balanced
        (Observation.Cycle_Accounts.Current),
      "Cycle Accounts retains the report book's typed Household cycle coordinate");
   Assert
     (Observation.Cycle_Accounts.Comparison.Status =
        HRA.Report_Cycle_Accounts.Comparison_Available
      and then Observation.Cycle_Accounts.Comparison.Value.Baseline.Observed_Through =
        D ("2026-07-10")
      and then HRA.Report_Cycle_Accounts.Is_Balanced
        (Observation.Cycle_Accounts.Comparison.Value),
      "Cycle comparison aligns the previous cycle at equal elapsed day");
   Assert
     (Natural (Observation.Daily_Flow.Lines.Length) = 2
      and then Natural (Observation.Monthly_Accounts.Months.Length) = 2,
      "flow sections expose admitted Actual through the resolved report periods");
   Assert
     (Observation.Planned_Payments.Status =
        HRA.Household_Report_Observation.Available
      and then Natural (Observation.Planned_Payments.Value.Payments.Length) = 1,
      "Planned Payments belongs to the same observation when projection is available");
   Assert
     (HRA.Issues.Count (Observation.Open_Issues.Open_Items) = 1
      and then Observation.Open_Issues.Resolved_Count = 1,
      "open Issues selection belongs to the same observation");
   Assert
     (Observation.Section_Order =
        HRA.Household_Report_Observation.Current_Report_Section_Order'
          [HRA.Household_Report_Observation.Envelope_And_Backing_Section,
           HRA.Household_Report_Observation.Cycle_Accounts_Section,
           HRA.Household_Report_Observation.Account_Balances_Section,
           HRA.Household_Report_Observation.Balance_Sheet_Section,
           HRA.Household_Report_Observation.Profit_And_Loss_Section,
           HRA.Household_Report_Observation.Daily_Flow_Section,
           HRA.Household_Report_Observation.Monthly_Accounts_Section,
           HRA.Household_Report_Observation.Recent_Journal_Section,
           HRA.Household_Report_Observation.Planned_Payments_Section,
           HRA.Household_Report_Observation.Open_Issues_Section],
      "current semantic section order is stable");
   Assert
     (Natural (Observation.Envelope_Report.Lines.Length) = 1
      and then HRA.Envelope.Image
        (Observation.Envelope_Report.Lines.Element (1).Env_Id) = "food",
      "Envelope identity and admitted order are retained");
   Assert
     (HRA.Money.Lookup_Balance
        (Observation.Envelope_Report.Lines.Element (1).Entitlement, JPY) = 100.0
      and then HRA.Money.Lookup_Balance
        (Observation.Envelope_Report.Lines.Element (1).Entitlement, USD) = 10.0
      and then Observation.Envelope_Report.Backing_Status =
        HRA.Backing_Policy.Under_Backed,
      "Envelope result and Backing condition retain every Commodity");

   declare
      First_Render : constant String :=
        HRA.Envelope_Report_Render.Render (Observation.Envelope_Report);
      Again_Render : constant String :=
        HRA.Envelope_Report_Render.Render (Observation.Envelope_Report);
   begin
      Assert
        (First_Render = Again_Render
         and then Index (First_Render, "100 JPY") > 0
         and then Index (First_Render, "10 USD") > 0,
         "renderer is deterministic and needs no Household_State");
   end;

   Empty_State := State;
   HRA.Issues.Clear (Empty_State.Issues);
   Assert
     (HRA.Household_Report_Observation.Observe
        (D ("2026-08-10"), Empty_State, Empty_Book, Error_Msg)
      and then HRA.Issues.Is_Empty (Empty_Book.Open_Issues.Open_Items)
      and then Empty_Book.Open_Issues.Total_Count = 0,
      "successful empty section is distinct from unavailable");

   Failed_State := State;
   declare
      Bad_Ledger   : HRA.Ledger.Ledger;
      Bad_Evidence : HRA.Journal_Evidence.Journal_Evidence;
   begin
      Assert
        (HRA.Journal.Parse_Journal_Text
           (Multi_Post_Plan_Text,
            "plan.journal",
            Bad_Ledger,
            Journal_Diag),
         "setup parses valid multi-post Plan");
      Assert
        (HRA.Journal_Evidence.Extract
           (Multi_Post_Plan_Text,
            Bad_Ledger,
            Bad_Evidence,
            Evidence_Diag),
         "setup retains multi-post Plan evidence");
      Bad_Ledger.Registry := State.Registry;
      Assert
        (HRA.Plan_Admission.Admit
           (Bad_Ledger,
            Bad_Evidence,
            Failed_State.Plan_Journal,
            Plan_Diag),
         "setup admits multi-post Plan authority");
      Assert
        (HRA.Plan_Completion.Admit
           (Failed_State.Plan_Journal,
            Failed_State.Actual_Identity,
            Failed_State.Plan_Completions,
            Completion_Diag),
         "setup admits multi-post completion relations");
   end;
   Assert
     (HRA.Household_Report_Observation.Observe
        (D ("2026-08-10"), Failed_State, Failed_Book, Error_Msg)
      and then Length (Error_Msg) = 0
      and then Failed_Book.Planned_Payments.Status =
        HRA.Household_Report_Observation.Unavailable
      and then Failed_Book.Planned_Payments.Diagnostic.Status =
        HRA.Planned_Payments.Plan_Report_Requires_Binary_Outgoing,
      "valid multi-post Plan keeps report book successful and only Planned Payments unavailable");
   Assert
     (Failed_Book.Account_Balances.As_Of = Observation.Account_Balances.As_Of
      and then Failed_Book.Cycle_Accounts.Current.Observed_Through =
        Observation.Cycle_Accounts.Current.Observed_Through
      and then HRA.Dates.Last (Failed_Book.Daily_Flow.Period) =
        HRA.Dates.Last (Observation.Daily_Flow.Period)
      and then HRA.Dates.Last (Failed_Book.Monthly_Accounts.Period) =
        HRA.Dates.Last (Observation.Monthly_Accounts.Period)
      and then HRA.Issues.Count (Failed_Book.Open_Issues.Open_Items) = 1,
      "Planned Payments projection limit does not erase independent report sections");

   Assert
     (HRA.Planned_Payments_Render.Render
        (Observation.Planned_Payments.Value)'Length > 0,
      "section renderer consumes only its available semantic observation");

   Put_Line
     (Natural'Image (Passed_Count) & " passed, " &
      Natural'Image (Failed_Count) & " failed");
   if Failed_Count > 0 then
      raise Program_Error with "Household report observation tests failed";
   end if;
end Test_Household_Report_Observation;
