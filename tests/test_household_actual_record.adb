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
with HRA.Household_Actual_Record;
with HRA.Ledger;
with HRA.Money;
with HRA.Writer;

procedure Test_Household_Actual_Record is
   use type HRA.Household_Actual_Record.Record_Status;
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
      Tx     : HRA.Ledger.Transaction;
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
         raise Program_Error with "failed to build household record transaction";
      end if;
      return Tx;
   end Transaction_For;

   Temp_Dir : constant String := ".hra-test-household-actual-record";

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
           "failed to load household record fixture: " & To_String (Error);
      end if;
      return State;
   end Load_State;

begin
   Put_Line ("--- Testing Household Actual record boundary ---");

   Reset_Files;
   declare
      State        : constant HRA.Household.Household_State := Load_State;
      Before_Count : constant Natural :=
        HRA.Actual_Admission.Transaction_Count (State.Actual_Identity);
      Diag         : HRA.Household_Actual_Record.Record_Diagnostic;
      First_ID     : constant HRA.Actual_Admission.Actual_Id :=
        Actual_ID ("home-record-actual");
   begin
      Assert
        (HRA.Household_Actual_Record.Record_Actual
           (State,
            Transaction_For ("expenses:coffee", 700.0, "Recorded Coffee"),
            First_ID,
            Diag)
         and then Diag.Status = HRA.Household_Actual_Record.Success,
         "Admitted Household records one explicit Actual through the complete publication path");

      declare
         Reloaded : constant HRA.Household.Household_State := Load_State;
      begin
         Assert
           (HRA.Actual_Admission.Transaction_Count (Reloaded.Actual_Identity) =
              Before_Count + 1
            and then HRA.Actual_Admission.Has_Source_Durable_Identity
              (Reloaded.Actual_Identity, First_ID),
            "Published Actual is visible after ordinary Household reload with durable identity");
      end;

      declare
         Root_After_First : constant String :=
           Read_Exact (Path_For (State.Sources.Paths, Actual_Source));
         Stale_Diag : HRA.Household_Actual_Record.Record_Diagnostic;
      begin
         Assert
           (not HRA.Household_Actual_Record.Record_Actual
              (State,
               Transaction_For ("expenses:coffee", 300.0, "Stale Second Record"),
               Actual_ID ("stale-second-actual"),
               Stale_Diag)
            and then Stale_Diag.Status =
              HRA.Household_Actual_Record.Publication_Rejected
            and then Stale_Diag.Publication.Writer_Status =
              HRA.Writer.Stale_Source_Rejected,
            "Pre-publication Household state cannot silently publish a second Actual after the root changed");
         Assert
           (Read_Exact (Path_For (State.Sources.Paths, Actual_Source)) =
              Root_After_First,
            "Stale Household mutation attempt preserves the already-published root exactly");
      end;
   end;

   Reset_Files;
   declare
      State      : constant HRA.Household.Household_State := Load_State;
      Root_Path  : constant String := Path_For (State.Sources.Paths, Actual_Source);
      Root_Before : constant String := Read_Exact (Root_Path);
      Diag       : HRA.Household_Actual_Record.Record_Diagnostic;
   begin
      Assert
        (not HRA.Household_Actual_Record.Record_Actual
           (State,
            Transaction_For ("expenses:rogue", 100.0, "Undeclared Account"),
            Actual_ID ("rogue-account-actual"),
            Diag)
         and then Diag.Status =
           HRA.Household_Actual_Record.Account_Admission_Rejected
         and then To_String (Diag.Account.Account_Name) = "expenses:rogue",
         "Household record boundary uses the admitted canonical Account universe");
      Assert
        (Read_Exact (Root_Path) = Root_Before,
         "Account qualification failure leaves canonical Actual bytes untouched");
   end;

   Reset_Files;
   declare
      State : constant HRA.Household.Household_State := Load_State;
      Actual_Path : constant String :=
        Path_For (State.Sources.Paths, Actual_Source);
      Accounts_Path : constant String :=
        Path_For (State.Sources.Paths, Accounts_Source);
      Actual_Before : constant String := Read_Exact (Actual_Path);
      External_Accounts : constant String :=
        "account assets:wallet" & ASCII.LF &
        "  ; type: Asset" & ASCII.LF &
        "account income:salary" & ASCII.LF &
        "  ; type: Income" & ASCII.LF;
      Diag : HRA.Household_Actual_Record.Record_Diagnostic;
   begin
      Write_Exact (Accounts_Path, External_Accounts);
      Assert
        (not HRA.Household_Actual_Record.Record_Actual
           (State,
            Transaction_For ("expenses:coffee", 100.0, "Stale Account Authority"),
            Actual_ID ("stale-account-authority"),
            Diag)
         and then Diag.Status =
           HRA.Household_Actual_Record.Publication_Rejected
         and then Diag.Publication.Writer_Status =
           HRA.Writer.Stale_Source_Rejected,
         "Account-qualified Actual cannot publish after canonical Accounts source changes");
      Assert
        (Read_Exact (Actual_Path) = Actual_Before,
         "Stale Accounts premise rejection leaves canonical Actual bytes untouched");
      Assert
        (Read_Exact (Accounts_Path) = External_Accounts,
         "Stale Accounts premise rejection never rewrites external Account authority");
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
end Test_Household_Actual_Record;
