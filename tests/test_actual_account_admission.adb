with Ada.Command_Line;
with Ada.Directories; use Ada.Directories;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO; use Ada.Text_IO;
with HRA.Account;
with HRA.Actual_Admission;
with HRA.Actual_Account_Admission;
with HRA.Actual_Candidate;
with HRA.Actual_Graph_Admission;
with HRA.Actual_Root_Candidate;
with HRA.Dates;
with HRA.Ledger;
with HRA.Money;

procedure Test_Actual_Account_Admission is
   use type HRA.Actual_Account_Admission.Admission_Status;
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

   procedure Write_Text (Path : String; Text : String) is
      File : File_Type;
   begin
      Create (File, Out_File, Path);
      Put (File, Text);
      Close (File);
   end Write_Text;

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

   function Make_Transaction
     (Expense_Name : String) return HRA.Ledger.Transaction
   is
      Posts  : HRA.Ledger.Posting_Vectors.Vector;
      Tx     : HRA.Ledger.Transaction;
      Status : HRA.Ledger.Transaction_Error;
      JPY    : constant HRA.Money.Commodity := HRA.Money.Make_Commodity ("JPY");
   begin
      Posts.Append
        (HRA.Ledger.Make_Posting
           (HRA.Account.Make_Account ("assets:cash"),
            HRA.Money.Make_Amount (JPY, -1_000.0)));
      Posts.Append
        (HRA.Ledger.Make_Posting
           (HRA.Account.Make_Account (Expense_Name),
            HRA.Money.Make_Amount (JPY, 1_000.0)));

      if not HRA.Ledger.Create_Transaction
        (D ("2026-08-20"), "Account Boundary", Posts, Tx, Status)
      then
         raise Program_Error with "failed to create account-boundary transaction";
      end if;
      return Tx;
   end Make_Transaction;

   function Make_Registry
     (Include_Expense : Boolean := True;
      Include_Asset   : Boolean := True) return HRA.Account.Account_Registry
   is
      Registry : HRA.Account.Account_Registry := HRA.Account.Empty_Registry;
      Status   : HRA.Account.Registry_Status;
   begin
      if Include_Asset then
         if not HRA.Account.Register_Account
           (Registry,
            HRA.Account.Declare_Account
              (HRA.Account.Make_Account ("assets:cash"), HRA.Account.Asset),
            Status)
         then
            raise Program_Error with "failed to declare asset test Account";
         end if;
      end if;

      if Include_Expense then
         if not HRA.Account.Register_Account
           (Registry,
            HRA.Account.Declare_Account
              (HRA.Account.Make_Account ("expenses:household"), HRA.Account.Expense),
            Status)
         then
            raise Program_Error with "failed to declare expense test Account";
         end if;
      end if;
      return Registry;
   end Make_Registry;

   Temp_Dir  : constant String := ".hra-test-actual-account-admission";
   Root_Path : constant String := Compose (Temp_Dir, "actual.journal");

   procedure Build_Graph
     (Expense_Name : String;
      ID_Text      : String;
      Graph        : out HRA.Actual_Graph_Admission.Candidate_Graph)
   is
      Block       : HRA.Actual_Candidate.Candidate_Block;
      Block_Diag  : HRA.Actual_Candidate.Candidate_Diagnostic;
      Root        : HRA.Actual_Root_Candidate.Candidate_Root;
      Root_Diag   : HRA.Actual_Root_Candidate.Candidate_Diagnostic;
      Graph_Diag  : HRA.Actual_Graph_Admission.Admission_Diagnostic;
      Existing    : HRA.Actual_Admission.Actual_Observation :=
        HRA.Actual_Admission.Empty_Observation;
   begin
      if not HRA.Actual_Candidate.Prepare_Identified
        (Make_Transaction (Expense_Name),
         Actual_ID (ID_Text),
         Block,
         Block_Diag)
      then
         raise Program_Error with "Actual block unexpectedly rejected before Account qualification";
      end if;

      if not HRA.Actual_Root_Candidate.Prepare
        (Root_Path, "", Block, Root, Root_Diag)
      then
         raise Program_Error with "root candidate unexpectedly rejected before Account qualification";
      end if;

      if not HRA.Actual_Graph_Admission.Admit_Candidate_Root
        (Existing, Root, Graph, Graph_Diag)
      then
         raise Program_Error with "graph candidate unexpectedly rejected before Account qualification";
      end if;
   end Build_Graph;

   procedure Build_Ordinary_Graph
     (Expense_Name : String;
      Graph        : out HRA.Actual_Graph_Admission.Candidate_Graph)
   is
      Block       : HRA.Actual_Candidate.Candidate_Block;
      Block_Diag  : HRA.Actual_Candidate.Candidate_Diagnostic;
      Root        : HRA.Actual_Root_Candidate.Candidate_Root;
      Root_Diag   : HRA.Actual_Root_Candidate.Candidate_Diagnostic;
      Graph_Diag  : HRA.Actual_Graph_Admission.Admission_Diagnostic;
      Existing    : HRA.Actual_Admission.Actual_Observation :=
        HRA.Actual_Admission.Empty_Observation;
   begin
      if not HRA.Actual_Candidate.Prepare_Ordinary
        (Make_Transaction (Expense_Name),
         Block,
         Block_Diag)
      then
         raise Program_Error with "ordinary Actual block unexpectedly rejected before Account qualification";
      end if;

      if not HRA.Actual_Root_Candidate.Prepare
        (Root_Path, "", Block, Root, Root_Diag)
      then
         raise Program_Error with "ordinary root candidate unexpectedly rejected before Account qualification";
      end if;

      if not HRA.Actual_Graph_Admission.Admit_Candidate_Root
        (Existing, Root, Graph, Graph_Diag)
      then
         raise Program_Error with "ordinary graph candidate unexpectedly rejected before Account qualification";
      end if;
   end Build_Ordinary_Graph;

begin
   Put_Line ("--- Testing Actual Account admission ---");

   if Exists (Temp_Dir) then
      Delete_Tree (Temp_Dir);
   end if;
   Create_Directory (Temp_Dir);
   Write_Text (Root_Path, "THIS ROOT IS PATH IDENTITY ONLY" & ASCII.LF);

   declare
      Registry      : HRA.Account.Account_Registry := Make_Registry;
      Before_Count  : constant Natural := HRA.Account.Declarations (Registry)'Length;
      Graph         : HRA.Actual_Graph_Admission.Candidate_Graph;
      Qualified     : HRA.Actual_Account_Admission.Account_Qualified_Graph;
      Diag          : HRA.Actual_Account_Admission.Admission_Diagnostic;
   begin
      Build_Graph ("expenses:household", "qualified-actual", Graph);
      Assert
        (HRA.Actual_Account_Admission.Admit
           (Registry, Graph, Qualified, Diag),
         "Declared candidate Accounts qualify without name-prefix inference");
      Assert
        (HRA.Actual_Admission.Transaction_Count
           (HRA.Actual_Account_Admission.Observation_Of (Qualified)) = 1,
         "Qualified graph preserves the already-admitted Actual observation");
      Assert
        (HRA.Account.Declarations (Registry)'Length = Before_Count,
         "Account qualification does not mutate canonical registry authority");
   end;

   declare
      Registry  : HRA.Account.Account_Registry := Make_Registry;
      Graph     : HRA.Actual_Graph_Admission.Candidate_Graph;
      Qualified : HRA.Actual_Account_Admission.Account_Qualified_Graph;
      Diag      : HRA.Actual_Account_Admission.Admission_Diagnostic;
   begin
      Build_Ordinary_Graph ("expenses:household", Graph);
      Assert
        (HRA.Actual_Account_Admission.Admit
           (Registry, Graph, Qualified, Diag),
         "Ordinary identity-free candidate graph qualifies against canonical Account registry");
      Assert
        (HRA.Actual_Admission.Transaction_Count
           (HRA.Actual_Account_Admission.Observation_Of (Qualified)) = 1,
         "Qualified ordinary graph preserves identity-free observation");
   end;

   declare
      Registry  : HRA.Account.Account_Registry := Make_Registry;
      Graph     : HRA.Actual_Graph_Admission.Candidate_Graph;
      Qualified : HRA.Actual_Account_Admission.Account_Qualified_Graph;
      Diag      : HRA.Actual_Account_Admission.Admission_Diagnostic;
   begin
      Build_Graph ("expenses:rogue", "rogue-actual", Graph);
      Assert
        (not HRA.Actual_Account_Admission.Admit
           (Registry, Graph, Qualified, Diag)
         and then Diag.Status = HRA.Actual_Account_Admission.Undeclared_Account
         and then Diag.Transaction_Index = 1
         and then Diag.Posting_Index = 2
         and then To_String (Diag.Account_Name) = "expenses:rogue",
         "Syntactically valid but undeclared Account is rejected only at Account-universe boundary");
   end;

   declare
      Wrong_Registry : HRA.Account.Account_Registry :=
        Make_Registry (Include_Expense => True, Include_Asset => False);
      Graph     : HRA.Actual_Graph_Admission.Candidate_Graph;
      Qualified : HRA.Actual_Account_Admission.Account_Qualified_Graph;
      Diag      : HRA.Actual_Account_Admission.Admission_Diagnostic;
   begin
      Build_Graph ("expenses:household", "wrong-universe-actual", Graph);
      Assert
        (not HRA.Actual_Account_Admission.Admit
           (Wrong_Registry, Graph, Qualified, Diag)
         and then Diag.Status = HRA.Actual_Account_Admission.Undeclared_Account
         and then To_String (Diag.Account_Name) = "assets:cash",
         "Candidate graph cannot be qualified against a different incomplete Account universe");
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
end Test_Actual_Account_Admission;
