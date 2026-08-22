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
with HRA.Issue_Realization_Preparation;
with HRA.Issue_Realization_Preparation.Publication;
with HRA.Issue_Relation.Admission;
with HRA.Issue_Relation.Sidecar;
with HRA.Issue_Relation.TSV;
with HRA.Issues;
with HRA.Ledger;
with HRA.Money;
with HRA.Writer;
with HRA.Writer.Test_Hooks;

procedure Test_Issue_Realization_Publication is
   use type HRA.Issue_Realization_Preparation.Preparation_Status;
   use type HRA.Issue_Realization_Preparation.Publication.Confirmed_World;
   use type HRA.Issue_Realization_Preparation.Publication.Publication_Step;
   use type HRA.Issue_Realization_Preparation.Publication.Result_Kind;
   use type HRA.Issue_Relation.Sidecar.Presence;
   use type HRA.Issues.Issue_Status;
   use type HRA.Money.Quantity;
   use type HRA.Writer.Writer_Status;

   Passed : Natural := 0;
   Failed : Natural := 0;
   procedure Assert (Condition : Boolean; Name : String) is
   begin
      if Condition then
         Put_Line ("[PASS] " & Name); Passed := Passed + 1;
      else
         Put_Line ("[FAIL] " & Name); Failed := Failed + 1;
      end if;
   end Assert;

   Root : constant String := ".hra-test-issue-realization-publication";
   Sidecar_Path : constant String := Compose (Root, "issue-relations.tsv");

   procedure Write_Exact (Path : String; Text : String) is
      package SIO renames Ada.Streams.Stream_IO;
      File : SIO.File_Type;
   begin
      SIO.Create (File, SIO.Out_File, Path);
      if Text'Length > 0 then
         declare
            Bytes : Stream_Element_Array (1 .. Stream_Element_Offset (Text'Length));
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
         if Size = 0 then SIO.Close (File); return ""; end if;
         declare
            Bytes : Stream_Element_Array (1 .. Stream_Element_Offset (Size));
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
      Value : HRA.Dates.Date; Status : HRA.Dates.Date_Status;
   begin
      if not HRA.Dates.Parse (Text, Value, Status) then raise Program_Error; end if;
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
      Posts.Append (HRA.Ledger.Make_Posting
        (HRA.Account.Make_Account ("assets:wallet"),
         HRA.Money.Make_Amount (JPY, -700.0)));
      Posts.Append (HRA.Ledger.Make_Posting
        (HRA.Account.Make_Account ("expenses:chair"),
         HRA.Money.Make_Amount (JPY, 700.0)));
      if not HRA.Ledger.Create_Transaction
        (D ("2026-08-20"), "Realized purchase", Posts, Value, Status)
      then raise Program_Error; end if;
      return Value;
   end Tx;

   Issue_Header : constant String :=
     "issue_id" & ASCII.HT & "status" & ASCII.HT & "date" & ASCII.HT &
     "due" & ASCII.HT & "closed" & ASCII.HT & "category" & ASCII.HT &
     "title" & ASCII.HT & "amount" & ASCII.HT & "currency" & ASCII.HT &
     "details";
   Issues_Text : constant String := Issue_Header & ASCII.LF &
     "ISSUE-OPEN" & ASCII.HT & "open" & ASCII.HT & "2026-08-01" & ASCII.HT &
     "none" & ASCII.HT & "none" & ASCII.HT & "purchase" & ASCII.HT &
     "Chair" & ASCII.HT & "" & ASCII.HT & "" & ASCII.HT &
     "compare two models" & ASCII.LF;
   Changed_Issues_Text : constant String := Issue_Header & ASCII.LF &
     "ISSUE-OPEN" & ASCII.HT & "open" & ASCII.HT & "2026-08-01" & ASCII.HT &
     "none" & ASCII.HT & "none" & ASCII.HT & "purchase" & ASCII.HT &
     "Chair" & ASCII.HT & "" & ASCII.HT & "" & ASCII.HT &
     "externally changed details" & ASCII.LF;

   function Fixture return Source_Observation is
      Result : Source_Observation;
   begin
      Result.Root_Path := To_Unbounded_String (Root);
      Result.Paths := HRA.Household.Resolve_Source_Paths (Root);
      Result.Texts (Accounts_Source) := To_Unbounded_String
        ("account assets:wallet" & ASCII.LF & "  ; type: Asset" & ASCII.LF &
         "account expenses:chair" & ASCII.LF & "  ; type: Expense" & ASCII.LF &
         "account income:salary" & ASCII.LF & "  ; type: Income" & ASCII.LF);
      Result.Texts (Actual_Source) := To_Unbounded_String
        ("2026-08-13 Existing" & ASCII.LF &
         "    ; event-id: existing-actual" & ASCII.LF &
         "    expenses:chair         500 JPY" & ASCII.LF &
         "    assets:wallet         -500 JPY" & ASCII.LF);
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
      Result.Texts (Issues_Source) := To_Unbounded_String (Issues_Text);
      return Result;
   end Fixture;

   procedure Reset is
      Obs : constant Source_Observation := Fixture;
   begin
      HRA.Writer.Test_Hooks.Clear_After_Stage_Hook;
      HRA.Writer.Test_Hooks.Clear_After_Publish_Hook;
      if Exists (Root) then Delete_Tree (Root); end if;
      Create_Directory (Root);
      for Source in Source_Name loop
         Write_Exact (Path_For (Obs.Paths, Source), Text_For (Obs, Source));
      end loop;
   end Reset;

   function Load return HRA.Household.Household_State is
      State : HRA.Household.Household_State; Error : Unbounded_String;
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

   function Prepare
     (Prepared : out HRA.Issue_Realization_Preparation.Prepared_Realization)
      return Boolean is
      State : constant HRA.Household.Household_State := Load;
      Diag : HRA.Issue_Realization_Preparation.Preparation_Diagnostic;
   begin
      return HRA.Issue_Realization_Preparation.Prepare
        (State, Tx, HRA.Issues.Make_Issue_Id ("ISSUE-OPEN"), AID ("new-actual"),
         RID ("rel-new"), D ("2026-08-21"), D ("2026-08-22"),
         "selected chair", Observe_Relation, Prepared, Diag)
        and then Diag.Status = HRA.Issue_Realization_Preparation.Success;
   end Prepare;

   Published_Order : Unbounded_String;
   procedure Record_Order (Path : String) is
   begin
      if Length (Published_Order) > 0 then Append (Published_Order, ">"); end if;
      if Index (Path, "actual.journal") > 0 then Append (Published_Order, "Actual");
      elsif Index (Path, "issue-relations.tsv") > 0 then Append (Published_Order, "Relation");
      elsif Index (Path, "issues.tsv") > 0 then Append (Published_Order, "Issue");
      else Append (Published_Order, "Other"); end if;
   end Record_Order;

   procedure Stale_Relation_Target (Staged_Path : String) is
   begin
      if Index (Staged_Path, "issue-relations.tsv") > 0 then
         Write_Exact (Sidecar_Path, HRA.Issue_Relation.TSV.Canonical_Header_Text & ASCII.LF);
      end if;
   end Stale_Relation_Target;

   procedure Stale_Issue_Target (Staged_Path : String) is
   begin
      if Index (Staged_Path, "issues.tsv") > 0 then
         Write_Exact (Compose (Root, "issues.tsv"), Changed_Issues_Text);
      end if;
   end Stale_Issue_Target;

   procedure Remove_Actual_Before_Relation (Staged_Path : String) is
      Obs : constant Source_Observation := Fixture;
   begin
      if Index (Staged_Path, "issue-relations.tsv") > 0 then
         Write_Exact (Path_For (Obs.Paths, Actual_Source), Text_For (Obs, Actual_Source));
      end if;
   end Remove_Actual_Before_Relation;

   procedure Stale_Issues_Guard_For_Relation (Staged_Path : String) is
   begin
      if Index (Staged_Path, "issue-relations.tsv") > 0 then
         Write_Exact (Compose (Root, "issues.tsv"), Changed_Issues_Text);
      end if;
   end Stale_Issues_Guard_For_Relation;

   procedure Stale_Relation_Guard_For_Issue (Staged_Path : String) is
   begin
      if Index (Staged_Path, "issues.tsv") > 0 then
         Write_Exact
           (Sidecar_Path,
            HRA.Issue_Relation.TSV.Canonical_Header_Text & ASCII.LF &
            "rel-new" & ASCII.HT & "2026-08-21" & ASCII.HT &
            "ISSUE-OPEN" & ASCII.HT & "realized-as" & ASCII.HT &
            "new-actual" & ASCII.HT & "externally changed relation" & ASCII.LF);
      end if;
   end Stale_Relation_Guard_For_Issue;

begin
   Put_Line ("--- Testing Issue realization ordered publication ---");

   Reset;
   declare
      Prepared : HRA.Issue_Realization_Preparation.Prepared_Realization;
      Result : HRA.Issue_Realization_Preparation.Publication.Publication_Result;
      State : HRA.Household.Household_State;
      Error : Unbounded_String;
      Relations : HRA.Issue_Relation.Admission.Admitted_History;
      Relation_Diag : HRA.Issue_Relation.Admission.Admission_Diagnostic;
      Sidecar : HRA.Issue_Relation.Sidecar.Observation;
   begin
      Assert (Prepare (Prepared), "prepare W0 realization");
      Published_Order := Null_Unbounded_String;
      HRA.Writer.Test_Hooks.Set_After_Publish_Hook (Record_Order'Address);
      Assert
        (HRA.Issue_Realization_Preparation.Publication.Publish (Prepared, Result)
         and then Result.Kind = HRA.Issue_Realization_Preparation.Publication.Completed
         and then Result.Last_Confirmed = HRA.Issue_Realization_Preparation.Publication.W3,
         "W0 publishes through typed W3 success");
      HRA.Writer.Test_Hooks.Clear_After_Publish_Hook;
      Assert (To_String (Published_Order) = "Actual>Relation>Issue",
              "publication order is Actual then relation then Issue");
      Assert (HRA.Household.Load_Canonical_Household (Root, State, Error),
              "successful W3 canonical reload");
      Assert
        (HRA.Household_Check_Observation.Observe (State).Actual_Transactions = 2
         and then HRA.Household_Check_Observation.Observe (State).Open_Issues = 0
         and then HRA.Actual_Admission.Has_Source_Durable_Identity
           (State.Actual_Identity, AID ("new-actual")),
         "successful W3 canonical check and Actual identity");
      Sidecar := Observe_Relation;
      Assert
        (HRA.Issue_Relation.Sidecar.State_Of (Sidecar) = HRA.Issue_Relation.Sidecar.Present
         and then HRA.Issue_Relation.Admission.Admit
           (HRA.Issue_Relation.Sidecar.Text_Of (Sidecar), State.Issues,
            State.Actual_Identity, Relations, Relation_Diag)
         and then HRA.Issue_Relation.Admission.Count (Relations) = 1,
         "successful W3 relation cross-admits after canonical reload");
   end;

   Reset;
   declare
      Prepared : HRA.Issue_Realization_Preparation.Prepared_Realization;
      Result : HRA.Issue_Realization_Preparation.Publication.Publication_Result;
      Actual_Before : constant String := Read_Exact (Compose (Root, "actual.journal"));
   begin
      Assert (Prepare (Prepared), "prepare Actual failure case");
      Write_Exact (Compose (Root, "issues.tsv"), Changed_Issues_Text);
      Assert
        (not HRA.Issue_Realization_Preparation.Publication.Publish (Prepared, Result)
         and then Result.Kind = HRA.Issue_Realization_Preparation.Publication.Failed
         and then Result.Last_Confirmed = HRA.Issue_Realization_Preparation.Publication.W0
         and then Result.Failed_Step = HRA.Issue_Realization_Preparation.Publication.Publishing_Actual
         and then Result.Writer_Status = HRA.Writer.Stale_Source_Rejected
         and then Read_Exact (Compose (Root, "actual.journal")) = Actual_Before
         and then not Exists (Sidecar_Path),
         "Issues premise drift rejects Actual publication at W0");
   end;

   Reset;
   declare
      Prepared : HRA.Issue_Realization_Preparation.Prepared_Realization;
      Result : HRA.Issue_Realization_Preparation.Publication.Publication_Result;
      State : HRA.Household.Household_State;
      Error : Unbounded_String;
   begin
      Assert (Prepare (Prepared), "prepare relation stale case");
      HRA.Writer.Test_Hooks.Set_After_Stage_Hook (Stale_Relation_Target'Address);
      Assert
        (not HRA.Issue_Realization_Preparation.Publication.Publish (Prepared, Result)
         and then Result.Last_Confirmed = HRA.Issue_Realization_Preparation.Publication.W1
         and then Result.Failed_Step = HRA.Issue_Realization_Preparation.Publication.Publishing_Relation
         and then Result.Writer_Status = HRA.Writer.Stale_Source_Rejected,
         "relation target drift leaves typed W1");
      HRA.Writer.Test_Hooks.Clear_After_Stage_Hook;
      Assert
        (HRA.Household.Load_Canonical_Household (Root, State, Error)
         and then HRA.Actual_Admission.Has_Source_Durable_Identity
           (State.Actual_Identity, AID ("new-actual"))
         and then HRA.Issues.Element (State.Issues, 1).Status = HRA.Issues.Open,
         "relation failure does not roll back W1 Actual");
   end;

   Reset;
   declare
      Prepared : HRA.Issue_Realization_Preparation.Prepared_Realization;
      Result : HRA.Issue_Realization_Preparation.Publication.Publication_Result;
      State : HRA.Household.Household_State;
      Error : Unbounded_String;
      Sidecar : HRA.Issue_Relation.Sidecar.Observation;
   begin
      Assert (Prepare (Prepared), "prepare Issue stale case");
      HRA.Writer.Test_Hooks.Set_After_Stage_Hook (Stale_Issue_Target'Address);
      Assert
        (not HRA.Issue_Realization_Preparation.Publication.Publish (Prepared, Result)
         and then Result.Last_Confirmed = HRA.Issue_Realization_Preparation.Publication.W2
         and then Result.Failed_Step = HRA.Issue_Realization_Preparation.Publication.Publishing_Issue
         and then Result.Writer_Status = HRA.Writer.Stale_Source_Rejected,
         "Issue target drift leaves typed W2");
      HRA.Writer.Test_Hooks.Clear_After_Stage_Hook;
      Sidecar := Observe_Relation;
      Assert
        (HRA.Household.Load_Canonical_Household (Root, State, Error)
         and then HRA.Issues.Element (State.Issues, 1).Status = HRA.Issues.Open
         and then HRA.Issue_Relation.Sidecar.State_Of (Sidecar) = HRA.Issue_Relation.Sidecar.Present,
         "Issue failure does not roll back W2 relation or Actual");
   end;

   Reset;
   declare
      Prepared : HRA.Issue_Realization_Preparation.Prepared_Realization;
      Result : HRA.Issue_Realization_Preparation.Publication.Publication_Result;
   begin
      Assert (Prepare (Prepared), "prepare dangling relation guard case");
      HRA.Writer.Test_Hooks.Set_After_Stage_Hook (Remove_Actual_Before_Relation'Address);
      Assert
        (not HRA.Issue_Realization_Preparation.Publication.Publish (Prepared, Result)
         and then Result.Failed_Step = HRA.Issue_Realization_Preparation.Publication.Publishing_Relation
         and then Result.Writer_Status = HRA.Writer.Stale_Source_Rejected
         and then not Exists (Sidecar_Path),
         "Actual graph drift prevents dangling relation publication");
      HRA.Writer.Test_Hooks.Clear_After_Stage_Hook;
   end;

   Reset;
   declare
      Prepared : HRA.Issue_Realization_Preparation.Prepared_Realization;
      Result : HRA.Issue_Realization_Preparation.Publication.Publication_Result;
   begin
      Assert (Prepare (Prepared), "prepare relation Issues-guard drift case");
      HRA.Writer.Test_Hooks.Set_After_Stage_Hook
        (Stale_Issues_Guard_For_Relation'Address);
      Assert
        (not HRA.Issue_Realization_Preparation.Publication.Publish (Prepared, Result)
         and then Result.Last_Confirmed = HRA.Issue_Realization_Preparation.Publication.W1
         and then Result.Failed_Step = HRA.Issue_Realization_Preparation.Publication.Publishing_Relation
         and then Result.Writer_Status = HRA.Writer.Stale_Source_Rejected
         and then not Exists (Sidecar_Path),
         "Issues guard drift rejects relation without rolling back Actual");
      HRA.Writer.Test_Hooks.Clear_After_Stage_Hook;
   end;

   Reset;
   declare
      Prepared : HRA.Issue_Realization_Preparation.Prepared_Realization;
      Result : HRA.Issue_Realization_Preparation.Publication.Publication_Result;
      State : HRA.Household.Household_State;
      Error : Unbounded_String;
   begin
      Assert (Prepare (Prepared), "prepare Issue relation-guard drift case");
      HRA.Writer.Test_Hooks.Set_After_Stage_Hook
        (Stale_Relation_Guard_For_Issue'Address);
      Assert
        (not HRA.Issue_Realization_Preparation.Publication.Publish (Prepared, Result)
         and then Result.Last_Confirmed = HRA.Issue_Realization_Preparation.Publication.W2
         and then Result.Failed_Step = HRA.Issue_Realization_Preparation.Publication.Publishing_Issue
         and then Result.Writer_Status = HRA.Writer.Stale_Source_Rejected
         and then HRA.Household.Load_Canonical_Household (Root, State, Error)
         and then HRA.Issues.Element (State.Issues, 1).Status = HRA.Issues.Open,
         "relation guard drift rejects Issue close without cross-step rollback");
      HRA.Writer.Test_Hooks.Clear_After_Stage_Hook;
   end;

   Reset;
   if Exists (Root) then Delete_Tree (Root); end if;
   Put_Line ("Summary: Passed =" & Natural'Image (Passed) &
             ", Failed =" & Natural'Image (Failed));
   if Failed > 0 then Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   else Put_Line ("RESULT: SUCCESS"); end if;
exception
   when others =>
      HRA.Writer.Test_Hooks.Clear_After_Stage_Hook;
      HRA.Writer.Test_Hooks.Clear_After_Publish_Hook;
      if Exists (Root) then Delete_Tree (Root); end if;
      raise;
end Test_Issue_Realization_Publication;
