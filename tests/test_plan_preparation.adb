with Ada.Command_Line;
with Ada.Directories; use Ada.Directories;
with Ada.Streams; use Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO; use Ada.Text_IO;
with HRA.Account;
with HRA.Canonical_Source; use HRA.Canonical_Source;
with HRA.Dates;
with HRA.Household;
with HRA.Household_Plan_Preparation;
with HRA.Household_Plan_Preparation.Publication;
with HRA.Ledger;
with HRA.Money;
with HRA.Plan;
with HRA.Plan_Admission;
with HRA.Plan_Candidate;
with HRA.Writer;

procedure Test_Plan_Preparation is
   use type HRA.Household_Plan_Preparation.Preparation_Status;
   use type HRA.Household_Plan_Preparation.Publication.Publication_Kind;
   use type HRA.Household_Plan_Preparation.Publication.Completion_Kind;
   use type HRA.Household_Plan_Preparation.Publication.Failure_Kind;
   use type HRA.Plan.Plan_Id;
   use type HRA.Plan_Candidate.Candidate_Status;
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

   function Make_PID (Value : String) return HRA.Plan.Plan_Id is
      Result : HRA.Plan.Plan_Id;
      Status : HRA.Plan.Plan_Id_Status;
   begin
      if not HRA.Plan.Create_Plan_Id (Value, Result, Status) then
         raise Program_Error with "invalid test Plan id: " & Value;
      end if;
      return Result;
   end Make_PID;

   function Transaction_For
     (Expense_Name : String;
      Amount       : HRA.Money.Quantity;
      Description  : String;
      Tx_Date      : String := "2026-09-01") return HRA.Ledger.Transaction
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
        (D (Tx_Date), Description, Posts, Tx, Status)
      then
         raise Program_Error with "failed to build plan preparation transaction";
      end if;
      return Tx;
   end Transaction_For;

   Temp_Dir : constant String := ".hra-test-household-plan-preparation";

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
         "account expenses:rent" & ASCII.LF &
         "  ; type: Expense" & ASCII.LF &
         "account income:salary" & ASCII.LF &
         "  ; type: Income" & ASCII.LF);

      Result.Texts (Actual_Source) := To_Unbounded_String
        ("2026-08-13 Coffee Purchase" & ASCII.LF &
         "    ; event-id: existing-actual" & ASCII.LF &
         "    expenses:coffee         500 JPY" & ASCII.LF &
         "    assets:wallet          -500 JPY" & ASCII.LF);

      Result.Texts (Plan_Source) := To_Unbounded_String
        ("2026-08-25 Planned Rent" & ASCII.LF &
         "    ; plan-id: existing-plan-1" & ASCII.LF &
         "    assets:wallet        -80000 JPY" & ASCII.LF &
         "    expenses:rent         80000 JPY" & ASCII.LF);

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
           "failed to load household plan preparation fixture: " & To_String (Error);
      end if;
      return State;
   end Load_State;

begin
   Put_Line ("--- Testing Household Plan preparation and publication authority ---");

   --  1. Fresh Plan candidate block validation
   declare
      Block : HRA.Plan_Candidate.Candidate_Block;
      Diag  : HRA.Plan_Candidate.Candidate_Diagnostic;
      Tx    : constant HRA.Ledger.Transaction :=
        Transaction_For ("expenses:coffee", 600.0, "Fresh Plan Coffee");
      PID   : constant HRA.Plan.Plan_Id := Make_PID ("plan-coffee-1");
   begin
      Assert
        (HRA.Plan_Candidate.Prepare_Pending (Tx, PID, Block, Diag)
         and then Diag.Status = HRA.Plan_Candidate.Success,
         "Plan candidate preparation succeeds for valid pending transaction");
      Assert
        (HRA.Plan_Candidate.Text (Block)'Length > 0,
         "Candidate block contains non-empty rendered Journal text");

      --  Malformed candidates rejected
      declare
         Null_PID : constant HRA.Plan.Plan_Id := HRA.Plan.Null_Plan_Id;
         Bad_Diag : HRA.Plan_Candidate.Candidate_Diagnostic;
      begin
         Assert
           (not HRA.Plan_Candidate.Prepare_Pending (Tx, Null_PID, Block, Bad_Diag)
            and then Bad_Diag.Status = HRA.Plan_Candidate.Invalid_Plan_Id,
            "Null Plan_Id is rejected by candidate preparation");
      end;

      declare
         Whitespace_Tx : HRA.Ledger.Transaction := Tx;
         Bad_Diag      : HRA.Plan_Candidate.Candidate_Diagnostic;
      begin
         Whitespace_Tx.Code_Or_Payee := To_Unbounded_String ("  leading space");
         Assert
           (not HRA.Plan_Candidate.Prepare_Pending (Whitespace_Tx, PID, Block, Bad_Diag)
            and then Bad_Diag.Status =
              HRA.Plan_Candidate.Description_Has_Surrounding_Whitespace,
            "Description with surrounding whitespace is rejected");
      end;
   end;

   --  2. Fresh Plan preparation in Household (publication-free)
   Reset_Files;
   declare
      State        : constant HRA.Household.Household_State := Load_State;
      Plan_Path    : constant String := Path_For (State.Sources.Paths, Plan_Source);
      Acc_Path     : constant String := Path_For (State.Sources.Paths, Accounts_Source);
      Plan_Before  : constant String := Read_Exact (Plan_Path);
      Acc_Before   : constant String := Read_Exact (Acc_Path);
      PID          : constant HRA.Plan.Plan_Id := Make_PID ("plan-coffee-fresh");
      Tx           : constant HRA.Ledger.Transaction :=
        Transaction_For ("expenses:coffee", 650.0, "Fresh Prepared Plan");
      Prepared     : HRA.Household_Plan_Preparation.Prepared_Plan;
      Diag         : HRA.Household_Plan_Preparation.Preparation_Diagnostic;
   begin
      Assert
        (HRA.Household_Plan_Preparation.Prepare
           (State, PID, Tx, Prepared, Diag)
         and then Diag.Status = HRA.Household_Plan_Preparation.Success,
         "Fresh Plan preparation succeeds in Household");
      Assert
        (not HRA.Household_Plan_Preparation.Is_Already_Present (Prepared),
         "Freshly prepared Plan is not marked as already present");
      Assert
        (HRA.Household_Plan_Preparation.Plan_Id_Of (Prepared) = PID,
         "Prepared Plan witness retains requested Plan_Id");
      Assert
        (Read_Exact (Plan_Path) = Plan_Before
         and then Read_Exact (Acc_Path) = Acc_Before,
         "Preparation writes no files to filesystem");
   end;

   --  3. Undeclared account rejected during preparation
   Reset_Files;
   declare
      State    : constant HRA.Household.Household_State := Load_State;
      PID      : constant HRA.Plan.Plan_Id := Make_PID ("plan-rogue");
      Tx       : constant HRA.Ledger.Transaction :=
        Transaction_For ("expenses:unknown_acc", 650.0, "Rogue Account Plan");
      Prepared : HRA.Household_Plan_Preparation.Prepared_Plan;
      Diag     : HRA.Household_Plan_Preparation.Preparation_Diagnostic;
   begin
      Assert
        (not HRA.Household_Plan_Preparation.Prepare
           (State, PID, Tx, Prepared, Diag)
         and then Diag.Status =
           HRA.Household_Plan_Preparation.Account_Admission_Rejected
         and then To_String (Diag.Account.Account_Name) = "expenses:unknown_acc",
         "Undeclared Account is rejected during Plan preparation");
   end;

   --  4. Duplicate Plan_Id with conflicting meaning rejected
   Reset_Files;
   declare
      State    : constant HRA.Household.Household_State := Load_State;
      PID      : constant HRA.Plan.Plan_Id := Make_PID ("existing-plan-1");
      Tx_Diff  : constant HRA.Ledger.Transaction :=
        Transaction_For ("expenses:coffee", 500.0, "Different Amount For Same ID");
      Prepared : HRA.Household_Plan_Preparation.Prepared_Plan;
      Diag     : HRA.Household_Plan_Preparation.Preparation_Diagnostic;
   begin
      Assert
        (not HRA.Household_Plan_Preparation.Prepare
           (State, PID, Tx_Diff, Prepared, Diag)
         and then Diag.Status =
           HRA.Household_Plan_Preparation.Conflicting_Plan_Already_Exists,
         "Duplicate Plan_Id with different transaction meaning is rejected");
   end;

   --  5. Exact retry recognition during preparation
   Reset_Files;
   declare
      State         : constant HRA.Household.Household_State := Load_State;
      PID           : constant HRA.Plan.Plan_Id := Make_PID ("existing-plan-1");
      Tx_Exact      : constant HRA.Ledger.Transaction :=
        Transaction_For ("expenses:rent", 80000.0, "Planned Rent", "2026-08-25");
      Prepared      : HRA.Household_Plan_Preparation.Prepared_Plan;
      Diag          : HRA.Household_Plan_Preparation.Preparation_Diagnostic;
      Pub_Result    : HRA.Household_Plan_Preparation.Publication.Publication_Result;
      Plan_Path     : constant String := Path_For (State.Sources.Paths, Plan_Source);
      Plan_Before   : constant String := Read_Exact (Plan_Path);
   begin
      Assert
        (HRA.Household_Plan_Preparation.Prepare
           (State, PID, Tx_Exact, Prepared, Diag)
         and then Diag.Status =
           HRA.Household_Plan_Preparation.Already_Present_As_Requested,
         "Identical Plan creation request recognized as Already_Present_As_Requested");
      Assert
        (HRA.Household_Plan_Preparation.Is_Already_Present (Prepared),
         "Retry prepared Plan is marked as already present");

      --  Publishing Already_Present is an exact verified no-op
      Assert
        (HRA.Household_Plan_Preparation.Publication.Publish (Prepared, Pub_Result)
         and then Pub_Result.Kind = HRA.Household_Plan_Preparation.Publication.Completed
         and then Pub_Result.Completion =
           HRA.Household_Plan_Preparation.Publication.Already_Present,
         "Already present Plan publication completes as verified no-op");
      Assert
        (Read_Exact (Plan_Path) = Plan_Before,
         "No-op publication leaves plan.journal untouched");
   end;

   --  6. Fresh publication succeeds and re-admits verified domain fact
   Reset_Files;
   declare
      State       : constant HRA.Household.Household_State := Load_State;
      Actual_Path : constant String := Path_For (State.Sources.Paths, Actual_Source);
      Issues_Path : constant String := Path_For (State.Sources.Paths, Issues_Source);
      Actual_Txt  : constant String := Read_Exact (Actual_Path);
      Issues_Txt  : constant String := Read_Exact (Issues_Path);
      PID         : constant HRA.Plan.Plan_Id := Make_PID ("plan-coffee-new");
      Tx          : constant HRA.Ledger.Transaction :=
        Transaction_For ("expenses:coffee", 720.0, "New Published Plan");
      Prepared    : HRA.Household_Plan_Preparation.Prepared_Plan;
      Prep_Diag   : HRA.Household_Plan_Preparation.Preparation_Diagnostic;
      Pub_Result  : HRA.Household_Plan_Preparation.Publication.Publication_Result;
   begin
      Assert
        (HRA.Household_Plan_Preparation.Prepare
           (State, PID, Tx, Prepared, Prep_Diag),
         "Fresh Plan prepares successfully");
      Assert
        (HRA.Household_Plan_Preparation.Publication.Publish
           (Prepared, Pub_Result)
         and then Pub_Result.Kind = HRA.Household_Plan_Preparation.Publication.Completed
         and then Pub_Result.Completion =
           HRA.Household_Plan_Preparation.Publication.Newly_Published,
         "Fresh Plan publication succeeds as Newly_Published");

      --  Check file contents and non-target sources untouched
      Assert
        (Read_Exact (Actual_Path) = Actual_Txt
         and then Read_Exact (Issues_Path) = Issues_Txt,
         "Actual and Issues sources untouched after Plan publication");

      --  Verify re-admission through Household
      declare
         Reloaded : constant HRA.Household.Household_State := Load_State;
      begin
         Assert
           (HRA.Plan_Admission.Transaction_Count (Reloaded.Plan_Journal) = 2,
            "Reloaded Household has 2 Plan transactions");
         Assert
           (HRA.Plan.Contains
              (HRA.Plan_Admission.Plan_Ids_Of (Reloaded.Plan_Journal), PID),
            "Reloaded Household contains newly published Plan_Id");
      end;
   end;

   --  7. Stale target rejected without mutation
   Reset_Files;
   declare
      State       : constant HRA.Household.Household_State := Load_State;
      Plan_Path   : constant String := Path_For (State.Sources.Paths, Plan_Source);
      PID         : constant HRA.Plan.Plan_Id := Make_PID ("plan-stale-test");
      Tx          : constant HRA.Ledger.Transaction :=
        Transaction_For ("expenses:coffee", 800.0, "Stale Test Plan");
      Prepared    : HRA.Household_Plan_Preparation.Prepared_Plan;
      Prep_Diag   : HRA.Household_Plan_Preparation.Preparation_Diagnostic;
      Pub_Result  : HRA.Household_Plan_Preparation.Publication.Publication_Result;
      External_Plan : constant String :=
        "2026-08-28 External Concurrent Plan" & ASCII.LF &
         "    ; plan-id: concurrent-plan" & ASCII.LF &
         "    expenses:coffee       300 JPY" & ASCII.LF &
         "    assets:wallet        -300 JPY" & ASCII.LF;
   begin
      Assert
        (HRA.Household_Plan_Preparation.Prepare
           (State, PID, Tx, Prepared, Prep_Diag),
         "Plan prepares before external target mutation");

      --  Mutate plan.journal externally
      Write_Exact (Plan_Path, External_Plan);

      Assert
        (not HRA.Household_Plan_Preparation.Publication.Publish
           (Prepared, Pub_Result)
         and then Pub_Result.Failure =
           HRA.Household_Plan_Preparation.Publication.Writer_Failure
         and then Pub_Result.Writer_Status = HRA.Writer.Stale_Source_Rejected,
         "Stale plan.journal rejected by Writer fence without mutation");
      Assert
        (Read_Exact (Plan_Path) = External_Plan,
         "External plan.journal preserved after stale rejection");
   end;

   --  8. Stale guard (accounts.journal) rejected without mutation
   Reset_Files;
   declare
      State       : constant HRA.Household.Household_State := Load_State;
      Plan_Path   : constant String := Path_For (State.Sources.Paths, Plan_Source);
      Acc_Path    : constant String := Path_For (State.Sources.Paths, Accounts_Source);
      Plan_Before : constant String := Read_Exact (Plan_Path);
      PID         : constant HRA.Plan.Plan_Id := Make_PID ("plan-guard-test");
      Tx          : constant HRA.Ledger.Transaction :=
        Transaction_For ("expenses:coffee", 900.0, "Guard Test Plan");
      Prepared    : HRA.Household_Plan_Preparation.Prepared_Plan;
      Prep_Diag   : HRA.Household_Plan_Preparation.Preparation_Diagnostic;
      Pub_Result  : HRA.Household_Plan_Preparation.Publication.Publication_Result;
      Modified_Acc : constant String :=
        "account assets:wallet" & ASCII.LF &
        "  ; type: Asset" & ASCII.LF &
        "account income:salary" & ASCII.LF &
        "  ; type: Income" & ASCII.LF;
   begin
      Assert
        (HRA.Household_Plan_Preparation.Prepare
           (State, PID, Tx, Prepared, Prep_Diag),
         "Plan prepares before external accounts mutation");

      --  Mutate accounts.journal externally
      Write_Exact (Acc_Path, Modified_Acc);

      Assert
        (not HRA.Household_Plan_Preparation.Publication.Publish
           (Prepared, Pub_Result)
         and then Pub_Result.Failure =
           HRA.Household_Plan_Preparation.Publication.Writer_Failure
         and then Pub_Result.Writer_Status = HRA.Writer.Stale_Source_Rejected,
         "Stale Accounts guard rejected by Writer fence");
      Assert
        (Read_Exact (Plan_Path) = Plan_Before,
         "Target plan.journal preserved after stale guard rejection");
   end;

   --  9. Retry premise drift rejected
   Reset_Files;
   declare
      State       : constant HRA.Household.Household_State := Load_State;
      Plan_Path   : constant String := Path_For (State.Sources.Paths, Plan_Source);
      PID         : constant HRA.Plan.Plan_Id := Make_PID ("existing-plan-1");
      Tx_Exact    : constant HRA.Ledger.Transaction :=
        Transaction_For ("expenses:rent", 80000.0, "Planned Rent", "2026-08-25");
      Prepared    : HRA.Household_Plan_Preparation.Prepared_Plan;
      Diag        : HRA.Household_Plan_Preparation.Preparation_Diagnostic;
      Pub_Result  : HRA.Household_Plan_Preparation.Publication.Publication_Result;
   begin
      Assert
        (HRA.Household_Plan_Preparation.Prepare
           (State, PID, Tx_Exact, Prepared, Diag)
         and then Diag.Status =
           HRA.Household_Plan_Preparation.Already_Present_As_Requested,
         "Retry prepared as Already_Present_As_Requested");

      --  External drift to plan.journal
      Write_Exact (Plan_Path, "");

      Assert
        (not HRA.Household_Plan_Preparation.Publication.Publish
           (Prepared, Pub_Result)
         and then Pub_Result.Failure =
           HRA.Household_Plan_Preparation.Publication.Writer_Failure
         and then Pub_Result.Writer_Status = HRA.Writer.Stale_Source_Rejected,
         "Drift in plan.journal rejects retry publication before success");
   end;

   --  10. Include graph support and include drift rejection
   Reset_Files;
   declare
      Sub_Dir        : constant String := Compose (Temp_Dir, "plans");
      Included_File  : constant String := Compose (Sub_Dir, "included.journal");
      Root_With_Inc  : constant String :=
        "include plans/included.journal" & ASCII.LF &
        "2026-08-25 Root Plan" & ASCII.LF &
        "    ; plan-id: root-plan" & ASCII.LF &
        "    expenses:coffee       400 JPY" & ASCII.LF &
        "    assets:wallet        -400 JPY" & ASCII.LF;
      Included_Text  : constant String :=
        "2026-08-20 Included Plan" & ASCII.LF &
        "    ; plan-id: inc-plan" & ASCII.LF &
        "    expenses:coffee       300 JPY" & ASCII.LF &
        "    assets:wallet        -300 JPY" & ASCII.LF;
   begin
      Create_Directory (Sub_Dir);
      Write_Exact (Included_File, Included_Text);
      Write_Exact (Compose (Temp_Dir, "plan.journal"), Root_With_Inc);

      declare
         State       : constant HRA.Household.Household_State := Load_State;
         PID         : constant HRA.Plan.Plan_Id := Make_PID ("new-root-plan-2");
         Tx          : constant HRA.Ledger.Transaction :=
           Transaction_For ("expenses:coffee", 550.0, "Second Root Plan");
         Prepared    : HRA.Household_Plan_Preparation.Prepared_Plan;
         Prep_Diag   : HRA.Household_Plan_Preparation.Preparation_Diagnostic;
         Pub_Result  : HRA.Household_Plan_Preparation.Publication.Publication_Result;
      begin
         Assert
           (HRA.Plan_Admission.Transaction_Count (State.Plan_Journal) = 2,
            "Plan include graph loads both root and included entries (count = 2)");
         Assert
           (HRA.Household_Plan_Preparation.Prepare
              (State, PID, Tx, Prepared, Prep_Diag),
            "Plan prepares successfully over include graph");

         --  Mutate included file to test include drift rejection
         Write_Exact (Included_File, "changed content");

         Assert
           (not HRA.Household_Plan_Preparation.Publication.Publish
              (Prepared, Pub_Result)
            and then Pub_Result.Failure =
              HRA.Household_Plan_Preparation.Publication.Writer_Failure
            and then Pub_Result.Writer_Status = HRA.Writer.Stale_Source_Rejected,
            "Included file drift is rejected by Writer fence in Plan publication");
      end;
   end;

   Delete_Tree (Temp_Dir);

   New_Line;
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
end Test_Plan_Preparation;
