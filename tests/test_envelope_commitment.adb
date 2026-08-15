with Ada.Text_IO; use Ada.Text_IO;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with ALedger.Account;
with ALedger.Config_Support;
with ALedger.Cycle_Observation;
with ALedger.Envelope;
with ALedger.Envelope_Commitment;
with ALedger.Envelope_Routing;
with ALedger.Journal;
with ALedger.Ledger;
with ALedger.Money;
with ALedger.Plan_Observation;

procedure Test_Envelope_Commitment is
   use type ALedger.Cycle_Observation.Resolve_Status;
   use type ALedger.Envelope_Routing.History_Status;

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

   procedure Register
     (Registry : in out ALedger.Account.Account_Registry;
      Name     : String;
      Kind     : ALedger.Account.Account_Type)
   is
      Status : ALedger.Account.Registry_Status;
   begin
      if not ALedger.Account.Register_Account
        (Registry,
         ALedger.Account.Declare_Account
           (ALedger.Account.Make_Account (Name), Kind),
         Status)
      then
         raise Program_Error with "test registry admission failed: " & Name;
      end if;
   end Register;

   Actual_Source : constant String :=
     "2026-06-15 Pension" & ASCII.LF &
     "    assets:cash        1000 JPY" & ASCII.LF &
     "    income:pension    -1000 JPY" & ASCII.LF & ASCII.LF &
     "2026-08-14 Pension" & ASCII.LF &
     "    assets:cash        1000 JPY" & ASCII.LF &
     "    income:pension    -1000 JPY" & ASCII.LF & ASCII.LF &
     "2026-08-14 Completed purchase" & ASCII.LF &
     "    ; plan-id: plan-completed" & ASCII.LF &
     "    expenses:food         50 JPY" & ASCII.LF &
     "    assets:cash          -50 JPY" & ASCII.LF;

   Plan_Source : constant String :=
     "2026-08-10 Overdue food" & ASCII.LF &
     "    ; plan-id: plan-overdue" & ASCII.LF &
     "    expenses:food        100 JPY" & ASCII.LF &
     "    assets:cash         -100 JPY" & ASCII.LF & ASCII.LF &
     "2026-08-20 Food" & ASCII.LF &
     "    ; plan-id: plan-food" & ASCII.LF &
     "    expenses:food        200 JPY" & ASCII.LF &
     "    assets:cash         -200 JPY" & ASCII.LF & ASCII.LF &
     "2026-08-25 Rent" & ASCII.LF &
     "    ; plan-id: plan-rent" & ASCII.LF &
     "    expenses:rent        300 JPY" & ASCII.LF &
     "    assets:cash         -300 JPY" & ASCII.LF & ASCII.LF &
     "2026-08-21 Completed purchase" & ASCII.LF &
     "    ; plan-id: plan-completed" & ASCII.LF &
     "    expenses:food         50 JPY" & ASCII.LF &
     "    assets:cash          -50 JPY" & ASCII.LF & ASCII.LF &
     "2026-10-15 Next pension" & ASCII.LF &
     "    ; plan-id: plan-next-pension" & ASCII.LF &
     "    assets:cash        1000 JPY" & ASCII.LF &
     "    income:pension    -1000 JPY" & ASCII.LF & ASCII.LF &
     "2026-10-15 Next-cycle food" & ASCII.LF &
     "    ; plan-id: plan-next-food" & ASCII.LF &
     "    expenses:food        999 JPY" & ASCII.LF &
     "    assets:cash         -999 JPY" & ASCII.LF;

   Registry      : ALedger.Account.Account_Registry := ALedger.Account.Empty_Registry;
   Actual        : ALedger.Ledger.Ledger;
   Plans         : ALedger.Ledger.Ledger;
   Parse_Error   : Unbounded_String;
   Open_Plans    : ALedger.Plan_Observation.Open_Plan_Vectors.Vector;
   Plan_Diag     : ALedger.Plan_Observation.Admission_Diagnostic;
   Window        : ALedger.Cycle_Observation.Cycle_Window;
   Cycle_Status  : ALedger.Cycle_Observation.Resolve_Status;
   Income_Acc    : ALedger.Account.Account := ALedger.Account.Make_Account ("income:pension");
   Env_Registry  : ALedger.Envelope.Envelope_Registry;
   Env_Diag      : ALedger.Config_Support.Config_Diagnostic;
   Env_Names     : ALedger.Config_Support.String_Vectors.Vector;
   Food_Env      : ALedger.Envelope.Envelope_Id;
   Route_Entries : ALedger.Envelope_Routing.Routing_Entry_Vectors.Vector;
   Routing       : ALedger.Envelope_Routing.Routing_History;
   Route_Status  : ALedger.Envelope_Routing.History_Status;
   Commitment    : ALedger.Envelope_Commitment.Commitment_Observation;
   Commit_Diag   : ALedger.Envelope_Commitment.Observe_Diagnostic;
   JPY           : constant ALedger.Money.Commodity := ALedger.Money.Make_Commodity ("JPY");

begin
   Put_Line ("--- Testing ALedger.Envelope_Commitment ---");

   Register (Registry, "income:pension", ALedger.Account.Income);
   Register (Registry, "assets:cash", ALedger.Account.Asset);
   Register (Registry, "expenses:food", ALedger.Account.Expense);
   Register (Registry, "expenses:rent", ALedger.Account.Expense);

   Assert
     (ALedger.Journal.Parse_Journal_Text (Actual_Source, Actual, Parse_Error),
      "Setup: parse Actual anchors and completion evidence");
   Assert
     (ALedger.Journal.Parse_Journal_Text (Plan_Source, Plans, Parse_Error),
      "Setup: parse current and next-cycle Plans");

   Assert
     (ALedger.Plan_Observation.Observe_Open_Plans
        (Plans, Plan_Source, Actual, Actual_Source,
         "2026-08-15", Open_Plans, Plan_Diag),
      "Observe role-neutral open Plans once");
   Assert
     (Natural (Open_Plans.Length) = 5,
      "Explicit Actual completion removes one Plan without date matching");

   Assert
     (ALedger.Cycle_Observation.Resolve_Current
        ("2026-08-15", Actual, Open_Plans, Registry, Income_Acc,
         Window, Cycle_Status),
      "Resolve income-anchor current cycle");
   Assert
     (To_String (Window.Start_Date) = "2026-08-14"
        and then To_String (Window.End_Exclusive) = "2026-10-15",
      "Cycle uses latest Actual anchor and first future Plan anchor");

   Env_Names.Append ("food");
   Assert
     (ALedger.Envelope.Admit_Registry (Env_Names, Env_Registry, Env_Diag),
      "Admit Envelope registry");
   Assert
     (ALedger.Envelope.Lookup (Env_Registry, "food", Food_Env),
      "Lookup food Envelope");

   Route_Entries.Append
     (ALedger.Envelope_Routing.Routing_Entry'
        (Effective => ALedger.Envelope_Routing.Initial_Effective_Date,
         Expense   => ALedger.Account.Make_Account ("expenses:food"),
         Route     => ALedger.Envelope_Routing.Managed_Route (Food_Env),
         Note      => Null_Unbounded_String));
   Assert
     (ALedger.Envelope_Routing.Admit
        (Route_Entries, Env_Registry, Routing, Route_Status),
      "Admit historical Expense routing");

   Assert
     (ALedger.Envelope_Commitment.Observe
        (Open_Plans, Registry, Routing, Window, "2026-08-15",
         Commitment, Commit_Diag),
      "Observe current-cycle Envelope commitments");
   Assert
     (ALedger.Money.Lookup_Balance
        (ALedger.Envelope_Commitment.Commitment_For (Commitment, Food_Env), JPY)
        = 300.0,
      "Managed commitment includes overdue plus upcoming current-cycle Plans");
   Assert
     (Commitment.Unrouted.Contains ("expenses:rent")
        and then ALedger.Money.Lookup_Balance
          (Commitment.Unrouted.Element ("expenses:rent"), JPY) = 300.0,
      "Missing Expense routing remains unrouted attention evidence");
   Assert
     (not Commitment.Managed.Contains ("plan-next-food")
        and then ALedger.Money.Lookup_Balance
          (ALedger.Envelope_Commitment.Commitment_For (Commitment, Food_Env), JPY)
            = 300.0,
      "Next-cycle Plan is excluded at the end-exclusive boundary");

   Put_Line
     (Natural'Image (Passed_Count) & " passed, " &
      Natural'Image (Failed_Count) & " failed");

   if Failed_Count > 0 then
      raise Program_Error with "Envelope commitment tests failed";
   end if;
end Test_Envelope_Commitment;
