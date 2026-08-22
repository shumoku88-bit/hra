with Ada.Command_Line;
with Ada.Directories; use Ada.Directories;
with Ada.Streams; use Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO; use Ada.Text_IO;
with HRA.Account;
with HRA.Actual_Admission;
with HRA.Canonical_Source; use HRA.Canonical_Source;
with HRA.Dates;
with HRA.Household;
with HRA.Issue_Realization_Reconciliation;
with HRA.Issue_Relation;
with HRA.Issue_Relation.Sidecar;
with HRA.Issue_Relation.TSV;
with HRA.Issues;
with HRA.Ledger;
with HRA.Money;

procedure Test_Issue_Realization_Reconciliation is
   use type HRA.Issue_Realization_Reconciliation.Recognized_World;
   use type HRA.Issue_Realization_Reconciliation.Reconciliation_Status;
   use type HRA.Money.Quantity;

   Passed : Natural := 0;
   Failed : Natural := 0;

   procedure Assert (Condition : Boolean; Name : String) is
   begin
      if Condition then
         Put_Line ("[PASS] " & Name);
         Passed := Passed + 1;
      else
         Put_Line ("[FAIL] " & Name);
         Failed := Failed + 1;
      end if;
   end Assert;

   Root : constant String := ".hra-test-issue-realization-reconciliation";
   Sidecar_Path : constant String := Compose (Root, "issue-relations.tsv");

   procedure Write_Exact (Path : String; Text : String) is
      package SIO renames Ada.Streams.Stream_IO;
      File : SIO.File_Type;
   begin
      SIO.Create (File, SIO.Out_File, Path);
      if Text'Length > 0 then
         declare
            Bytes : Stream_Element_Array
              (1 .. Stream_Element_Offset (Text'Length));
         begin
            for I in Text'Range loop
               Bytes (Stream_Element_Offset (I - Text'First + 1)) :=
                 Stream_Element (Character'Pos (Text (I)));
            end loop;
            SIO.Write (File, Bytes);
         end;
      end if;
      SIO.Close (File);
   end Write_Exact;

   function D (Text : String) return HRA.Dates.Date is
      Value : HRA.Dates.Date;
      Status : HRA.Dates.Date_Status;
   begin
      if not HRA.Dates.Parse (Text, Value, Status) then
         raise Program_Error;
      end if;
      return Value;
   end D;

   function AID (Text : String) return HRA.Actual_Admission.Actual_Id is
      Value : HRA.Actual_Admission.Actual_Id;
      Status : HRA.Actual_Admission.Actual_Id_Status;
   begin
      if not HRA.Actual_Admission.Create_Actual_Id (Text, Value, Status) then
         raise Program_Error;
      end if;
      return Value;
   end AID;

   function RID (Text : String) return HRA.Issue_Relation.Relation_Event_Id is
      Value : HRA.Issue_Relation.Relation_Event_Id;
      Status : HRA.Issue_Relation.Relation_Event_Id_Status;
   begin
      if not HRA.Issue_Relation.Create_Relation_Event_Id (Text, Value, Status) then
         raise Program_Error;
      end if;
      return Value;
   end RID;

   function Requested_Tx return HRA.Ledger.Transaction is
      Posts : HRA.Ledger.Posting_Vectors.Vector;
      Value : HRA.Ledger.Transaction;
      Status : HRA.Ledger.Transaction_Error;
      JPY : constant HRA.Money.Commodity := HRA.Money.Make_Commodity ("JPY");
   begin
      Posts.Append
        (HRA.Ledger.Make_Posting
           (HRA.Account.Make_Account ("assets:wallet"),
            HRA.Money.Make_Amount (JPY, -700.0)));
      Posts.Append
        (HRA.Ledger.Make_Posting
           (HRA.Account.Make_Account ("expenses:chair"),
            HRA.Money.Make_Amount (JPY, 700.0)));
      if not HRA.Ledger.Create_Transaction
        (D ("2026-08-20"), "Realized purchase", Posts, Value, Status)
      then
         raise Program_Error;
      end if;
      return Value;
   end Requested_Tx;

   Issue_Header : constant String :=
     "issue_id" & ASCII.HT & "status" & ASCII.HT & "date" & ASCII.HT &
     "due" & ASCII.HT & "closed" & ASCII.HT & "category" & ASCII.HT &
     "title" & ASCII.HT & "amount" & ASCII.HT & "currency" & ASCII.HT &
     "details";

   Issues_Open : constant String := Issue_Header & ASCII.LF &
     "ISSUE-OPEN" & ASCII.HT & "open" & ASCII.HT & "2026-08-01" & ASCII.HT &
     "none" & ASCII.HT & "none" & ASCII.HT & "purchase" & ASCII.HT &
     "Chair" & ASCII.HT & "" & ASCII.HT & "" & ASCII.HT &
     "compare two models" & ASCII.LF;

   Issues_Resolved : constant String := Issue_Header & ASCII.LF &
     "ISSUE-OPEN" & ASCII.HT & "resolved" & ASCII.HT & "2026-08-01" & ASCII.HT &
     "none" & ASCII.HT & "2026-08-22" & ASCII.HT & "purchase" & ASCII.HT &
     "Chair" & ASCII.HT & "" & ASCII.HT & "" & ASCII.HT &
     "compare two models" & ASCII.LF;

   Issues_Resolved_Other_Date : constant String := Issue_Header & ASCII.LF &
     "ISSUE-OPEN" & ASCII.HT & "resolved" & ASCII.HT & "2026-08-01" & ASCII.HT &
     "none" & ASCII.HT & "2026-08-21" & ASCII.HT & "purchase" & ASCII.HT &
     "Chair" & ASCII.HT & "" & ASCII.HT & "" & ASCII.HT &
     "compare two models" & ASCII.LF;

   Existing_Actual : constant String :=
     "2026-08-13 Existing" & ASCII.LF &
     "    ; event-id: existing-actual" & ASCII.LF &
     "    expenses:chair" & ASCII.HT & "500 JPY" & ASCII.LF &
     "    assets:wallet" & ASCII.HT & "-500 JPY" & ASCII.LF;

   Requested_Actual : constant String := Existing_Actual &
     "2026-08-20 Realized purchase" & ASCII.LF &
     "    ; event-id: new-actual" & ASCII.LF &
     "    assets:wallet" & ASCII.HT & "-700 JPY" & ASCII.LF &
     "    expenses:chair" & ASCII.HT & "700 JPY" & ASCII.LF;

   Different_Actual : constant String := Existing_Actual &
     "2026-08-20 Realized purchase" & ASCII.LF &
     "    ; event-id: new-actual" & ASCII.LF &
     "    assets:wallet" & ASCII.HT & "-800 JPY" & ASCII.LF &
     "    expenses:chair" & ASCII.HT & "800 JPY" & ASCII.LF;

   function Relation_Text (Details : String) return String is
     (HRA.Issue_Relation.TSV.Canonical_Header_Text & ASCII.LF &
      "rel-new" & ASCII.HT & "2026-08-21" & ASCII.HT &
      "ISSUE-OPEN" & ASCII.HT & "realized-as" & ASCII.HT &
      "new-actual" & ASCII.HT & Details & ASCII.LF);

   function Fixture
     (Actual_Text : String;
      Issues_Text : String) return Source_Observation
   is
      Result : Source_Observation;
   begin
      Result.Root_Path := To_Unbounded_String (Root);
      Result.Paths := HRA.Household.Resolve_Source_Paths (Root);
      Result.Texts (Accounts_Source) := To_Unbounded_String
        ("account assets:wallet" & ASCII.LF & "  ; type: Asset" & ASCII.LF &
         "account expenses:chair" & ASCII.LF & "  ; type: Expense" & ASCII.LF &
         "account income:salary" & ASCII.LF & "  ; type: Income" & ASCII.LF);
      Result.Texts (Actual_Source) := To_Unbounded_String (Actual_Text);
      Result.Texts (Plan_Source) := Null_Unbounded_String;
      Result.Texts (Entitlement_Source) := To_Unbounded_String
        ("2026-08-01 origin JPY ; epoch" & ASCII.LF &
         "2026-08-01 transfer unallocated -> chair 1000 JPY" & ASCII.LF);
      Result.Texts (Envelope_Config_Source) := To_Unbounded_String
        ("[[backing-pools]]" & ASCII.LF &
         "id = ""liquid""" & ASCII.LF &
         "asset-accounts = [""assets:wallet""]" & ASCII.LF &
         "[[envelopes]]" & ASCII.LF &
         "id = ""chair""" & ASCII.LF &
         "label = ""Chair""" & ASCII.LF &
         "pacing = ""daily""" & ASCII.LF &
         "backing-pool = ""liquid""" & ASCII.LF);
      Result.Texts (Household_Config_Source) := To_Unbounded_String
        ("[cycle]" & ASCII.LF &
         "mode = ""income-anchor""" & ASCII.LF &
         "income-account = ""income:salary""" & ASCII.LF &
         "[money]" & ASCII.LF &
         "primary-commodity = ""JPY""" & ASCII.LF &
         "[envelope-history]" & ASCII.LF &
         "identities = [""chair""]" & ASCII.LF &
         "[[envelope-history.expense-routing]]" & ASCII.LF &
         "effective-from = ""initial""" & ASCII.LF &
         "expense-account = ""expenses:chair""" & ASCII.LF &
         "route = ""managed""" & ASCII.LF &
         "target = ""chair""" & ASCII.LF &
         "note = ""fixture""" & ASCII.LF);
      Result.Texts (Report_Config_Source) := To_Unbounded_String
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
      Result.Texts (Issues_Source) := To_Unbounded_String (Issues_Text);
      return Result;
   end Fixture;

   function State_For
     (Actual_Text : String;
      Issues_Text : String) return HRA.Household.Household_State
   is
      State : HRA.Household.Household_State;
      Error : Unbounded_String;
   begin
      if not HRA.Household.Admit_Canonical_Household
        (Fixture (Actual_Text, Issues_Text), State, Error)
      then
         raise Program_Error with To_String (Error);
      end if;
      return State;
   end State_For;

   function Observe_Relation
     (Present : Boolean;
      Text    : String := "") return HRA.Issue_Relation.Sidecar.Observation
   is
      Observation : HRA.Issue_Relation.Sidecar.Observation;
      Diag : HRA.Issue_Relation.Sidecar.Observation_Diagnostic;
   begin
      if Exists (Sidecar_Path) then
         Delete_File (Sidecar_Path);
      end if;
      if Present then
         Write_Exact (Sidecar_Path, Text);
      end if;
      if not HRA.Issue_Relation.Sidecar.Observe (Root, Observation, Diag) then
         raise Program_Error;
      end if;
      return Observation;
   end Observe_Relation;

   procedure Expect_World
     (Actual_Text : String;
      Issues_Text : String;
      Relation_Present : Boolean;
      Relation_Source : String;
      Expected : HRA.Issue_Realization_Reconciliation.Recognized_World;
      Name : String)
   is
      State : constant HRA.Household.Household_State :=
        State_For (Actual_Text, Issues_Text);
      Relation : constant HRA.Issue_Relation.Sidecar.Observation :=
        Observe_Relation (Relation_Present, Relation_Source);
      World : HRA.Issue_Realization_Reconciliation.Recognized_World;
      Diag : HRA.Issue_Realization_Reconciliation.Reconciliation_Diagnostic;
   begin
      Assert
        (HRA.Issue_Realization_Reconciliation.Reconcile
           (State, Requested_Tx, HRA.Issues.Make_Issue_Id ("ISSUE-OPEN"),
            AID ("new-actual"), RID ("rel-new"), D ("2026-08-21"),
            D ("2026-08-22"), "selected chair", Relation, World, Diag)
         and then Diag.Status = HRA.Issue_Realization_Reconciliation.Success
         and then World = Expected,
         Name);
   end Expect_World;

begin
   Put_Line ("--- Testing Issue realization prefix reconciliation ---");

   if Exists (Root) then
      Delete_Tree (Root);
   end if;
   Create_Directory (Root);

   Expect_World
     (Existing_Actual, Issues_Open, False, "",
      HRA.Issue_Realization_Reconciliation.W0,
      "W0 recognized from absent requested Actual and relation");

   Expect_World
     (Requested_Actual, Issues_Open, False, "",
      HRA.Issue_Realization_Reconciliation.W1,
      "W1 recognized from exact requested Actual only");

   Expect_World
     (Requested_Actual, Issues_Open, True, Relation_Text ("selected chair"),
      HRA.Issue_Realization_Reconciliation.W2,
      "W2 recognized from exact Actual and relation with Open Issue");

   Expect_World
     (Requested_Actual, Issues_Resolved, True, Relation_Text ("selected chair"),
      HRA.Issue_Realization_Reconciliation.W3,
      "W3 recognized from exact Actual relation and requested resolution");

   declare
      State : constant HRA.Household.Household_State :=
        State_For (Different_Actual, Issues_Open);
      Relation : constant HRA.Issue_Relation.Sidecar.Observation :=
        Observe_Relation (False);
      World : HRA.Issue_Realization_Reconciliation.Recognized_World;
      Diag : HRA.Issue_Realization_Reconciliation.Reconciliation_Diagnostic;
   begin
      Assert
        (not HRA.Issue_Realization_Reconciliation.Reconcile
           (State, Requested_Tx, HRA.Issues.Make_Issue_Id ("ISSUE-OPEN"),
            AID ("new-actual"), RID ("rel-new"), D ("2026-08-21"),
            D ("2026-08-22"), "selected chair", Relation, World, Diag)
         and then Diag.Status =
           HRA.Issue_Realization_Reconciliation.Actual_Meaning_Mismatch,
         "same Actual ID with different Transaction meaning is rejected");
   end;

   declare
      State : constant HRA.Household.Household_State :=
        State_For (Requested_Actual, Issues_Open);
      Relation : constant HRA.Issue_Relation.Sidecar.Observation :=
        Observe_Relation (True, Relation_Text ("different details"));
      World : HRA.Issue_Realization_Reconciliation.Recognized_World;
      Diag : HRA.Issue_Realization_Reconciliation.Reconciliation_Diagnostic;
   begin
      Assert
        (not HRA.Issue_Realization_Reconciliation.Reconcile
           (State, Requested_Tx, HRA.Issues.Make_Issue_Id ("ISSUE-OPEN"),
            AID ("new-actual"), RID ("rel-new"), D ("2026-08-21"),
            D ("2026-08-22"), "selected chair", Relation, World, Diag)
         and then Diag.Status =
           HRA.Issue_Realization_Reconciliation.Relation_Meaning_Mismatch,
         "same relation Event ID with different meaning is rejected");
   end;

   declare
      State : constant HRA.Household.Household_State :=
        State_For (Requested_Actual, Issues_Resolved_Other_Date);
      Relation : constant HRA.Issue_Relation.Sidecar.Observation :=
        Observe_Relation (True, Relation_Text ("selected chair"));
      World : HRA.Issue_Realization_Reconciliation.Recognized_World;
      Diag : HRA.Issue_Realization_Reconciliation.Reconciliation_Diagnostic;
   begin
      Assert
        (not HRA.Issue_Realization_Reconciliation.Reconcile
           (State, Requested_Tx, HRA.Issues.Make_Issue_Id ("ISSUE-OPEN"),
            AID ("new-actual"), RID ("rel-new"), D ("2026-08-21"),
            D ("2026-08-22"), "selected chair", Relation, World, Diag)
         and then Diag.Status =
           HRA.Issue_Realization_Reconciliation.Issue_Lifecycle_Mismatch,
         "resolved Issue with a different closure coordinate is rejected");
   end;

   if Exists (Root) then
      Delete_Tree (Root);
   end if;

   Put_Line
     ("Summary: Passed =" & Natural'Image (Passed) &
      ", Failed =" & Natural'Image (Failed));
   if Failed > 0 then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   else
      Put_Line ("RESULT: SUCCESS");
   end if;
exception
   when others =>
      if Exists (Root) then
         Delete_Tree (Root);
      end if;
      raise;
end Test_Issue_Realization_Reconciliation;
