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
with HRA.Household_Actual_Preparation;
with HRA.Issue_Close;
with HRA.Issue_Realization_Preparation;
with HRA.Issue_Relation;
with HRA.Issue_Relation.Admission;
with HRA.Issue_Relation.Sidecar;
with HRA.Issue_Relation.TSV;
with HRA.Issue_Relation_Candidate;
with HRA.Issues;
with HRA.Ledger;
with HRA.Money;

procedure Test_Issue_Realization_Preparation is
   use type HRA.Actual_Admission.Actual_Id;
   use type HRA.Dates.Date;
   use type HRA.Household_Actual_Preparation.Preparation_Status;
   use type HRA.Issue_Close.Close_Status;
   use type HRA.Issue_Realization_Preparation.Preparation_Status;
   use type HRA.Issue_Relation.Admission.Admission_Status;
   use type HRA.Issue_Relation.Create_Status;
   use type HRA.Issue_Relation.Reference_Status;
   use type HRA.Issue_Relation.Sidecar.Presence;
   use type HRA.Issue_Relation_Candidate.Candidate_Status;
   use type HRA.Issues.Issue_Closed_Kind;
   use type HRA.Issues.Issue_Id;
   use type HRA.Issues.Issue_Status;
   use type HRA.Money.Quantity;

   Passed_Count : Natural := 0;
   Failed_Count : Natural := 0;

   procedure Assert (Condition : Boolean; Name : String) is
   begin
      if Condition then
         Put_Line ("[PASS] " & Name);
         Passed_Count := Passed_Count + 1;
      else
         Put_Line ("[FAIL] " & Name);
         Failed_Count := Failed_Count + 1;
      end if;
   end Assert;

   Temp_Root : constant String := ".hra-test-issue-realization-preparation";
   Other_Root : constant String :=
     ".hra-test-issue-realization-preparation-other";
   Sidecar_Path : constant String := Compose (Temp_Root, "issue-relations.tsv");
   Other_Sidecar_Path : constant String :=
     Compose (Other_Root, "issue-relations.tsv");

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
         if Size = 0 then
            SIO.Close (File);
            return "";
         end if;
         declare
            Bytes : Stream_Element_Array (1 .. Stream_Element_Offset (Size));
            Last  : Stream_Element_Offset;
            Text  : String (1 .. Natural (Size));
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
         raise Program_Error with "bad test date";
      end if;
      return Value;
   end D;

   function AID (Text : String) return HRA.Actual_Admission.Actual_Id is
      Value : HRA.Actual_Admission.Actual_Id;
      Status : HRA.Actual_Admission.Actual_Id_Status;
   begin
      if not HRA.Actual_Admission.Create_Actual_Id (Text, Value, Status) then
         raise Program_Error with "bad test Actual ID";
      end if;
      return Value;
   end AID;

   function RID (Text : String) return HRA.Issue_Relation.Relation_Event_Id is
      Value : HRA.Issue_Relation.Relation_Event_Id;
      Status : HRA.Issue_Relation.Relation_Event_Id_Status;
   begin
      if not HRA.Issue_Relation.Create_Relation_Event_Id (Text, Value, Status) then
         raise Program_Error with "bad test relation ID";
      end if;
      return Value;
   end RID;

   function Tx_For (Expense : String) return HRA.Ledger.Transaction is
      Posts : HRA.Ledger.Posting_Vectors.Vector;
      Tx : HRA.Ledger.Transaction;
      Status : HRA.Ledger.Transaction_Error;
      JPY : constant HRA.Money.Commodity := HRA.Money.Make_Commodity ("JPY");
   begin
      Posts.Append
        (HRA.Ledger.Make_Posting
           (HRA.Account.Make_Account ("assets:wallet"),
            HRA.Money.Make_Amount (JPY, -700.0)));
      Posts.Append
        (HRA.Ledger.Make_Posting
           (HRA.Account.Make_Account (Expense),
            HRA.Money.Make_Amount (JPY, 700.0)));
      if not HRA.Ledger.Create_Transaction
        (D ("2026-08-20"), "Realized purchase", Posts, Tx, Status)
      then
         raise Program_Error with "bad test transaction";
      end if;
      return Tx;
   end Tx_For;

   Issue_Header : constant String :=
     "issue_id" & ASCII.HT & "status" & ASCII.HT & "date" & ASCII.HT &
     "due" & ASCII.HT & "closed" & ASCII.HT & "category" & ASCII.HT &
     "title" & ASCII.HT & "amount" & ASCII.HT & "currency" & ASCII.HT &
     "details";

   Issues_Text : constant String :=
     Issue_Header & ASCII.LF &
     "ISSUE-OPEN" & ASCII.HT & "open" & ASCII.HT & "2026-08-01" & ASCII.HT &
     "none" & ASCII.HT & "none" & ASCII.HT & "purchase" & ASCII.HT &
     "Chair" & ASCII.HT & "" & ASCII.HT & "" & ASCII.HT &
     "compare two models" & ASCII.LF &
     "ISSUE-CLOSED" & ASCII.HT & "resolved" & ASCII.HT & "2026-08-01" & ASCII.HT &
     "none" & ASCII.HT & "2026-08-10" & ASCII.HT & "purchase" & ASCII.HT &
     "Old chair" & ASCII.HT & "" & ASCII.HT & "" & ASCII.HT &
     "already done" & ASCII.LF;

   Relation_Header : constant String :=
     HRA.Issue_Relation.TSV.Canonical_Header_Text;

   function Fixture return Source_Observation is
      Result : Source_Observation;
   begin
      Result.Root_Path := To_Unbounded_String (Temp_Root);
      Result.Paths := HRA.Household.Resolve_Source_Paths (Temp_Root);
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
         "income-account = ""income:salary""" & ASCII.LF &
         "[money]" & ASCII.LF & "primary-commodity = ""JPY""" & ASCII.LF &
         "[envelope-history]" & ASCII.LF & "identities = [""chair""]" & ASCII.LF &
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

   procedure Reset_Files (Sidecar : String := ""; Present : Boolean := False) is
      Obs : constant Source_Observation := Fixture;
   begin
      if Exists (Temp_Root) then
         Delete_Tree (Temp_Root);
      end if;
      Create_Directory (Temp_Root);
      for Source in Source_Name loop
         Write_Exact (Path_For (Obs.Paths, Source), Text_For (Obs, Source));
      end loop;
      if Present then
         Write_Exact (Sidecar_Path, Sidecar);
      end if;
   end Reset_Files;

   function Load_State return HRA.Household.Household_State is
      State : HRA.Household.Household_State;
      Error : Unbounded_String;
   begin
      if not HRA.Household.Load_Canonical_Household (Temp_Root, State, Error) then
         raise Program_Error with To_String (Error);
      end if;
      return State;
   end Load_State;

   function Observe_Relations return HRA.Issue_Relation.Sidecar.Observation is
      Value : HRA.Issue_Relation.Sidecar.Observation;
      Diag : HRA.Issue_Relation.Sidecar.Observation_Diagnostic;
   begin
      if not HRA.Issue_Relation.Sidecar.Observe (Temp_Root, Value, Diag) then
         raise Program_Error with "sidecar observation failed";
      end if;
      return Value;
   end Observe_Relations;

   function Canonical_Unchanged return Boolean is
      Obs : constant Source_Observation := Fixture;
   begin
      for Source in Source_Name loop
         if Read_Exact (Path_For (Obs.Paths, Source)) /= Text_For (Obs, Source) then
            return False;
         end if;
      end loop;
      return True;
   end Canonical_Unchanged;

   Open_ID : constant HRA.Issues.Issue_Id := HRA.Issues.Make_Issue_Id ("ISSUE-OPEN");
   Closed_ID : constant HRA.Issues.Issue_Id := HRA.Issues.Make_Issue_Id ("ISSUE-CLOSED");
   Missing_ID : constant HRA.Issues.Issue_Id := HRA.Issues.Make_Issue_Id ("ISSUE-MISSING");
   New_Actual : constant HRA.Actual_Admission.Actual_Id := AID ("new-actual");

   function Try_Prepare
     (State    : HRA.Household.Household_State;
      Issue    : HRA.Issues.Issue_Id;
      Actual   : HRA.Actual_Admission.Actual_Id := New_Actual;
      Rel_ID   : String := "rel-new";
      Details  : String := "selected chair";
      Closed   : String := "2026-08-22";
      Expense  : String := "expenses:chair";
      Prepared : out HRA.Issue_Realization_Preparation.Prepared_Realization;
      Diag     : out HRA.Issue_Realization_Preparation.Preparation_Diagnostic)
      return Boolean is
   begin
      return HRA.Issue_Realization_Preparation.Prepare
        (State                => State,
         Tx                   => Tx_For (Expense),
         Issue_ID             => Issue,
         Actual_ID            => Actual,
         Relation_Event_ID    => RID (Rel_ID),
         Relation_Recorded_On => D ("2026-08-21"),
         Closed_On            => D (Closed),
         Relation_Details     => Details,
         Relation_Observation => Observe_Relations,
         Prepared             => Prepared,
         Diag                 => Diag);
   end Try_Prepare;

begin
   Put_Line ("--- Testing Issue realization preparation ---");

   Reset_Files;
   declare
      State : constant HRA.Household.Household_State := Load_State;
      Observed : constant HRA.Issue_Relation.Sidecar.Observation := Observe_Relations;
      Prepared : HRA.Issue_Realization_Preparation.Prepared_Realization;
      Diag : HRA.Issue_Realization_Preparation.Preparation_Diagnostic;
      Before_Count : constant Natural :=
        HRA.Actual_Admission.Transaction_Count (State.Actual_Identity);
   begin
      Assert
        (Try_Prepare (State, Open_ID, Prepared => Prepared, Diag => Diag)
         and then Diag.Status = HRA.Issue_Realization_Preparation.Success,
         "successful realization composes three candidates with distinct dates");
      declare
         Actuals : constant HRA.Actual_Admission.Actual_Observation :=
           HRA.Issue_Realization_Preparation.Actual_Observation_Of (Prepared);
         Actual_Entry : constant HRA.Actual_Admission.Actual_Transaction_Entry :=
           HRA.Actual_Admission.Transaction_At (Actuals, Before_Count + 1);
      begin
         Assert
           (Actual_Entry.Tx.Date = D ("2026-08-20")
            and then Actual_Entry.Source_Durable_Identity.Present
            and then Actual_Entry.Source_Durable_Identity.Value = New_Actual,
            "identified candidate Actual retains supplied ID and independent Tx.Date");
      end;
      Assert (Canonical_Unchanged, "successful preparation publishes no canonical source");
      Assert
        (not Exists (Sidecar_Path)
         and then HRA.Issue_Relation.Sidecar.State_Of (Observed) =
           HRA.Issue_Relation.Sidecar.Absent,
         "Absent relation sidecar remains Absent after success");

      --  Characterize the central candidate-world law independently through its
      --  owners: the exact event fails against State Actuals and admits against
      --  the prepared Actual observation.
      declare
         Event : HRA.Issue_Relation.Relation_Event;
         Create_Status : HRA.Issue_Relation.Create_Status;
         Candidate : HRA.Issue_Relation_Candidate.Candidate_Source;
         Candidate_Diag : HRA.Issue_Relation_Candidate.Candidate_Diagnostic;
         History : HRA.Issue_Relation.Admission.Admitted_History;
         Admission_Diag : HRA.Issue_Relation.Admission.Admission_Diagnostic;
      begin
         Assert
           (HRA.Issue_Relation.Create_Realized_As
              (RID ("rel-law"), D ("2026-08-21"), Open_ID, New_Actual,
               "selected chair", Event, Create_Status)
            and then HRA.Issue_Relation_Candidate.Prepare
              (Observed, Event, Candidate, Candidate_Diag)
            and then HRA.Issue_Relation.Admission.Admit
              (HRA.Issue_Relation_Candidate.Text (Candidate), State.Issues,
               HRA.Issue_Realization_Preparation.Actual_Observation_Of (Prepared),
               History, Admission_Diag)
            and then HRA.Issue_Relation.Admission.Count (History) = 1
            and then HRA.Issue_Relation.Issue_Id
              (HRA.Issue_Relation.Admission.Element (History, 1)) = Open_ID
            and then HRA.Issue_Relation.Actual_Id
              (HRA.Issue_Relation.Admission.Element (History, 1)) = New_Actual
            and then HRA.Issue_Relation.Recorded_On
              (HRA.Issue_Relation.Admission.Element (History, 1)) =
                D ("2026-08-21")
            and then HRA.Issue_Relation.Details
              (HRA.Issue_Relation.Admission.Element (History, 1)) =
                "selected chair",
            "relation preserves supplied IDs, date, details and candidate-world admission");
         Assert
           (not HRA.Issue_Relation.Admission.Admit
              (HRA.Issue_Relation_Candidate.Text (Candidate), State.Issues,
               State.Actual_Identity, History, Admission_Diag)
            and then Admission_Diag.Status =
              HRA.Issue_Relation.Admission.Reference_Error
            and then Admission_Diag.Reference.Status =
              HRA.Issue_Relation.Unknown_Source_Durable_Actual,
            "same relation dangles in pre-publication Actual universe");
      end;

      declare
         Close_Candidate : HRA.Issue_Close.Candidate_Source;
         Close_Diag : HRA.Issue_Close.Close_Diagnostic;
         Closed_Issues : HRA.Issues.Issues_Inventory;
         Issues_Diag : HRA.Issues.Admission_Diagnostic;
      begin
         Assert
           (HRA.Issue_Close.Prepare_Close
              (Issues_Text, Open_ID, HRA.Issue_Close.Resolve_Issue,
               D ("2026-08-22"), Close_Candidate, Close_Diag)
            and then HRA.Issues.Admit_Issues_TSV
              (HRA.Issue_Close.Text (Close_Candidate), Closed_Issues, Issues_Diag)
            and then HRA.Issues.Element (Closed_Issues, 1).Status = HRA.Issues.Resolved
            and then HRA.Issues.Element (Closed_Issues, 1).Closed.Kind =
              HRA.Issues.Closed_On
            and then HRA.Issues.Element (Closed_Issues, 1).Closed.Closed_Date =
              D ("2026-08-22")
            and then To_String (HRA.Issues.Element (Closed_Issues, 1).Details) =
              "compare two models",
            "Issue close resolves target on independent date without changing details");
      end;
   end;

   --  A sidecar observation from another root cannot be recombined with this
   --  admitted Household, even though both values are independently valid.
   Reset_Files;
   if Exists (Other_Root) then
      Delete_Tree (Other_Root);
   end if;
   Create_Directory (Other_Root);
   declare
      Other_Sidecar_Text : constant String :=
        Relation_Header & ASCII.LF &
        "rel-other" & ASCII.HT & "2026-08-19" & ASCII.HT &
        "ISSUE-OPEN" & ASCII.HT & "realized-as" & ASCII.HT &
        "existing-actual" & ASCII.HT & "other root" & ASCII.LF;
      State_A : constant HRA.Household.Household_State := Load_State;
      Actual_Path : constant String :=
        Path_For (State_A.Sources.Paths, Actual_Source);
      Issues_Path : constant String :=
        Path_For (State_A.Sources.Paths, Issues_Source);
      Actual_Before : constant String := Read_Exact (Actual_Path);
      Issues_Before : constant String := Read_Exact (Issues_Path);
      Observation_B : HRA.Issue_Relation.Sidecar.Observation;
      Observation_Diag : HRA.Issue_Relation.Sidecar.Observation_Diagnostic;
      Prepared : HRA.Issue_Realization_Preparation.Prepared_Realization;
      Diag : HRA.Issue_Realization_Preparation.Preparation_Diagnostic;
   begin
      Write_Exact (Other_Sidecar_Path, Other_Sidecar_Text);
      if not HRA.Issue_Relation.Sidecar.Observe
        (Other_Root, Observation_B, Observation_Diag)
      then
         raise Program_Error with "failed to observe second Household root";
      end if;

      Assert
        (not HRA.Issue_Realization_Preparation.Prepare
           (State                => State_A,
            Tx                   => Tx_For ("expenses:chair"),
            Issue_ID             => Open_ID,
            Actual_ID            => New_Actual,
            Relation_Event_ID    => RID ("rel-cross-root"),
            Relation_Recorded_On => D ("2026-08-21"),
            Closed_On            => D ("2026-08-22"),
            Relation_Details     => "selected chair",
            Relation_Observation => Observation_B,
            Prepared             => Prepared,
            Diag                 => Diag)
         and then Diag.Status =
           HRA.Issue_Realization_Preparation.Relation_Observation_Root_Mismatch
         and then Diag.Actual.Status =
           HRA.Household_Actual_Preparation.Success,
         "relation observation from Household B rejects against Household A");
      Assert
        (Read_Exact (Actual_Path) = Actual_Before
         and then Read_Exact (Issues_Path) = Issues_Before
         and then Canonical_Unchanged,
         "cross-root rejection leaves Actual, Issues, and canonical sources unchanged");
      Assert
        (not Exists (Sidecar_Path)
         and then Read_Exact (Other_Sidecar_Path) = Other_Sidecar_Text,
         "cross-root rejection leaves sidecars A and B unchanged");
   end;
   Delete_Tree (Other_Root);

   Reset_Files
     (Relation_Header & ASCII.LF &
      "rel-duplicate" & ASCII.HT & "2026-08-15" & ASCII.HT &
      "ISSUE-OPEN" & ASCII.HT & "realized-as" & ASCII.HT &
      "existing-actual" & ASCII.HT & "earlier" & ASCII.LF,
      Present => True);
   declare
      State : constant HRA.Household.Household_State := Load_State;
      Before : constant String := Read_Exact (Sidecar_Path);
      Prepared : HRA.Issue_Realization_Preparation.Prepared_Realization;
      Diag : HRA.Issue_Realization_Preparation.Preparation_Diagnostic;
   begin
      Assert
        (not Try_Prepare
           (State, Open_ID, Rel_ID => "rel-duplicate", Prepared => Prepared, Diag => Diag)
         and then Diag.Status = HRA.Issue_Realization_Preparation.Relation_Candidate_Rejected
         and then Diag.Relation_Candidate.Status =
           HRA.Issue_Relation_Candidate.Candidate_Admission_Failed,
         "duplicate relation_event_id rejects at relation candidate stage");
      Assert
        (Canonical_Unchanged and then Read_Exact (Sidecar_Path) = Before,
         "duplicate failure writes nothing");
   end;

   Reset_Files ("bad" & ASCII.HT & "header" & ASCII.LF, Present => True);
   declare
      State : constant HRA.Household.Household_State := Load_State;
      Before : constant String := Read_Exact (Sidecar_Path);
      Prepared : HRA.Issue_Realization_Preparation.Prepared_Realization;
      Diag : HRA.Issue_Realization_Preparation.Preparation_Diagnostic;
   begin
      Assert
        (not Try_Prepare (State, Open_ID, Prepared => Prepared, Diag => Diag)
         and then Diag.Status = HRA.Issue_Realization_Preparation.Relation_Candidate_Rejected
         and then Diag.Relation_Candidate.Status =
           HRA.Issue_Relation_Candidate.Existing_Sidecar_Admission_Failed,
         "malformed existing relation sidecar rejects with typed diagnostic");
      Assert (Canonical_Unchanged and then Read_Exact (Sidecar_Path) = Before,
              "malformed sidecar failure writes nothing");
   end;

   Reset_Files;
   declare
      State : constant HRA.Household.Household_State := Load_State;
      Prepared : HRA.Issue_Realization_Preparation.Prepared_Realization;
      Diag : HRA.Issue_Realization_Preparation.Preparation_Diagnostic;
   begin
      Assert
        (not Try_Prepare (State, Missing_ID, Prepared => Prepared, Diag => Diag)
         and then Diag.Status =
           HRA.Issue_Realization_Preparation.Relation_Reference_Admission_Rejected
         and then Diag.Relation_Admission.Status =
           HRA.Issue_Relation.Admission.Reference_Error
         and then Diag.Relation_Admission.Reference.Status =
           HRA.Issue_Relation.Unknown_Issue,
         "unknown Issue rejects at candidate-world reference admission");
      Assert
        (not Try_Prepare (State, Closed_ID, Prepared => Prepared, Diag => Diag)
         and then Diag.Status = HRA.Issue_Realization_Preparation.Issue_Close_Rejected
         and then Diag.Issue_Close.Status = HRA.Issue_Close.Issue_Not_Open,
         "already-closed Issue rejects at close stage");
      Assert
        (not Try_Prepare
           (State, Open_ID, Expense => "expenses:undeclared",
            Prepared => Prepared, Diag => Diag)
         and then Diag.Status = HRA.Issue_Realization_Preparation.Actual_Preparation_Rejected
         and then Diag.Actual.Status =
           HRA.Household_Actual_Preparation.Account_Admission_Rejected,
         "undeclared Actual posting Account rejects before composition continues");
      Assert
        (not Try_Prepare
           (State, Open_ID, Details => " invalid ", Prepared => Prepared, Diag => Diag)
         and then Diag.Status = HRA.Issue_Realization_Preparation.Relation_Creation_Rejected
         and then Diag.Relation_Creation =
           HRA.Issue_Relation.Details_Have_Surrounding_Whitespace,
         "invalid relation Details rejects at typed creation stage");
      Assert
        (not Try_Prepare
           (State, Open_ID, Closed => "2026-07-31", Prepared => Prepared, Diag => Diag)
         and then Diag.Status = HRA.Issue_Realization_Preparation.Issue_Close_Rejected
         and then Diag.Issue_Close.Status = HRA.Issue_Close.Close_Before_Recorded,
         "Closed_On before Issue recorded date rejects at close stage");
      Assert
        (Canonical_Unchanged and then not Exists (Sidecar_Path),
         "all absent-sidecar failure stages write nothing");
   end;

   Delete_Tree (Temp_Root);
   if Exists (Other_Root) then
      Delete_Tree (Other_Root);
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
      if Exists (Temp_Root) then
         Delete_Tree (Temp_Root);
      end if;
      if Exists (Other_Root) then
         Delete_Tree (Other_Root);
      end if;
      raise;
end Test_Issue_Realization_Preparation;
