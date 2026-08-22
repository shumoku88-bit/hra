with Ada.Command_Line;
with Ada.Directories; use Ada.Directories;
with Ada.Streams; use Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO; use Ada.Text_IO;
with HRA.Account;
with HRA.Actual_Admission;
with HRA.Actual_Account_Admission;
with HRA.Actual_Candidate;
with HRA.Actual_Graph_Admission;
with HRA.Actual_Publication;
with HRA.Actual_Root_Candidate;
with HRA.Dates;
with HRA.Journal_Loader;
with HRA.Ledger;
with HRA.Money;
with HRA.Writer;

procedure Test_Actual_Publication is
   use type HRA.Actual_Publication.Publication_Status;
   use type HRA.Money.Quantity;
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

   function New_Transaction return HRA.Ledger.Transaction is
      Posts  : HRA.Ledger.Posting_Vectors.Vector;
      Tx     : HRA.Ledger.Transaction;
      Status : HRA.Ledger.Transaction_Error;
      JPY    : constant HRA.Money.Commodity := HRA.Money.Make_Commodity ("JPY");
   begin
      Posts.Append
        (HRA.Ledger.Make_Posting
           (HRA.Account.Make_Account ("assets:cash"),
            HRA.Money.Make_Amount (JPY, -300.0)));
      Posts.Append
        (HRA.Ledger.Make_Posting
           (HRA.Account.Make_Account ("expenses:household"),
            HRA.Money.Make_Amount (JPY, 300.0)));

      if not HRA.Ledger.Create_Transaction
        (D ("2026-08-20"), "Published Actual", Posts, Tx, Status)
      then
         raise Program_Error with "failed to create publication test transaction";
      end if;
      return Tx;
   end New_Transaction;

   function Registry return HRA.Account.Account_Registry is
      Result : HRA.Account.Account_Registry := HRA.Account.Empty_Registry;
      Status : HRA.Account.Registry_Status;
   begin
      if not HRA.Account.Register_Account
        (Result,
         HRA.Account.Declare_Account
           (HRA.Account.Make_Account ("assets:cash"), HRA.Account.Asset),
         Status)
      then
         raise Program_Error with "failed to register publication asset Account";
      end if;

      if not HRA.Account.Register_Account
        (Result,
         HRA.Account.Declare_Account
           (HRA.Account.Make_Account ("expenses:household"), HRA.Account.Expense),
         Status)
      then
         raise Program_Error with "failed to register publication expense Account";
      end if;
      return Result;
   end Registry;

   Temp_Dir   : constant String := ".hra-test-actual-publication";
   Root_Path  : constant String := Compose (Temp_Dir, "actual.journal");
   Child_Path : constant String := Compose (Temp_Dir, "child.journal");

   Root_Source : constant String :=
     "2026-08-18 Root Existing" & ASCII.LF &
     "    ; event-id: root-existing" & ASCII.LF &
     "    assets:cash" & ASCII.HT & "-100 JPY" & ASCII.LF &
     "    expenses:household" & ASCII.HT & "100 JPY" & ASCII.LF &
     "include child.journal" & ASCII.LF;

   Child_Source : constant String :=
     "2026-08-19 Child Existing" & ASCII.LF &
     "    ; event-id: child-existing" & ASCII.LF &
     "    assets:cash" & ASCII.HT & "-200 JPY" & ASCII.LF &
     "    expenses:household" & ASCII.HT & "200 JPY" & ASCII.LF;

   Changed_Child_Source : constant String :=
     "2026-08-19 Child Changed" & ASCII.LF &
     "    ; event-id: child-existing" & ASCII.LF &
     "    assets:cash" & ASCII.HT & "-250 JPY" & ASCII.LF &
     "    expenses:household" & ASCII.HT & "250 JPY" & ASCII.LF;

   procedure Reset_Files is
   begin
      if Exists (Temp_Dir) then
         Delete_Tree (Temp_Dir);
      end if;
      Create_Directory (Temp_Dir);
      Write_Exact (Root_Path, Root_Source);
      Write_Exact (Child_Path, Child_Source);
   end Reset_Files;

   procedure Build_Qualified
     (Qualified : out HRA.Actual_Account_Admission.Account_Qualified_Graph)
   is
      Loaded       : HRA.Journal_Loader.Journal_Observation;
      Load_Error   : Unbounded_String;
      Existing     : HRA.Actual_Admission.Actual_Observation;
      Actual_Diag  : HRA.Actual_Admission.Admission_Diagnostic;
      Block        : HRA.Actual_Candidate.Candidate_Block;
      Block_Diag   : HRA.Actual_Candidate.Candidate_Diagnostic;
      Root         : HRA.Actual_Root_Candidate.Candidate_Root;
      Root_Diag    : HRA.Actual_Root_Candidate.Candidate_Diagnostic;
      Graph        : HRA.Actual_Graph_Admission.Candidate_Graph;
      Graph_Diag   : HRA.Actual_Graph_Admission.Admission_Diagnostic;
      Account_Diag : HRA.Actual_Account_Admission.Admission_Diagnostic;
   begin
      if not HRA.Journal_Loader.Load_From_Root_Source
        (Root_Path, Root_Source, Loaded, Load_Error)
      then
         raise Program_Error with
           "failed to load existing publication graph: " & To_String (Load_Error);
      end if;

      if not HRA.Actual_Admission.Admit
        (Loaded.Value, Loaded.Evidence, Existing, Actual_Diag)
      then
         raise Program_Error with "failed to admit existing publication Actual authority";
      end if;

      if not HRA.Actual_Candidate.Prepare
        (New_Transaction, Actual_ID ("published-actual"), Block, Block_Diag)
      then
         raise Program_Error with "failed to prepare publication Actual block";
      end if;

      if not HRA.Actual_Root_Candidate.Prepare
        (Root_Path, Root_Source, Block, Root, Root_Diag)
      then
         raise Program_Error with "failed to prepare publication root candidate";
      end if;

      if not HRA.Actual_Graph_Admission.Admit_Candidate_Root
        (Existing, Root, Graph, Graph_Diag)
      then
         raise Program_Error with "failed to admit publication candidate graph";
      end if;

      if not HRA.Actual_Account_Admission.Admit
        (Registry, Graph, Qualified, Account_Diag)
      then
         raise Program_Error with "failed to qualify publication candidate Accounts";
      end if;
   end Build_Qualified;

   function Candidate_Text
     (Qualified : HRA.Actual_Account_Admission.Account_Qualified_Graph)
      return String
   is
      Graph : constant HRA.Actual_Graph_Admission.Candidate_Graph :=
        HRA.Actual_Account_Admission.Graph_Of (Qualified);
      Root : constant HRA.Actual_Root_Candidate.Candidate_Root :=
        HRA.Actual_Graph_Admission.Root_Of (Graph);
   begin
      return HRA.Actual_Root_Candidate.Text (Root);
   end Candidate_Text;

begin
   Put_Line ("--- Testing Actual qualified publication ---");

   Reset_Files;
   declare
      Qualified : HRA.Actual_Account_Admission.Account_Qualified_Graph;
      Diag      : HRA.Actual_Publication.Publication_Diagnostic;
   begin
      Build_Qualified (Qualified);
      declare
         Expected_Root : constant String := Candidate_Text (Qualified);
      begin
         Assert
           (HRA.Actual_Publication.Publish (Qualified, Diag)
            and then Diag.Status = HRA.Actual_Publication.Success
            and then Diag.Writer_Status = HRA.Writer.Success,
            "Account-qualified graph publishes through the retained exact source witness");
         Assert
           (Read_Exact (Root_Path) = Expected_Root,
            "Qualified publication replaces only the root with its admitted candidate bytes");
         Assert
           (Read_Exact (Child_Path) = Child_Source,
            "Qualified publication leaves included source bytes untouched");
      end;
   end;

   Reset_Files;
   declare
      Qualified : HRA.Actual_Account_Admission.Account_Qualified_Graph;
      Diag      : HRA.Actual_Publication.Publication_Diagnostic;
   begin
      Build_Qualified (Qualified);
      Write_Exact (Child_Path, Changed_Child_Source);

      Assert
        (not HRA.Actual_Publication.Publish (Qualified, Diag)
         and then Diag.Status = HRA.Actual_Publication.Writer_Rejected
         and then Diag.Writer_Status = HRA.Writer.Stale_Source_Rejected,
         "Included source drift after qualification rejects publication as stale");
      Assert
        (Read_Exact (Root_Path) = Root_Source,
         "Stale included source leaves the root at the exact observed premise");
      Assert
        (Read_Exact (Child_Path) = Changed_Child_Source,
         "Stale included source is never overwritten by Actual publication");
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
end Test_Actual_Publication;
