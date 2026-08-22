with Ada.Command_Line;
with Ada.Directories; use Ada.Directories;
with Ada.Streams; use Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO; use Ada.Text_IO;
with HRA.Dates;
with HRA.Household;
with HRA.Issue_Close;
with HRA.Issue_Closure_Preparation;
with HRA.Issue_Closure_Preparation.Publication;
with HRA.Issues;
with HRA.Writer;
with HRA.Writer.Test_Hooks;

procedure Test_Issue_Closure_Preparation is
   use type HRA.Dates.Date;
   use type HRA.Issue_Close.Close_Disposition;
   use type HRA.Issue_Close.Close_Status;
   use type HRA.Issue_Closure_Preparation.Preparation_Status;
   use type HRA.Issue_Closure_Preparation.Publication.Completion_Kind;
   use type HRA.Issue_Closure_Preparation.Publication.Failure_Kind;
   use type HRA.Issue_Closure_Preparation.Publication.Result_Kind;
   use type HRA.Issues.Issue_Closed_Kind;
   use type HRA.Issues.Issue_Id;
   use type HRA.Issues.Issue_Status;
   use type HRA.Writer.Writer_Status;

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

   function D (Value : String) return HRA.Dates.Date is
      Result : HRA.Dates.Date;
      Status : HRA.Dates.Date_Status;
   begin
      if not HRA.Dates.Parse (Value, Result, Status) then
         raise Program_Error with "invalid test date: " & Value;
      end if;
      return Result;
   end D;

   Root : constant String := ".hra-test-issue-closure-prep";

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

   Header_Row : constant String :=
     "issue_id" & ASCII.HT &
     "status" & ASCII.HT &
     "date" & ASCII.HT &
     "due" & ASCII.HT &
     "closed" & ASCII.HT &
     "category" & ASCII.HT &
     "title" & ASCII.HT &
     "amount" & ASCII.HT &
     "currency" & ASCII.HT &
     "details";

   Open_Chair_Row : constant String :=
     "ISSUE-CHAIR" & ASCII.HT &
     "open" & ASCII.HT &
     "2026-08-10" & ASCII.HT &
     "2026-08-30" & ASCII.HT &
     "none" & ASCII.HT &
     "purchase" & ASCII.HT &
     "Ergonomic Chair" & ASCII.HT &
     "20000" & ASCII.HT &
     "JPY" & ASCII.HT &
     "compare two ergonomic models";

   Open_Desk_Row : constant String :=
     "ISSUE-DESK" & ASCII.HT &
     "open" & ASCII.HT &
     "2026-08-12" & ASCII.HT &
     "none" & ASCII.HT &
     "none" & ASCII.HT &
     "furniture" & ASCII.HT &
     "Standing Desk" & ASCII.HT &
     "" & ASCII.HT &
     "" & ASCII.HT &
     "evaluate dimensions";

   Closed_Old_Row : constant String :=
     "ISSUE-OLD" & ASCII.HT &
     "resolved" & ASCII.HT &
     "2026-08-01" & ASCII.HT &
     "none" & ASCII.HT &
     "2026-08-05" & ASCII.HT &
     "purchase" & ASCII.HT &
     "Old item" & ASCII.HT &
     "" & ASCII.HT &
     "" & ASCII.HT &
     "already finished";

   Initial_Issues_Text : constant String :=
     Header_Row & ASCII.LF &
     Open_Chair_Row & ASCII.LF &
     Open_Desk_Row & ASCII.LF &
     Closed_Old_Row & ASCII.LF;

   Accounts_Text : constant String :=
     "account assets:wallet" & ASCII.LF & "  ; type: Asset" & ASCII.LF &
     "account expenses:chair" & ASCII.LF & "  ; type: Expense" & ASCII.LF &
     "account expenses:desk" & ASCII.LF & "  ; type: Expense" & ASCII.LF &
     "account income:salary" & ASCII.LF & "  ; type: Income" & ASCII.LF;

   Actual_Text : constant String :=
     "2026-08-15 Base fact" & ASCII.LF &
     "    ; event-id: actual-1" & ASCII.LF &
     "    assets:wallet         -1000 JPY" & ASCII.LF &
     "    expenses:chair         1000 JPY" & ASCII.LF;

   Plan_Text : constant String := "";

   Entitlement_Text : constant String :=
     "2026-08-01 origin JPY ; epoch" & ASCII.LF &
     "2026-08-01 transfer unallocated -> chair 1000 JPY" & ASCII.LF;

   Envelope_Text : constant String :=
     "[[backing-pools]]" & ASCII.LF & "id = ""liquid""" & ASCII.LF &
     "asset-accounts = [""assets:wallet""]" & ASCII.LF &
     "[[envelopes]]" & ASCII.LF & "id = ""chair""" & ASCII.LF &
     "label = ""Chair""" & ASCII.LF & "pacing = ""daily""" & ASCII.LF &
     "backing-pool = ""liquid""" & ASCII.LF;

   Household_Text : constant String :=
     "[cycle]" & ASCII.LF & "mode = ""income-anchor""" & ASCII.LF &
     "income-account = ""income:salary""" & ASCII.LF & "[money]" & ASCII.LF &
     "primary-commodity = ""JPY""" & ASCII.LF & "[envelope-history]" & ASCII.LF &
     "identities = [""chair""]" & ASCII.LF &
     "[[envelope-history.expense-routing]]" & ASCII.LF &
     "effective-from = ""initial""" & ASCII.LF &
     "expense-account = ""expenses:chair""" & ASCII.LF &
     "route = ""managed""" & ASCII.LF & "target = ""chair""" & ASCII.LF &
     "note = ""fixture""" & ASCII.LF;

   Report_Text : constant String :=
     "[presentation.amounts]" & ASCII.LF & "negative-style = ""parentheses""" & ASCII.LF &
     "[reports.trial-balance]" & ASCII.LF & "as-of = ""latest""" & ASCII.LF &
     "[reports.balance-sheet]" & ASCII.LF & "as-of = ""latest""" & ASCII.LF &
     "[reports.profit-and-loss]" & ASCII.LF & "from = ""beginning""" & ASCII.LF &
     "through = ""latest""" & ASCII.LF & "[reports.daily-flow]" & ASCII.LF &
     "from = ""beginning""" & ASCII.LF & "through = ""latest""" & ASCII.LF &
     "max-date-columns = 7" & ASCII.LF & "[reports.monthly-accounts]" & ASCII.LF &
     "from = ""beginning""" & ASCII.LF & "through = ""latest""" & ASCII.LF &
     "[reports.recent-transactions]" & ASCII.LF & "through = ""latest""" & ASCII.LF &
     "count = 10" & ASCII.LF;

   procedure Reset (Issues_Content : String := Initial_Issues_Text) is
   begin
      if Exists (Root) then
         Delete_Tree (Root);
      end if;
      Create_Directory (Root);

      Write_Exact (Compose (Root, "accounts.journal"), Accounts_Text);
      Write_Exact (Compose (Root, "actual.journal"), Actual_Text);
      Write_Exact (Compose (Root, "plan.journal"), Plan_Text);
      Write_Exact (Compose (Root, "entitlement.journal"), Entitlement_Text);
      Write_Exact (Compose (Root, "envelope.toml"), Envelope_Text);
      Write_Exact (Compose (Root, "household.toml"), Household_Text);
      Write_Exact (Compose (Root, "report.toml"), Report_Text);
      Write_Exact (Compose (Root, "issues.tsv"), Issues_Content);
   end Reset;

begin
   Put_Line ("--- Testing Issue closure preparation & publication ---");

   --  Test 1: Open -> Resolved with explicit Closed_On
   declare
      State    : HRA.Household.Household_State;
      Error    : Unbounded_String;
      Prepared : HRA.Issue_Closure_Preparation.Prepared_Closure;
      Prep_Diag : HRA.Issue_Closure_Preparation.Preparation_Diagnostic;
      Pub_Res  : HRA.Issue_Closure_Preparation.Publication.Publication_Result;
      New_State : HRA.Household.Household_State;
      Chair_ID : constant HRA.Issues.Issue_Id :=
        HRA.Issues.Make_Issue_Id ("ISSUE-CHAIR");
   begin
      Reset;
      Assert
        (HRA.Household.Load_Canonical_Household (Root, State, Error),
         "initial Household admits for Resolve test");

      Assert
        (HRA.Issue_Closure_Preparation.Prepare
           (State       => State,
            Issue_ID    => Chair_ID,
            Disposition => HRA.Issue_Close.Resolve_Issue,
            Closed_On   => D ("2026-08-20"),
            Prepared    => Prepared,
            Diag        => Prep_Diag)
         and then Prep_Diag.Status = HRA.Issue_Closure_Preparation.Success
         and then not HRA.Issue_Closure_Preparation.Is_Already_Closed (Prepared)
         and then HRA.Issue_Closure_Preparation.Issue_Id_Of (Prepared) = Chair_ID
         and then HRA.Issue_Closure_Preparation.Disposition_Of (Prepared) =
           HRA.Issue_Close.Resolve_Issue
         and then HRA.Issue_Closure_Preparation.Closed_On_Of (Prepared) =
           D ("2026-08-20"),
         "prepare Open -> Resolved with explicit Closed_On");

      Assert
        (HRA.Issue_Closure_Preparation.Publication.Publish (Prepared, Pub_Res)
         and then Pub_Res.Kind =
           HRA.Issue_Closure_Preparation.Publication.Completed
         and then Pub_Res.Completion =
           HRA.Issue_Closure_Preparation.Publication.Newly_Closed,
         "publish Open -> Resolved succeeds");

      Assert
        (HRA.Household.Load_Canonical_Household (Root, New_State, Error),
         "re-admit Household after Resolve publication");

      declare
         Chair : constant HRA.Issues.Household_Issue :=
           HRA.Issues.Element (New_State.Issues, 1);
      begin
         Assert
           (Chair.Status = HRA.Issues.Resolved
            and then Chair.Closed.Kind = HRA.Issues.Closed_On
            and then Chair.Closed.Closed_Date = D ("2026-08-20"),
            "published Issue has status=resolved and exact Closed_On");

         Assert
           (To_String (Chair.Category) = "purchase"
            and then To_String (Chair.Title) = "Ergonomic Chair"
            and then Chair.Amt.Has_Amount
            and then To_String (Chair.Details) = "compare two ergonomic models",
            "other fields preserved across Resolve publication");
      end;
   end;

   --  Test 2: Open -> Dropped with explicit Closed_On
   declare
      State    : HRA.Household.Household_State;
      Error    : Unbounded_String;
      Prepared : HRA.Issue_Closure_Preparation.Prepared_Closure;
      Prep_Diag : HRA.Issue_Closure_Preparation.Preparation_Diagnostic;
      Pub_Res  : HRA.Issue_Closure_Preparation.Publication.Publication_Result;
      New_State : HRA.Household.Household_State;
      Desk_ID  : constant HRA.Issues.Issue_Id :=
        HRA.Issues.Make_Issue_Id ("ISSUE-DESK");
   begin
      Reset;
      Assert
        (HRA.Household.Load_Canonical_Household (Root, State, Error),
         "initial Household admits for Drop test");

      Assert
        (HRA.Issue_Closure_Preparation.Prepare
           (State       => State,
            Issue_ID    => Desk_ID,
            Disposition => HRA.Issue_Close.Drop_Issue,
            Closed_On   => D ("2026-08-21"),
            Prepared    => Prepared,
            Diag        => Prep_Diag)
         and then Prep_Diag.Status = HRA.Issue_Closure_Preparation.Success
         and then not HRA.Issue_Closure_Preparation.Is_Already_Closed (Prepared),
         "prepare Open -> Dropped with explicit Closed_On");

      Assert
        (HRA.Issue_Closure_Preparation.Publication.Publish (Prepared, Pub_Res)
         and then Pub_Res.Kind =
           HRA.Issue_Closure_Preparation.Publication.Completed
         and then Pub_Res.Completion =
           HRA.Issue_Closure_Preparation.Publication.Newly_Closed,
         "publish Open -> Dropped succeeds");

      Assert
        (HRA.Household.Load_Canonical_Household (Root, New_State, Error),
         "re-admit Household after Drop publication");

      declare
         Desk : constant HRA.Issues.Household_Issue :=
           HRA.Issues.Element (New_State.Issues, 2);
      begin
         Assert
           (Desk.Status = HRA.Issues.Dropped
            and then Desk.Closed.Kind = HRA.Issues.Closed_On
            and then Desk.Closed.Closed_Date = D ("2026-08-21"),
            "published Issue has status=dropped and exact Closed_On");

         Assert
           (To_String (Desk.Category) = "furniture"
            and then To_String (Desk.Title) = "Standing Desk"
            and then not Desk.Amt.Has_Amount
            and then To_String (Desk.Details) = "evaluate dimensions",
            "other fields preserved across Drop publication");
      end;
   end;

   --  Test 3: No Actual / Plan / Relation mutations
   declare
      Sidecar_Path : constant String := Compose (Root, "issue-relations.tsv");
   begin
      Assert
        (Read_Exact (Compose (Root, "actual.journal")) = Actual_Text,
         "Actual journal byte-for-byte untouched by Issue closure");
      Assert
        (Read_Exact (Compose (Root, "plan.journal")) = Plan_Text,
         "Plan journal byte-for-byte untouched by Issue closure");
      Assert
        (Read_Exact (Compose (Root, "accounts.journal")) = Accounts_Text,
         "Accounts journal byte-for-byte untouched by Issue closure");
      Assert
        (not Exists (Sidecar_Path),
         "no relation sidecar created for closure without financial fact");
   end;

   --  Test 4: Close before Recorded_On rejected
   declare
      State    : HRA.Household.Household_State;
      Error    : Unbounded_String;
      Prepared : HRA.Issue_Closure_Preparation.Prepared_Closure;
      Prep_Diag : HRA.Issue_Closure_Preparation.Preparation_Diagnostic;
      Chair_ID : constant HRA.Issues.Issue_Id :=
        HRA.Issues.Make_Issue_Id ("ISSUE-CHAIR");
   begin
      Reset;
      Assert
        (HRA.Household.Load_Canonical_Household (Root, State, Error),
         "initial Household admits for Recorded_On check");

      Assert
        (not HRA.Issue_Closure_Preparation.Prepare
           (State       => State,
            Issue_ID    => Chair_ID,
            Disposition => HRA.Issue_Close.Resolve_Issue,
            Closed_On   => D ("2026-08-01"), -- Recorded_On is 2026-08-10
            Prepared    => Prepared,
            Diag        => Prep_Diag)
         and then Prep_Diag.Status =
           HRA.Issue_Closure_Preparation.Issue_Close_Rejected
         and then Prep_Diag.Issue_Close.Status =
           HRA.Issue_Close.Close_Before_Recorded,
         "close before Recorded_On is rejected closed");
   end;

   --  Test 5: Nonexistent Issue ID rejected
   declare
      State    : HRA.Household.Household_State;
      Error    : Unbounded_String;
      Prepared : HRA.Issue_Closure_Preparation.Prepared_Closure;
      Prep_Diag : HRA.Issue_Closure_Preparation.Preparation_Diagnostic;
      Missing_ID : constant HRA.Issues.Issue_Id :=
        HRA.Issues.Make_Issue_Id ("ISSUE-NONEXISTENT");
   begin
      Reset;
      Assert
        (HRA.Household.Load_Canonical_Household (Root, State, Error),
         "initial Household admits for missing ID check");

      Assert
        (not HRA.Issue_Closure_Preparation.Prepare
           (State       => State,
            Issue_ID    => Missing_ID,
            Disposition => HRA.Issue_Close.Resolve_Issue,
            Closed_On   => D ("2026-08-20"),
            Prepared    => Prepared,
            Diag        => Prep_Diag)
         and then Prep_Diag.Status =
           HRA.Issue_Closure_Preparation.Issue_Close_Rejected
         and then Prep_Diag.Issue_Close.Status =
           HRA.Issue_Close.Issue_Not_Found,
         "nonexistent Issue ID is rejected closed");
   end;

   --  Test 6: Non-Open Issue with different parameters rejected
   declare
      State    : HRA.Household.Household_State;
      Error    : Unbounded_String;
      Prepared : HRA.Issue_Closure_Preparation.Prepared_Closure;
      Prep_Diag : HRA.Issue_Closure_Preparation.Preparation_Diagnostic;
      Old_ID   : constant HRA.Issues.Issue_Id :=
        HRA.Issues.Make_Issue_Id ("ISSUE-OLD"); -- Already resolved on 2026-08-05
   begin
      Reset;
      Assert
        (HRA.Household.Load_Canonical_Household (Root, State, Error),
         "initial Household admits for non-open mismatch check");

      --  Mismatch 1: Different closure date (requesting 2026-08-20, was 2026-08-05)
      Assert
        (not HRA.Issue_Closure_Preparation.Prepare
           (State       => State,
            Issue_ID    => Old_ID,
            Disposition => HRA.Issue_Close.Resolve_Issue,
            Closed_On   => D ("2026-08-20"),
            Prepared    => Prepared,
            Diag        => Prep_Diag)
         and then Prep_Diag.Status =
           HRA.Issue_Closure_Preparation.Issue_Close_Rejected,
         "already resolved Issue with different Closed_On is rejected");

      --  Mismatch 2: Different disposition (requesting Drop, was Resolved)
      Assert
        (not HRA.Issue_Closure_Preparation.Prepare
           (State       => State,
            Issue_ID    => Old_ID,
            Disposition => HRA.Issue_Close.Drop_Issue,
            Closed_On   => D ("2026-08-05"),
            Prepared    => Prepared,
            Diag        => Prep_Diag)
         and then Prep_Diag.Status =
           HRA.Issue_Closure_Preparation.Issue_Close_Rejected,
         "already resolved Issue with Drop disposition is rejected");
   end;

   --  Test 7: Stale issues.tsv target rejected with no mutation
   declare
      State    : HRA.Household.Household_State;
      Error    : Unbounded_String;
      Prepared : HRA.Issue_Closure_Preparation.Prepared_Closure;
      Prep_Diag : HRA.Issue_Closure_Preparation.Preparation_Diagnostic;
      Pub_Res  : HRA.Issue_Closure_Preparation.Publication.Publication_Result;
      Chair_ID : constant HRA.Issues.Issue_Id :=
        HRA.Issues.Make_Issue_Id ("ISSUE-CHAIR");

      procedure Stale_Issues_Target (Staged_Path : String) is
      begin
         if Index (Staged_Path, "issues.tsv") > 0 then
            Write_Exact
              (Compose (Root, "issues.tsv"),
               Initial_Issues_Text & "external drift" & ASCII.LF);
         end if;
      end Stale_Issues_Target;
   begin
      Reset;
      Assert
        (HRA.Household.Load_Canonical_Household (Root, State, Error),
         "initial Household admits for stale check");

      Assert
        (HRA.Issue_Closure_Preparation.Prepare
           (State       => State,
            Issue_ID    => Chair_ID,
            Disposition => HRA.Issue_Close.Resolve_Issue,
            Closed_On   => D ("2026-08-20"),
            Prepared    => Prepared,
            Diag        => Prep_Diag),
         "prepare closure before target drift");

      HRA.Writer.Test_Hooks.Set_After_Stage_Hook (Stale_Issues_Target'Address);

      Assert
        (not HRA.Issue_Closure_Preparation.Publication.Publish
           (Prepared, Pub_Res)
         and then Pub_Res.Kind =
           HRA.Issue_Closure_Preparation.Publication.Failed
         and then Pub_Res.Writer_Status =
           HRA.Writer.Stale_Source_Rejected,
         "stale issues.tsv target rejected with Stale_Source_Rejected");

      HRA.Writer.Test_Hooks.Clear_After_Stage_Hook;
   end;

   --  Test 8: Exact retry after already-published Resolve
   declare
      State    : HRA.Household.Household_State;
      Error    : Unbounded_String;
      Prepared : HRA.Issue_Closure_Preparation.Prepared_Closure;
      Prep_Diag : HRA.Issue_Closure_Preparation.Preparation_Diagnostic;
      Pub_Res  : HRA.Issue_Closure_Preparation.Publication.Publication_Result;
      Old_ID   : constant HRA.Issues.Issue_Id :=
        HRA.Issues.Make_Issue_Id ("ISSUE-OLD"); -- Already resolved on 2026-08-05
   begin
      Reset;
      Assert
        (HRA.Household.Load_Canonical_Household (Root, State, Error),
         "initial Household admits for retry Resolve test");

      declare
         Before_Text : constant String := Read_Exact (Compose (Root, "issues.tsv"));
      begin
         Assert
           (HRA.Issue_Closure_Preparation.Prepare
              (State       => State,
               Issue_ID    => Old_ID,
               Disposition => HRA.Issue_Close.Resolve_Issue,
               Closed_On   => D ("2026-08-05"),
               Prepared    => Prepared,
               Diag        => Prep_Diag)
            and then Prep_Diag.Status =
              HRA.Issue_Closure_Preparation.Already_Closed_As_Requested
            and then HRA.Issue_Closure_Preparation.Is_Already_Closed (Prepared),
            "prepare recognizes already-resolved exact retry request");

         Assert
           (HRA.Issue_Closure_Preparation.Publication.Publish (Prepared, Pub_Res)
            and then Pub_Res.Kind =
              HRA.Issue_Closure_Preparation.Publication.Completed
            and then Pub_Res.Completion =
              HRA.Issue_Closure_Preparation.Publication.Already_Closed,
            "publish exact retry succeeds as no-op");

         Assert
           (Read_Exact (Compose (Root, "issues.tsv")) = Before_Text,
            "issues.tsv left byte-for-byte untouched on exact retry");
      end;
   end;

   --  Test 9: Exact retry after already-published Drop (crash-after-publish scenario)
   declare
      State       : HRA.Household.Household_State;
      Error       : Unbounded_String;
      Prepared_1  : HRA.Issue_Closure_Preparation.Prepared_Closure;
      Prep_Diag_1 : HRA.Issue_Closure_Preparation.Preparation_Diagnostic;
      Pub_Res_1   : HRA.Issue_Closure_Preparation.Publication.Publication_Result;
      Post_State  : HRA.Household.Household_State;
      Prepared_2  : HRA.Issue_Closure_Preparation.Prepared_Closure;
      Prep_Diag_2 : HRA.Issue_Closure_Preparation.Preparation_Diagnostic;
      Pub_Res_2   : HRA.Issue_Closure_Preparation.Publication.Publication_Result;
      Desk_ID     : constant HRA.Issues.Issue_Id :=
        HRA.Issues.Make_Issue_Id ("ISSUE-DESK");
   begin
      Reset;
      --  Step 1: First attempt prepares and publishes Drop
      Assert
        (HRA.Household.Load_Canonical_Household (Root, State, Error),
         "initial Household admits for crash-retry test");

      Assert
        (HRA.Issue_Closure_Preparation.Prepare
           (State       => State,
            Issue_ID    => Desk_ID,
            Disposition => HRA.Issue_Close.Drop_Issue,
            Closed_On   => D ("2026-08-22"),
            Prepared    => Prepared_1,
            Diag        => Prep_Diag_1),
         "initial prepare Drop succeeds");

      Assert
        (HRA.Issue_Closure_Preparation.Publication.Publish
           (Prepared_1, Pub_Res_1)
         and then Pub_Res_1.Completion =
           HRA.Issue_Closure_Preparation.Publication.Newly_Closed,
         "initial publish Drop succeeds");

      declare
         Written_Text : constant String := Read_Exact (Compose (Root, "issues.tsv"));
      begin
         --  Simulate crash & caller presenting the exact same request again
         Assert
           (HRA.Household.Load_Canonical_Household (Root, Post_State, Error),
            "re-load Household in new process after crash");

         Assert
           (HRA.Issue_Closure_Preparation.Prepare
              (State       => Post_State,
               Issue_ID    => Desk_ID,
               Disposition => HRA.Issue_Close.Drop_Issue,
               Closed_On   => D ("2026-08-22"),
               Prepared    => Prepared_2,
               Diag        => Prep_Diag_2)
            and then Prep_Diag_2.Status =
              HRA.Issue_Closure_Preparation.Already_Closed_As_Requested
            and then HRA.Issue_Closure_Preparation.Is_Already_Closed (Prepared_2),
            "crash retry recognizes already-dropped exact state");

         Assert
           (HRA.Issue_Closure_Preparation.Publication.Publish
              (Prepared_2, Pub_Res_2)
            and then Pub_Res_2.Kind =
              HRA.Issue_Closure_Preparation.Publication.Completed
            and then Pub_Res_2.Completion =
              HRA.Issue_Closure_Preparation.Publication.Already_Closed,
            "crash retry publication succeeds with Already_Closed completion");

         Assert
           (Read_Exact (Compose (Root, "issues.tsv")) = Written_Text,
            "issues.tsv unchanged after crash retry publication");
      end;
   end;

   --  Test 10: Already_Closed witness rejected when issues.tsv drifts before Publish
   declare
      State    : HRA.Household.Household_State;
      Error    : Unbounded_String;
      Prepared : HRA.Issue_Closure_Preparation.Prepared_Closure;
      Prep_Diag : HRA.Issue_Closure_Preparation.Preparation_Diagnostic;
      Pub_Res  : HRA.Issue_Closure_Preparation.Publication.Publication_Result;
      Old_ID   : constant HRA.Issues.Issue_Id :=
        HRA.Issues.Make_Issue_Id ("ISSUE-OLD");
      Drifted_Text : constant String :=
        Header_Row & ASCII.LF &
        Open_Chair_Row & ASCII.LF &
        Open_Desk_Row & ASCII.LF &
        "ISSUE-OLD" & ASCII.HT &
        "resolved" & ASCII.HT &
        "2026-08-01" & ASCII.HT &
        "none" & ASCII.HT &
        "2026-08-06" & ASCII.HT &
        "purchase" & ASCII.HT &
        "Old item" & ASCII.HT &
        "" & ASCII.HT &
        "" & ASCII.HT &
        "already finished" & ASCII.LF;
   begin
      Reset;
      Assert
        (HRA.Household.Load_Canonical_Household (Root, State, Error),
         "initial Household admits for stale retry test");

      Assert
        (HRA.Issue_Closure_Preparation.Prepare
           (State       => State,
            Issue_ID    => Old_ID,
            Disposition => HRA.Issue_Close.Resolve_Issue,
            Closed_On   => D ("2026-08-05"),
            Prepared    => Prepared,
            Diag        => Prep_Diag)
         and then Prep_Diag.Status =
           HRA.Issue_Closure_Preparation.Already_Closed_As_Requested
         and then HRA.Issue_Closure_Preparation.Is_Already_Closed (Prepared),
         "prepare recognizes already-resolved exact retry request");

      --  External mutation: change Closed_On of ISSUE-OLD from 2026-08-05 to 2026-08-06
      Write_Exact (Compose (Root, "issues.tsv"), Drifted_Text);

      Assert
        (not HRA.Issue_Closure_Preparation.Publication.Publish (Prepared, Pub_Res)
         and then Pub_Res.Kind =
           HRA.Issue_Closure_Preparation.Publication.Failed
         and then Pub_Res.Writer_Status =
           HRA.Writer.Stale_Source_Rejected,
         "stale issues.tsv premise rejects Already_Closed publish");

      Assert
        (Read_Exact (Compose (Root, "issues.tsv")) = Drifted_Text,
         "issues.tsv left untouched after stale retry rejection");
   end;

   --  Test 11: Already_Closed witness rejected when issues.tsv deleted before Publish
   declare
      State    : HRA.Household.Household_State;
      Error    : Unbounded_String;
      Prepared : HRA.Issue_Closure_Preparation.Prepared_Closure;
      Prep_Diag : HRA.Issue_Closure_Preparation.Preparation_Diagnostic;
      Pub_Res  : HRA.Issue_Closure_Preparation.Publication.Publication_Result;
      Old_ID   : constant HRA.Issues.Issue_Id :=
        HRA.Issues.Make_Issue_Id ("ISSUE-OLD");
   begin
      Reset;
      Assert
        (HRA.Household.Load_Canonical_Household (Root, State, Error),
         "initial Household admits for deleted retry test");

      Assert
        (HRA.Issue_Closure_Preparation.Prepare
           (State       => State,
            Issue_ID    => Old_ID,
            Disposition => HRA.Issue_Close.Resolve_Issue,
            Closed_On   => D ("2026-08-05"),
            Prepared    => Prepared,
            Diag        => Prep_Diag)
         and then Prep_Diag.Status =
           HRA.Issue_Closure_Preparation.Already_Closed_As_Requested
         and then HRA.Issue_Closure_Preparation.Is_Already_Closed (Prepared),
         "prepare recognizes already-resolved exact retry request");

      --  External mutation: delete issues.tsv
      Delete_File (Compose (Root, "issues.tsv"));

      Assert
        (not HRA.Issue_Closure_Preparation.Publication.Publish (Prepared, Pub_Res)
         and then Pub_Res.Kind =
           HRA.Issue_Closure_Preparation.Publication.Failed
         and then Pub_Res.Writer_Status =
           HRA.Writer.Stale_Source_Rejected,
         "deleted issues.tsv premise rejects Already_Closed publish");
   end;

   if Exists (Root) then
      Delete_Tree (Root);
   end if;

   Put_Line
     ("Summary: Passed =" & Natural'Image (Passed_Count) &
      ", Failed =" & Natural'Image (Failed_Count));
   if Failed_Count > 0 then
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
end Test_Issue_Closure_Preparation;
