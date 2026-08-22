with Ada.Command_Line;
with Ada.Directories; use Ada.Directories;
with Ada.Streams; use Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO; use Ada.Text_IO;
with HRA.Account;
with HRA.Actual_Admission;
with HRA.Actual_Candidate;
with HRA.Canonical_Source; use HRA.Canonical_Source;
with HRA.Dates;
with HRA.Household;
with HRA.Actual_Publication;
with HRA.Household_Actual_Preparation;
with HRA.Ledger;
with HRA.Money;
with HRA.Writer;

procedure Test_Household_Actual_Preparation is
   use type HRA.Household_Actual_Preparation.Preparation_Status;
   use type HRA.Actual_Admission.Actual_Id;
   use type HRA.Actual_Candidate.Candidate_Status;
   use type HRA.Writer.Writer_Status;
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
   exception
      when others =>
         if SIO.Is_Open (File) then
            SIO.Close (File);
         end if;
         raise;
   end Write_Exact;

   function Read_Exact (Path : String) return String is
      package SIO renames Ada.Streams.Stream_IO;
      use type SIO.Count;
      File : SIO.File_Type;
   begin
      SIO.Open (File, SIO.In_File, Path);
      declare
         Byte_Count : constant SIO.Count := SIO.Size (File);
      begin
         if Byte_Count = 0 then
            SIO.Close (File);
            return "";
         end if;

         declare
            Bytes : Stream_Element_Array
              (1 .. Stream_Element_Offset (Byte_Count));
            Last  : Stream_Element_Offset;
            Value : String (1 .. Natural (Byte_Count));
         begin
            SIO.Read (File, Bytes, Last);
            if Last /= Bytes'Last then
               SIO.Close (File);
               raise Program_Error with "short exact test read";
            end if;
            for I in Bytes'Range loop
               Value (Natural (I)) := Character'Val (Bytes (I));
            end loop;
            SIO.Close (File);
            return Value;
         end;
      end;
   end Read_Exact;

   function D (Value : String) return HRA.Dates.Date is
      Result : HRA.Dates.Date;
      Status : HRA.Dates.Date_Status;
   begin
      if not HRA.Dates.Parse (Value, Result, Status) then
         raise Program_Error with "invalid test date: " & Value;
      end if;
      return Result;
   end D;

   function Actual_ID (Value : String) return HRA.Actual_Admission.Actual_Id is
      Result : HRA.Actual_Admission.Actual_Id;
      Status : HRA.Actual_Admission.Actual_Id_Status;
   begin
      if not HRA.Actual_Admission.Create_Actual_Id (Value, Result, Status) then
         raise Program_Error with "invalid test Actual id: " & Value;
      end if;
      return Result;
   end Actual_ID;

   function Transaction_For
     (Expense_Name : String;
      Amount       : HRA.Money.Quantity;
      Description  : String) return HRA.Ledger.Transaction
   is
      Posts  : HRA.Ledger.Posting_Vectors.Vector;
      Tx    : HRA.Ledger.Transaction;
      Status : HRA.Ledger.Transaction_Error;
      JPY    : constant HRA.Money.Commodity := HRA.Money.Make_Commodity ("JPY");
   begin
      Posts.Append
        (HRA.Ledger.Make_Posting
           (HRA.Account.Make_Account ("assets:wallet"),
            HRA.Money.Make_Amount (JPY, -Amount)));
      Posts.Append
        (HRA.Ledger.Make_Posting
           (HRA.Account.Make_Account (Expense_Name),
            HRA.Money.Make_Amount (JPY, Amount)));
      if not HRA.Ledger.Create_Transaction
        (D ("2026-08-20"), Description, Posts, Tx, Status)
      then
         raise Program_Error with "failed to build household preparation transaction";
      end if;
      return Tx;
   end Transaction_For;

   Temp_Dir : constant String := ".hra-test-household-actual-preparation";

   function Observation return Source_Observation is
      Result : Source_Observation;
   begin
      Result.Root_Path := To_Unbounded_String (Temp_Dir);
      Result.Paths := HRA.Household.Resolve_Source_Paths (Temp_Dir);

      Result.Texts (Accounts_Source) := To_Unbounded_String
        ("account assets:wallet" & ASCII.LF &
         "  ; type: Asset" & ASCII.LF &
         "account expenses:coffee" & ASCII.LF &
         "  ; type: Expense" & ASCII.LF &
         "account income:salary" & ASCII.LF &
         "  ; type: Income" & ASCII.LF);

      Result.Texts (Actual_Source) := To_Unbounded_String
        ("2026-08-13 Coffee Purchase" & ASCII.LF &
         "    ; event-id: existing-actual" & ASCII.LF &
         "    expenses:coffee         500 JPY" & ASCII.LF &
         "    assets:wallet          -500 JPY" & ASCII.LF);

      Result.Texts (Plan_Source) := To_Unbounded_String ("");

      Result.Texts (Entitlement_Source) := To_Unbounded_String
        ("2026-08-01 origin JPY ; clean Envelope epoch" & ASCII.LF &
         "2026-08-01 transfer unallocated -> coffee 1000 JPY" & ASCII.LF);

      Result.Texts (Envelope_Config_Source) := To_Unbounded_String
        ("[[backing-pools]]" & ASCII.LF &
         "id = ""liquid""" & ASCII.LF &
         "asset-accounts = [""assets:wallet""]" & ASCII.LF &
         "[[envelopes]]" & ASCII.LF &
         "id = ""coffee""" & ASCII.LF &
         "label = ""Coffee""" & ASCII.LF &
         "pacing = ""daily""" & ASCII.LF &
         "backing-pool = ""liquid""" & ASCII.LF);

      Result.Texts (Household_Config_Source) := To_Unbounded_String
        ("[cycle]" & ASCII.LF &
         "mode = ""income-anchor""" & ASCII.LF &
         "income-account = ""income:salary""" & ASCII.LF &
         "[money]" & ASCII.LF &
         "primary-commodity = ""JPY""" & ASCII.LF &
         "[envelope-history]" & ASCII.LF &
         "identities = [""coffee""]" & ASCII.LF &
         "[[envelope-history.expense-routing]]" & ASCII.LF &
         "effective-from = ""initial""" & ASCII.LF &
         "expense-account = ""expenses:coffee""" & ASCII.LF &
         "route = ""managed""" & ASCII.LF &
         "target = ""coffee""" & ASCII.LF &
         "note = ""record test routing""" & ASCII.LF);

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

      Result.Texts (Issues_Source) := To_Unbounded_String
        ("issue_id" & ASCII.HT & "status" & ASCII.HT & "date" & ASCII.HT &
         "due" & ASCII.HT & "closed" & ASCII.HT & "category" & ASCII.HT &
         "title" & ASCII.HT & "amount" & ASCII.HT & "currency" & ASCII.HT &
         "details" & ASCII.LF);
      return Result;
   end Observation;

   procedure Reset_Files is
      Obs : constant Source_Observation := Observation;
   begin
      if Exists (Temp_Dir) then
         Delete_Tree (Temp_Dir);
      end if;
      Create_Directory (Temp_Dir);
      for Source in Source_Name loop
         Write_Exact
           (Path_For (Obs.Paths, Source),
            Text_For (Obs, Source));
      end loop;
   end Reset_Files;

   function Load_State return HRA.Household.Household_State is
      State : HRA.Household.Household_State;
      Error : Unbounded_String;
   begin
      if not HRA.Household.Load_Canonical_Household
        (Temp_Dir, State, Error)
      then
         raise Program_Error with
           "failed to load household preparation fixture: " & To_String (Error);
      end if;
      return State;
   end Load_State;

begin
   Put_Line ("--- Testing Household Actual preparation boundary ---");

   Reset_Files;
   declare
      State : constant HRA.Household.Household_State := Load_State;
      Actual_Path : constant String := Path_For (State.Sources.Paths, Actual_Source);
      Accounts_Path : constant String := Path_For (State.Sources.Paths, Accounts_Source);
      Actual_Before : constant String := Read_Exact (Actual_Path);
      Accounts_Before : constant String := Read_Exact (Accounts_Path);
      Before_Count : constant Natural :=
        HRA.Actual_Admission.Transaction_Count (State.Actual_Identity);
      Prepared : HRA.Household_Actual_Preparation.Prepared_Actual;
      Diag : HRA.Household_Actual_Preparation.Preparation_Diagnostic;
   begin
      Assert
        (HRA.Household_Actual_Preparation.Prepare_Ordinary
           (State,
            Transaction_For ("expenses:coffee", 700.0, "Prepared Coffee"),
            Prepared,
            Diag)
         and then Diag.Status = HRA.Household_Actual_Preparation.Success,
         "Ordinary Household preparation succeeds");
      Assert
        (Read_Exact (Actual_Path) = Actual_Before
         and then Read_Exact (Accounts_Path) = Accounts_Before,
         "Ordinary preparation writes no canonical file");

      declare
         Candidate : constant HRA.Actual_Admission.Actual_Observation :=
           HRA.Household_Actual_Preparation.Observation_Of (Prepared);
         New_Entry : constant HRA.Actual_Admission.Actual_Transaction_Entry :=
           HRA.Actual_Admission.Transaction_At (Candidate, Before_Count + 1);
      begin
         Assert
           (not New_Entry.Identity.Present
            and then not New_Entry.Source_Durable_Identity.Present,
            "Ordinary prepared observation has no effective or source-durable identity");
         Assert
           (HRA.Actual_Admission.Transaction_Count (Candidate) = Before_Count + 1,
            "Ordinary prepared observation adds exactly one transaction");
      end;

      declare
         Invalid_Tx : HRA.Ledger.Transaction :=
           Transaction_For ("expenses:coffee", 100.0, "Temporary Description");
         Rejected : HRA.Household_Actual_Preparation.Prepared_Actual;
         Reject_Diag : HRA.Household_Actual_Preparation.Preparation_Diagnostic;
      begin
         Invalid_Tx.Code_Or_Payee := Null_Unbounded_String;
         Assert
           (not HRA.Household_Actual_Preparation.Prepare_Ordinary
              (State, Invalid_Tx, Rejected, Reject_Diag)
            and then Reject_Diag.Status =
              HRA.Household_Actual_Preparation.Candidate_Rejected
            and then Reject_Diag.Candidate.Status =
              HRA.Actual_Candidate.Description_Required,
            "Unrepresentable candidate rejects during preparation before publication");
         Assert
           (Read_Exact (Actual_Path) = Actual_Before,
            "Rejected candidate leaves Actual root unchanged");
      end;
   end;

   Reset_Files;
   declare
      State : constant HRA.Household.Household_State := Load_State;
      Actual_Path : constant String := Path_For (State.Sources.Paths, Actual_Source);
      Accounts_Path : constant String := Path_For (State.Sources.Paths, Accounts_Source);
      Actual_Before : constant String := Read_Exact (Actual_Path);
      Accounts_Before : constant String := Read_Exact (Accounts_Path);
      Before_Count : constant Natural :=
        HRA.Actual_Admission.Transaction_Count (State.Actual_Identity);
      Explicit_ID : constant HRA.Actual_Admission.Actual_Id :=
        Actual_ID ("prepared-explicit-actual");
      Prepared : HRA.Household_Actual_Preparation.Prepared_Actual;
      Diag : HRA.Household_Actual_Preparation.Preparation_Diagnostic;
   begin
      Assert
        (HRA.Household_Actual_Preparation.Prepare_Identified
           (State,
            Transaction_For ("expenses:coffee", 1200.0, "Prepared Identified"),
            Explicit_ID,
            Prepared,
            Diag)
         and then Diag.Status = HRA.Household_Actual_Preparation.Success,
         "Identified Household preparation succeeds");

      declare
         Candidate : constant HRA.Actual_Admission.Actual_Observation :=
           HRA.Household_Actual_Preparation.Observation_Of (Prepared);
         New_Entry : constant HRA.Actual_Admission.Actual_Transaction_Entry :=
           HRA.Actual_Admission.Transaction_At (Candidate, Before_Count + 1);
      begin
         Assert
           (New_Entry.Identity.Present
            and then New_Entry.Source_Durable_Identity.Present
            and then New_Entry.Identity.Value = Explicit_ID
            and then New_Entry.Source_Durable_Identity.Value = Explicit_ID,
            "Identified prepared observation retains the supplied source-durable Actual_Id");
      end;
      Assert
        (Read_Exact (Actual_Path) = Actual_Before
         and then Read_Exact (Accounts_Path) = Accounts_Before,
         "Identified preparation writes no canonical file");
   end;

   Reset_Files;
   declare
      State : constant HRA.Household.Household_State := Load_State;
      Actual_Path : constant String := Path_For (State.Sources.Paths, Actual_Source);
      Accounts_Path : constant String := Path_For (State.Sources.Paths, Accounts_Source);
      Actual_Before : constant String := Read_Exact (Actual_Path);
      Accounts_Before : constant String := Read_Exact (Accounts_Path);
      Prepared : HRA.Household_Actual_Preparation.Prepared_Actual;
      Diag : HRA.Household_Actual_Preparation.Preparation_Diagnostic;
   begin
      Assert
        (not HRA.Household_Actual_Preparation.Prepare_Ordinary
           (State,
            Transaction_For ("expenses:rogue", 100.0, "Undeclared Account"),
            Prepared,
            Diag)
         and then Diag.Status =
           HRA.Household_Actual_Preparation.Account_Admission_Rejected
         and then To_String (Diag.Account.Account_Name) = "expenses:rogue",
         "Undeclared Account rejects during Household preparation");
      Assert
        (Read_Exact (Actual_Path) = Actual_Before
         and then Read_Exact (Accounts_Path) = Accounts_Before,
         "Account qualification rejection publishes nothing");
   end;

   Reset_Files;
   declare
      State : constant HRA.Household.Household_State := Load_State;
      Actual_Path : constant String := Path_For (State.Sources.Paths, Actual_Source);
      Accounts_Path : constant String := Path_For (State.Sources.Paths, Accounts_Source);
      Actual_Before : constant String := Read_Exact (Actual_Path);
      Accounts_Before : constant String := Read_Exact (Accounts_Path);
      External_Accounts : constant String :=
        "account assets:wallet" & ASCII.LF &
        "  ; type: Asset" & ASCII.LF &
        "account income:salary" & ASCII.LF &
        "  ; type: Income" & ASCII.LF;
      Prepared : HRA.Household_Actual_Preparation.Prepared_Actual;
      Preparation_Diag : HRA.Household_Actual_Preparation.Preparation_Diagnostic;
      Publication_Diag : HRA.Actual_Publication.Publication_Diagnostic;
   begin
      Assert
        (HRA.Household_Actual_Preparation.Prepare_Ordinary
           (State,
            Transaction_For ("expenses:coffee", 100.0, "Retained Premise"),
            Prepared,
            Preparation_Diag),
         "Actual prepares before an external Accounts change");
      Assert
        (Read_Exact (Actual_Path) = Actual_Before
         and then Read_Exact (Accounts_Path) = Accounts_Before,
         "Successful preparation preserves exact Actual and Accounts bytes");

      Write_Exact (Accounts_Path, External_Accounts);
      declare
         Account_Guards : constant HRA.Writer.Source_Premise_Array (1 .. 1) :=
           [1 => HRA.Household_Actual_Preparation.Account_Premise_Of (Prepared)];
      begin
         Assert
           (not HRA.Actual_Publication.Publish_With_Guards
              (HRA.Household_Actual_Preparation.Qualified_Graph_Of (Prepared),
               Account_Guards,
               Publication_Diag)
            and then Publication_Diag.Writer_Status =
              HRA.Writer.Stale_Source_Rejected,
            "Publication uses Prepared_Actual's retained Accounts premise and fails stale");
      end;
      Assert
        (Read_Exact (Actual_Path) = Actual_Before,
         "Stale retained Accounts premise leaves Actual root unchanged");
      Assert
        (Read_Exact (Accounts_Path) = External_Accounts,
         "Stale publication never rewrites external Accounts authority");
   end;

   Delete_Tree (Temp_Dir);

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
      if Exists (Temp_Dir) then
         Delete_Tree (Temp_Dir);
      end if;
      raise;
end Test_Household_Actual_Preparation;
