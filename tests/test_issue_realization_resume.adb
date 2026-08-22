with Ada.Command_Line;
with Ada.Directories; use Ada.Directories;
with Ada.Streams; use Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO; use Ada.Text_IO;
with HRA.Account;
with HRA.Actual_Admission;
with HRA.Canonical_Source; use HRA.Canonical_Source;
with HRA.Dates;
with HRA.Household;
with HRA.Household_Check_Observation;
with HRA.Issue_Realization_Preparation.Publication;
with HRA.Issue_Realization_Reconciliation;
with HRA.Issue_Realization_Resume;
with HRA.Issue_Realization_Resume.Publication;
with HRA.Issue_Relation.Sidecar;
with HRA.Issue_Relation.TSV;
with HRA.Issues;
with HRA.Ledger;
with HRA.Money;
with HRA.Writer;
with HRA.Writer.Test_Hooks;

procedure Test_Issue_Realization_Resume is
   use type HRA.Issue_Realization_Preparation.Publication.Confirmed_World;
   use type HRA.Issue_Realization_Preparation.Publication.Publication_Step;
   use type HRA.Issue_Realization_Preparation.Publication.Result_Kind;
   use type HRA.Issue_Realization_Reconciliation.Recognized_World;
   use type HRA.Issue_Realization_Reconciliation.Reconciliation_Status;
   use type HRA.Issue_Realization_Resume.Resume_Status;
   use type HRA.Issue_Relation.Sidecar.Presence;
   use type HRA.Issues.Issue_Status;
   use type HRA.Money.Quantity;
   use type HRA.Writer.Writer_Status;

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

   Root : constant String := ".hra-test-issue-realization-resume";
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

   function Read_Exact (Path : String) return String is
      package SIO renames Ada.Streams.Stream_IO;
      use type SIO.Count;
      File : SIO.File_Type;
   begin
      SIO.Open (File, SIO.In_File, Path);
      declare
         Size : constant SIO.Count := SIO.Size (File);
      begin
         if Size = 0 then
            SIO.Close (File);
            return "";
         end if;
         declare
            Bytes : Stream_Element_Array
              (1 .. Stream_Element_Offset (Size));
            Last : Stream_Element_Offset;
            Text : String (1 .. Natural (Size));
         begin
            SIO.Read (File, Bytes, Last);
            for I in Bytes'Range loop
               Text (Natural (I)) := Character'Val (Bytes (I));
            end loop;
            SIO.Close (File);
            return Text;
         end;
      end;
   end Read_Exact;

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

   function Tx return HRA.Ledger.Transaction is
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
   end Tx;

   Issue_Header : constant String :=
     "issue_id" & ASCII.HT & "status" & ASCII.HT & "date" & ASCII.HT &
     "due" & ASCII.HT & "closed" & ASCII.HT & "category" & ASCII.HT &
     "title" & ASCII.HT & "amount" & ASCII.HT & "currency" & ASCII.HT &
     "details";

   Issues_Open_Text : constant String := Issue_Header & ASCII.LF &
     "ISSUE-OPEN" & ASCII.HT & "open" & ASCII.HT & "2026-08-01" & ASCII.HT &
     "none" & ASCII.HT & "none" & ASCII.HT & "purchase" & ASCII.HT &
     "Chair" & ASCII.HT & "" & ASCII.HT & "" & ASCII.HT &
     "compare two models" & ASCII.LF;

   Issues_Resolved_Text : constant String := Issue_Header & ASCII.LF &
     "ISSUE-OPEN" & ASCII.HT & "resolved" & ASCII.HT & "2026-08-01" & ASCII.HT &
     "none" & ASCII.HT & "2026-08-22" & ASCII.HT & "purchase" & ASCII.HT &
     "Chair" & ASCII.HT & "" & ASCII.HT & "" & ASCII.HT &
     "compare two models" & ASCII.LF;

   Changed_Issues_Text : constant String := Issue_Header & ASCII.LF &
     "ISSUE-OPEN" & ASCII.HT & "open" & ASCII.HT & "2026-08-01" & ASCII.HT &
     "none" & ASCII.HT & "none" & ASCII.HT & "purchase" & ASCII.HT &
     "Chair" & ASCII.HT & "" & ASCII.HT & "" & ASCII.HT &
     "externally changed details" & ASCII.LF;

   Base_Actual_Text : constant String :=
     "2026-08-13 Existing" & ASCII.LF &
     "    ; event-id: existing-actual" & ASCII.LF &
     "    expenses:chair         500 JPY" & ASCII.LF &
     "    assets:wallet         -500 JPY" & ASCII.LF;

   Appended_Actual_Text : constant String := Base_Actual_Text & ASCII.LF &
     "2026-08-20 Realized purchase" & ASCII.LF &
     "    ; event-id: new-actual" & ASCII.LF &
     "    assets:wallet         -700 JPY" & ASCII.LF &
     "    expenses:chair         700 JPY" & ASCII.LF;

   Mismatch_Actual_Text : constant String := Base_Actual_Text & ASCII.LF &
     "2026-08-20 Realized purchase" & ASCII.LF &
     "    ; event-id: new-actual" & ASCII.LF &
     "    assets:wallet         -800 JPY" & ASCII.LF &
     "    expenses:chair         800 JPY" & ASCII.LF;

   Relation_Row_Text : constant String :=
     HRA.Issue_Relation.TSV.Canonical_Header_Text & ASCII.LF &
     "rel-new" & ASCII.HT & "2026-08-21" & ASCII.HT &
     "ISSUE-OPEN" & ASCII.HT & "realized-as" & ASCII.HT &
     "new-actual" & ASCII.HT & "selected chair" & ASCII.LF;

   function Fixture
     (Actual_Content : String;
      Issues_Content : String) return Source_Observation
   is
      Result : Source_Observation;
   begin
      Result.Root_Path := To_Unbounded_String (Full_Name (Root));
      Result.Paths := HRA.Household.Resolve_Source_Paths (Root);
      Result.Texts (Accounts_Source) := To_Unbounded_String
        ("account assets:wallet" & ASCII.LF & "  ; type: Asset" & ASCII.LF &
         "account expenses:chair" & ASCII.LF & "  ; type: Expense" & ASCII.LF &
         "account income:salary" & ASCII.LF & "  ; type: Income" & ASCII.LF);
      Result.Texts (Actual_Source) := To_Unbounded_String (Actual_Content);
      Result.Texts (Plan_Source) := Null_Unbounded_String;
      Result.Texts (Entitlement_Source) := To_Unbounded_String
        ("2026-08-01 origin JPY ; epoch" & ASCII.LF &
         "2026-08-01 transfer unallocated -> chair 1000 JPY" & ASCII.LF);
      Result.Texts (Envelope_Config_Source) := To_Unbounded_String
        ("[[backing-pools]]" & ASCII.LF & "id = ""liquid""" & ASCII.LF &
         "asset-accounts = [""assets:wallet""]" & ASCII.LF &
         "[[envelopes]]" & ASCII.LF & "id = ""chair""" & ASCII.LF &
         "label = ""Chair""" & ASCII.LF & "pacing = ""daily""" & ASCII.LF &
         "backing-pool = ""liquid""" & ASCII.LF);
      Result.Texts (Household_Config_Source) := To_Unbounded_String
        ("[cycle]" & ASCII.LF & "mode = ""income-anchor""" & ASCII.LF &
         "income-account = ""income:salary""" & ASCII.LF & "[money]" & ASCII.LF &
         "primary-commodity = ""JPY""" & ASCII.LF & "[envelope-history]" & ASCII.LF &
         "identities = [""chair""]" & ASCII.LF &
         "[[envelope-history.expense-routing]]" & ASCII.LF &
         "effective-from = ""initial""" & ASCII.LF &
         "expense-account = ""expenses:chair""" & ASCII.LF &
         "route = ""managed""" & ASCII.LF & "target = ""chair""" & ASCII.LF &
         "note = ""fixture""" & ASCII.LF);
      Result.Texts (Report_Config_Source) := To_Unbounded_String
        ("[presentation.amounts]" & ASCII.LF & "negative-style = ""parentheses""" & ASCII.LF &
         "[reports.trial-balance]" & ASCII.LF & "as-of = ""latest""" & ASCII.LF &
         "[reports.balance-sheet]" & ASCII.LF & "as-of = ""latest""" & ASCII.LF &
         "[reports.profit-and-loss]" & ASCII.LF & "from = ""beginning""" & ASCII.LF &
         "through = ""latest""" & ASCII.LF & "[reports.daily-flow]" & ASCII.LF &
         "from = ""beginning""" & ASCII.LF & "through = ""latest""" & ASCII.LF &
         "max-date-columns = 7" & ASCII.LF & "[reports.monthly-accounts]" & ASCII.LF &
         "from = ""beginning""" & ASCII.LF & "through = ""latest""" & ASCII.LF &
         "[reports.recent-transactions]" & ASCII.LF & "through = ""latest""" & ASCII.LF &
         "count = 10" & ASCII.LF);
      Result.Texts (Issues_Source) := To_Unbounded_String (Issues_Content);
      return Result;
   end Fixture;

   procedure Reset
     (Actual_Content : String;
      Issues_Content : String;
      Sidecar_Content : String := "")
   is
      Obs : constant Source_Observation :=
        Fixture (Actual_Content, Issues_Content);
   begin
      HRA.Writer.Test_Hooks.Clear_After_Stage_Hook;
      HRA.Writer.Test_Hooks.Clear_After_Publish_Hook;
      if Exists (Root) then
         Delete_Tree (Root);
      end if;
      Create_Directory (Root);
      for Source in Source_Name loop
         Write_Exact (Path_For (Obs.Paths, Source), Text_For (Obs, Source));
      end loop;
      if Sidecar_Content'Length > 0 then
         Write_Exact (Sidecar_Path, Sidecar_Content);
      end if;
   end Reset;

   function Load return HRA.Household.Household_State is
      State : HRA.Household.Household_State;
      Error : Unbounded_String;
   begin
      if not HRA.Household.Load_Canonical_Household (Root, State, Error) then
         raise Program_Error with To_String (Error);
      end if;
      return State;
   end Load;

   function Observe_Relation return HRA.Issue_Relation.Sidecar.Observation is
      Obs : HRA.Issue_Relation.Sidecar.Observation;
      Diag : HRA.Issue_Relation.Sidecar.Observation_Diagnostic;
   begin
      if not HRA.Issue_Relation.Sidecar.Observe (Root, Obs, Diag) then
         raise Program_Error;
      end if;
      return Obs;
   end Observe_Relation;

   function Prepare_Resume_Call
     (Prepared : out HRA.Issue_Realization_Resume.Prepared_Resume;
      Diag     : out HRA.Issue_Realization_Resume.Resume_Diagnostic) return Boolean
   is
      State : constant HRA.Household.Household_State := Load;
   begin
      return HRA.Issue_Realization_Resume.Prepare_Resume
        (State                => State,
         Tx                   => Tx,
         Issue_ID             => HRA.Issues.Make_Issue_Id ("ISSUE-OPEN"),
         Actual_ID            => AID ("new-actual"),
         Relation_Event_ID    => RID ("rel-new"),
         Relation_Recorded_On => D ("2026-08-21"),
         Closed_On            => D ("2026-08-22"),
         Relation_Details     => "selected chair",
         Relation_Observation => Observe_Relation,
         Prepared             => Prepared,
         Diag                 => Diag);
   end Prepare_Resume_Call;

begin
   Put_Line ("--- Testing Issue realization crash resume ---");

   --  Test 1: W0 Resume
   declare
      Prepared : HRA.Issue_Realization_Resume.Prepared_Resume;
      Diag     : HRA.Issue_Realization_Resume.Resume_Diagnostic;
      Pub_Res  : HRA.Issue_Realization_Resume.Publication.Publication_Result;
      State    : HRA.Household.Household_State;
      Error    : Unbounded_String;
   begin
      Reset (Base_Actual_Text, Issues_Open_Text);
      Assert
        (Prepare_Resume_Call (Prepared, Diag)
         and then Diag.Status = HRA.Issue_Realization_Resume.Success
         and then HRA.Issue_Realization_Resume.World_Of (Prepared) =
           HRA.Issue_Realization_Reconciliation.W0,
         "W0 resume witness prepared from unperformed realization");

      Assert
        (HRA.Issue_Realization_Resume.Publication.Publish (Prepared, Pub_Res)
         and then Pub_Res.Kind =
           HRA.Issue_Realization_Preparation.Publication.Completed
         and then Pub_Res.Last_Confirmed =
           HRA.Issue_Realization_Preparation.Publication.W3,
         "W0 resume publishes full sequence through W3");

      Assert
        (HRA.Household.Load_Canonical_Household (Root, State, Error),
         "W0-resumed Household re-admits after completion");

      Assert
        (HRA.Household_Check_Observation.Observe (State).Actual_Transactions = 2
         and then HRA.Household_Check_Observation.Observe (State).Open_Issues = 0,
         "W0-resumed Household passes canonical check");
   end;

   --  Test 2: W1 Resume
   declare
      Prepared : HRA.Issue_Realization_Resume.Prepared_Resume;
      Diag     : HRA.Issue_Realization_Resume.Resume_Diagnostic;
      Pub_Res  : HRA.Issue_Realization_Resume.Publication.Publication_Result;
      State    : HRA.Household.Household_State;
      Error    : Unbounded_String;
   begin
      Reset (Appended_Actual_Text, Issues_Open_Text);
      Assert
        (Prepare_Resume_Call (Prepared, Diag)
         and then Diag.Status = HRA.Issue_Realization_Resume.Success
         and then HRA.Issue_Realization_Resume.World_Of (Prepared) =
           HRA.Issue_Realization_Reconciliation.W1,
         "W1 resume witness prepared from existing Actual prefix");

      Assert
        (HRA.Issue_Realization_Resume.Publication.Publish (Prepared, Pub_Res)
         and then Pub_Res.Kind =
           HRA.Issue_Realization_Preparation.Publication.Completed
         and then Pub_Res.Last_Confirmed =
           HRA.Issue_Realization_Preparation.Publication.W3,
         "W1 resume publishes missing Relation and Issue through W3");

      Assert
        (HRA.Household.Load_Canonical_Household (Root, State, Error),
         "W1-resumed Household re-admits after completion");

      Assert
        (HRA.Household_Check_Observation.Observe (State).Actual_Transactions = 2
         and then HRA.Household_Check_Observation.Observe (State).Open_Issues = 0,
         "W1-resumed Household passes canonical check");
   end;

   --  Test 3: W2 Resume
   declare
      Prepared : HRA.Issue_Realization_Resume.Prepared_Resume;
      Diag     : HRA.Issue_Realization_Resume.Resume_Diagnostic;
      Pub_Res  : HRA.Issue_Realization_Resume.Publication.Publication_Result;
      State    : HRA.Household.Household_State;
      Error    : Unbounded_String;
   begin
      Reset (Appended_Actual_Text, Issues_Open_Text, Relation_Row_Text);
      Assert
        (Prepare_Resume_Call (Prepared, Diag)
         and then Diag.Status = HRA.Issue_Realization_Resume.Success
         and then HRA.Issue_Realization_Resume.World_Of (Prepared) =
           HRA.Issue_Realization_Reconciliation.W2,
         "W2 resume witness prepared from existing Actual and Relation");

      Assert
        (HRA.Issue_Realization_Resume.Publication.Publish (Prepared, Pub_Res)
         and then Pub_Res.Kind =
           HRA.Issue_Realization_Preparation.Publication.Completed
         and then Pub_Res.Last_Confirmed =
           HRA.Issue_Realization_Preparation.Publication.W3,
         "W2 resume publishes missing Issue through W3");

      Assert
        (HRA.Household.Load_Canonical_Household (Root, State, Error),
         "W2-resumed Household re-admits after completion");

      Assert
        (HRA.Household_Check_Observation.Observe (State).Actual_Transactions = 2
         and then HRA.Household_Check_Observation.Observe (State).Open_Issues = 0,
         "W2-resumed Household passes canonical check");
   end;

   --  Test 4: W3 Resume (already complete no-op)
   declare
      Prepared : HRA.Issue_Realization_Resume.Prepared_Resume;
      Diag     : HRA.Issue_Realization_Resume.Resume_Diagnostic;
      Pub_Res  : HRA.Issue_Realization_Resume.Publication.Publication_Result;
      Actual_Before : constant String := Appended_Actual_Text;
      Issues_Before : constant String := Issues_Resolved_Text;
      Rel_Before    : constant String := Relation_Row_Text;
   begin
      Reset (Appended_Actual_Text, Issues_Resolved_Text, Relation_Row_Text);
      Assert
        (Prepare_Resume_Call (Prepared, Diag)
         and then Diag.Status = HRA.Issue_Realization_Resume.Success
         and then HRA.Issue_Realization_Resume.World_Of (Prepared) =
           HRA.Issue_Realization_Reconciliation.W3,
         "W3 resume witness recognized as already complete");

      Assert
        (HRA.Issue_Realization_Resume.Publication.Publish (Prepared, Pub_Res)
         and then Pub_Res.Kind =
           HRA.Issue_Realization_Preparation.Publication.Completed
         and then Pub_Res.Last_Confirmed =
           HRA.Issue_Realization_Preparation.Publication.W3,
         "W3 resume succeeds as no-op");

      Assert
        (Read_Exact (Compose (Root, "actual.journal")) = Actual_Before
         and then Read_Exact (Compose (Root, "issues.tsv")) = Issues_Before
         and then Read_Exact (Sidecar_Path) = Rel_Before,
         "W3 resume leaves all sources byte-for-byte untouched");
   end;

   --  Test 5: W1 Stale Relation Target Race
   declare
      Prepared : HRA.Issue_Realization_Resume.Prepared_Resume;
      Diag     : HRA.Issue_Realization_Resume.Resume_Diagnostic;
      Pub_Res  : HRA.Issue_Realization_Resume.Publication.Publication_Result;
   begin
      Reset (Appended_Actual_Text, Issues_Open_Text);
      Assert
        (Prepare_Resume_Call (Prepared, Diag),
         "prepare W1 before relation drift");

      --  Mutate relation sidecar externally after preparation
      Write_Exact (Sidecar_Path, "# external sidecar race" & ASCII.LF);

      Assert
        (not HRA.Issue_Realization_Resume.Publication.Publish
           (Prepared, Pub_Res)
         and then Pub_Res.Kind =
           HRA.Issue_Realization_Preparation.Publication.Failed
         and then Pub_Res.Failed_Step =
           HRA.Issue_Realization_Preparation.Publication.Publishing_Relation
         and then Pub_Res.Last_Confirmed =
           HRA.Issue_Realization_Preparation.Publication.W1,
         "relation target drift rejects at W1 without rollback");

      Assert
        (Read_Exact (Compose (Root, "actual.journal")) = Appended_Actual_Text,
         "W1 Actual remains intact after relation target drift");
   end;

   --  Test 6: W1 Guard Drift (Issues changed before relation published)
   declare
      Prepared : HRA.Issue_Realization_Resume.Prepared_Resume;
      Diag     : HRA.Issue_Realization_Resume.Resume_Diagnostic;
      Pub_Res  : HRA.Issue_Realization_Resume.Publication.Publication_Result;
   begin
      Reset (Appended_Actual_Text, Issues_Open_Text);
      Assert
        (Prepare_Resume_Call (Prepared, Diag),
         "prepare W1 before issues guard drift");

      --  Mutate issues.tsv externally
      Write_Exact (Compose (Root, "issues.tsv"), Changed_Issues_Text);

      Assert
        (not HRA.Issue_Realization_Resume.Publication.Publish
           (Prepared, Pub_Res)
         and then Pub_Res.Kind =
           HRA.Issue_Realization_Preparation.Publication.Failed
         and then Pub_Res.Failed_Step =
           HRA.Issue_Realization_Preparation.Publication.Publishing_Relation
         and then Pub_Res.Last_Confirmed =
           HRA.Issue_Realization_Preparation.Publication.W1,
         "issues guard drift rejects relation at W1 without rollback");
   end;

   --  Test 7: W2 Stale Issue Target Race
   declare
      Prepared : HRA.Issue_Realization_Resume.Prepared_Resume;
      Diag     : HRA.Issue_Realization_Resume.Resume_Diagnostic;
      Pub_Res  : HRA.Issue_Realization_Resume.Publication.Publication_Result;
   begin
      Reset (Appended_Actual_Text, Issues_Open_Text, Relation_Row_Text);
      Assert
        (Prepare_Resume_Call (Prepared, Diag),
         "prepare W2 before issue target drift");

      --  Mutate issues.tsv externally
      Write_Exact (Compose (Root, "issues.tsv"), Changed_Issues_Text);

      Assert
        (not HRA.Issue_Realization_Resume.Publication.Publish
           (Prepared, Pub_Res)
         and then Pub_Res.Kind =
           HRA.Issue_Realization_Preparation.Publication.Failed
         and then Pub_Res.Failed_Step =
           HRA.Issue_Realization_Preparation.Publication.Publishing_Issue
         and then Pub_Res.Last_Confirmed =
           HRA.Issue_Realization_Preparation.Publication.W2,
         "issue target drift rejects at W2 without rollback");

      Assert
        (Read_Exact (Compose (Root, "actual.journal")) = Appended_Actual_Text
         and then Read_Exact (Sidecar_Path) = Relation_Row_Text,
         "W2 Actual and Relation remain intact after issue target drift");
   end;

   --  Test 8: W1 Step 2 Issue Stale (Relation published, but Issue target changed)
   declare
      Prepared : HRA.Issue_Realization_Resume.Prepared_Resume;
      Diag     : HRA.Issue_Realization_Resume.Resume_Diagnostic;
      Pub_Res  : HRA.Issue_Realization_Resume.Publication.Publication_Result;

      procedure Stale_Issue_Target_During_Step_2 (Staged_Path : String) is
      begin
         if Index (Staged_Path, "issues.tsv") > 0 then
            Write_Exact (Compose (Root, "issues.tsv"), Changed_Issues_Text);
         end if;
      end Stale_Issue_Target_During_Step_2;
   begin
      Reset (Appended_Actual_Text, Issues_Open_Text);
      Assert
        (Prepare_Resume_Call (Prepared, Diag),
         "prepare W1 for step-2 issue drift test");

      HRA.Writer.Test_Hooks.Set_After_Stage_Hook
        (Stale_Issue_Target_During_Step_2'Address);

      Assert
        (not HRA.Issue_Realization_Resume.Publication.Publish
           (Prepared, Pub_Res)
         and then Pub_Res.Kind =
           HRA.Issue_Realization_Preparation.Publication.Failed
         and then Pub_Res.Failed_Step =
           HRA.Issue_Realization_Preparation.Publication.Publishing_Issue
         and then Pub_Res.Last_Confirmed =
           HRA.Issue_Realization_Preparation.Publication.W2,
         "step-2 issue drift preserves confirmed W2 without cross-step rollback");

      HRA.Writer.Test_Hooks.Clear_After_Stage_Hook;

      Assert
        (Read_Exact (Compose (Root, "actual.journal")) = Appended_Actual_Text
         and then Read_Exact (Sidecar_Path) = Relation_Row_Text,
         "confirmed W2 Actual and Relation persist after step-2 failure");
   end;

   --  Test 9: Reconciliation Mismatch Rejection
   declare
      Prepared : HRA.Issue_Realization_Resume.Prepared_Resume;
      Diag     : HRA.Issue_Realization_Resume.Resume_Diagnostic;
   begin
      Reset (Mismatch_Actual_Text, Issues_Open_Text);
      Assert
        (not Prepare_Resume_Call (Prepared, Diag)
         and then Diag.Status = HRA.Issue_Realization_Resume.Reconciliation_Failed
         and then Diag.Reconciliation.Status =
           HRA.Issue_Realization_Reconciliation.Actual_Meaning_Mismatch,
         "semantic mismatch rejects preparation with no publication authority");
   end;

   --  Test 10: Included Actual Meaning Drift Fails Preparation
   declare
      Child_Path : constant String := Compose (Root, "child.journal");
      Root_With_Include : constant String :=
        "include child.journal" & ASCII.LF &
        "2026-08-20 Realized purchase" & ASCII.LF &
        "    ; event-id: new-actual" & ASCII.LF &
        "    assets:wallet         -700 JPY" & ASCII.LF &
        "    expenses:chair         700 JPY" & ASCII.LF;
      Child_Original : constant String :=
        "2026-08-13 Existing" & ASCII.LF &
        "    ; event-id: existing-actual" & ASCII.LF &
        "    expenses:chair         500 JPY" & ASCII.LF &
        "    assets:wallet         -500 JPY" & ASCII.LF;
      Child_Drifted_Meaning : constant String :=
        "2026-08-13 Existing" & ASCII.LF &
        "    ; event-id: existing-actual" & ASCII.LF &
        "    expenses:chair         600 JPY" & ASCII.LF &
        "    assets:wallet         -600 JPY" & ASCII.LF;

      Prepared : HRA.Issue_Realization_Resume.Prepared_Resume;
      Diag     : HRA.Issue_Realization_Resume.Resume_Diagnostic;
      State    : HRA.Household.Household_State;
      Error    : Unbounded_String;
   begin
      Reset (Root_With_Include, Issues_Open_Text);
      Write_Exact (Child_Path, Child_Original);

      if not HRA.Household.Load_Canonical_Household (Root, State, Error) then
         raise Program_Error with To_String (Error);
      end if;

      --  Mutate included source on disk after State was admitted
      Write_Exact (Child_Path, Child_Drifted_Meaning);

      Assert
        (not HRA.Issue_Realization_Resume.Prepare_Resume
           (State                => State,
            Tx                   => Tx,
            Issue_ID             => HRA.Issues.Make_Issue_Id ("ISSUE-OPEN"),
            Actual_ID            => AID ("new-actual"),
            Relation_Event_ID    => RID ("rel-new"),
            Relation_Recorded_On => D ("2026-08-21"),
            Closed_On            => D ("2026-08-22"),
            Relation_Details     => "selected chair",
            Relation_Observation => Observe_Relation,
            Prepared             => Prepared,
            Diag                 => Diag)
         and then Diag.Status =
           HRA.Issue_Realization_Resume.Actual_Graph_Load_Failed,
         "included Actual meaning drift fails resume preparation closed");
   end;

   --  Test 11: Included Actual Identity Drift Fails Preparation
   declare
      Child_Path : constant String := Compose (Root, "child.journal");
      Root_With_Include : constant String :=
        "include child.journal" & ASCII.LF &
        "2026-08-20 Realized purchase" & ASCII.LF &
        "    ; event-id: new-actual" & ASCII.LF &
        "    assets:wallet         -700 JPY" & ASCII.LF &
        "    expenses:chair         700 JPY" & ASCII.LF;
      Child_Original : constant String :=
        "2026-08-13 Existing" & ASCII.LF &
        "    ; event-id: existing-actual" & ASCII.LF &
        "    expenses:chair         500 JPY" & ASCII.LF &
        "    assets:wallet         -500 JPY" & ASCII.LF;
      Child_Drifted_Identity : constant String :=
        "2026-08-13 Existing" & ASCII.LF &
        "    ; event-id: changed-actual" & ASCII.LF &
        "    expenses:chair         500 JPY" & ASCII.LF &
        "    assets:wallet         -500 JPY" & ASCII.LF;

      Prepared : HRA.Issue_Realization_Resume.Prepared_Resume;
      Diag     : HRA.Issue_Realization_Resume.Resume_Diagnostic;
      State    : HRA.Household.Household_State;
      Error    : Unbounded_String;
   begin
      Reset (Root_With_Include, Issues_Open_Text);
      Write_Exact (Child_Path, Child_Original);

      if not HRA.Household.Load_Canonical_Household (Root, State, Error) then
         raise Program_Error with To_String (Error);
      end if;

      --  Mutate included source identity on disk after State was admitted
      Write_Exact (Child_Path, Child_Drifted_Identity);

      Assert
        (not HRA.Issue_Realization_Resume.Prepare_Resume
           (State                => State,
            Tx                   => Tx,
            Issue_ID             => HRA.Issues.Make_Issue_Id ("ISSUE-OPEN"),
            Actual_ID            => AID ("new-actual"),
            Relation_Event_ID    => RID ("rel-new"),
            Relation_Recorded_On => D ("2026-08-21"),
            Closed_On            => D ("2026-08-22"),
            Relation_Details     => "selected chair",
            Relation_Observation => Observe_Relation,
            Prepared             => Prepared,
            Diag                 => Diag)
         and then Diag.Status =
           HRA.Issue_Realization_Resume.Actual_Graph_Load_Failed,
         "included Actual identity drift fails resume preparation closed");
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
      HRA.Writer.Test_Hooks.Clear_After_Stage_Hook;
      HRA.Writer.Test_Hooks.Clear_After_Publish_Hook;
      if Exists (Root) then
         Delete_Tree (Root);
      end if;
      raise;
end Test_Issue_Realization_Resume;
