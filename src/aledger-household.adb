with Ada.Text_IO;          use Ada.Text_IO;
with Ada.Directories;        use Ada.Directories;
with ALedger.Journal;        use ALedger.Journal;

package body ALedger.Household is

   function Join_Path (Dir, File_Name : String) return String is
   begin
      if Dir'Length = 0 then
         return File_Name;
      elsif Dir (Dir'Last) = '/' then
         return Dir & File_Name;
      else
         return Dir & "/" & File_Name;
      end if;
   end Join_Path;

   function Resolve_Source_Paths (Root_Dir : String) return Source_Paths is
   begin
      return (Accounts_Journal => To_Unbounded_String (Join_Path (Root_Dir, "accounts.journal")),
              Actual_Journal   => To_Unbounded_String (Join_Path (Root_Dir, "actual.journal")),
              Plan_Journal     => To_Unbounded_String (Join_Path (Root_Dir, "plan.journal")),
              Budget_Journal   => To_Unbounded_String (Join_Path (Root_Dir, "budget.journal")),
              Budget_TOML      => To_Unbounded_String (Join_Path (Root_Dir, "budget.toml")),
              Household_TOML   => To_Unbounded_String (Join_Path (Root_Dir, "household.toml")),
              Report_TOML      => To_Unbounded_String (Join_Path (Root_Dir, "report.toml")),
              Issues_TSV       => To_Unbounded_String (Join_Path (Root_Dir, "issues.tsv")));
   end Resolve_Source_Paths;

   function Empty_Household_State return Household_State is
      State : Household_State;
   begin
      State.Registry        := Empty_Registry;
      State.Actual_Ledger   := Empty_Ledger;
      State.Plan_Ledger     := Empty_Ledger;
      State.Budget_Ledger   := Empty_Ledger;
      State.Combined_Ledger := Empty_Ledger;
      return State;
   end Empty_Household_State;

   function Read_File_Content (File_Path : String; Content : out Unbounded_String) return Boolean is
      F : File_Type;
   begin
      if not Exists (File_Path) then
         Content := Null_Unbounded_String;
         return False;
      end if;

      Open (F, In_File, File_Path);
      Content := Null_Unbounded_String;
      while not End_Of_File (F) loop
         Append (Content, Get_Line (F));
         Append (Content, ASCII.LF);
      end loop;
      Close (F);
      return True;
   exception
      when others =>
         Content := Null_Unbounded_String;
         return False;
   end Read_File_Content;

   function Load_Canonical_Household
     (Root_Dir  : String;
      State     : out Household_State;
      Error_Msg : out Unbounded_String) return Boolean
   is
      Result : Household_State := Empty_Household_State;
      Paths  : constant Source_Paths := Resolve_Source_Paths (Root_Dir);
      Content: Unbounded_String;
      Err    : Unbounded_String;
   begin
      Result.Root_Path := To_Unbounded_String (Root_Dir);
      Result.Paths     := Paths;

      --  1. Load accounts.journal (Account Registry)
      if Read_File_Content (To_String (Paths.Accounts_Journal), Content) then
         declare
            Acc_Ledger : Ledger.Ledger;
         begin
            if Parse_Journal_Text (To_String (Content), Acc_Ledger, Err) then
               Result.Registry := Acc_Ledger.Registry;
            end if;
         end;
      end if;

      --  2. Load actual.journal (Actual Ledger)
      if Read_File_Content (To_String (Paths.Actual_Journal), Content) then
         declare
            Act_Ledger : Ledger.Ledger;
         begin
            if not Parse_Journal_Text (To_String (Content), Act_Ledger, Err) then
               Error_Msg := To_Unbounded_String ("Error parsing actual.journal: " & To_String (Err));
               return False;
            end if;
            Result.Actual_Ledger := Act_Ledger;

            --  Merge account declarations and transactions
            for Decl of Declarations (Act_Ledger.Registry) loop
               Register_Or_Update_Account (Result.Registry, Decl);
            end loop;

            for Tx of Act_Ledger.Transactions loop
               declare
                  Status : Transaction_Error;
               begin
                  if not Add_Transaction (Result.Combined_Ledger, Tx, Status) then
                     null;
                  end if;
               end;
            end loop;
         end;
      end if;

      --  3. Load plan.journal (Plan Ledger)
      if Read_File_Content (To_String (Paths.Plan_Journal), Content) then
         declare
            Pln_Ledger : Ledger.Ledger;
         begin
            if Parse_Journal_Text (To_String (Content), Pln_Ledger, Err) then
               Result.Plan_Ledger := Pln_Ledger;
               for Decl of Declarations (Pln_Ledger.Registry) loop
                  Register_Or_Update_Account (Result.Registry, Decl);
               end loop;
            end if;
         end;
      end if;

      --  4. Load budget.journal (Budget Ledger)
      if Read_File_Content (To_String (Paths.Budget_Journal), Content) then
         declare
            Bgt_Ledger : Ledger.Ledger;
         begin
            if Parse_Journal_Text (To_String (Content), Bgt_Ledger, Err) then
               Result.Budget_Ledger := Bgt_Ledger;
               for Decl of Declarations (Bgt_Ledger.Registry) loop
                  Register_Or_Update_Account (Result.Registry, Decl);
               end loop;
               for Tx of Bgt_Ledger.Transactions loop
                  declare
                     Status : Transaction_Error;
                  begin
                     if not Add_Transaction (Result.Combined_Ledger, Tx, Status) then
                        null;
                     end if;
                  end;
               end loop;
            end if;
         end;
      end if;

      --  5. Load issues.tsv (Household Issues)
      if Read_File_Content (To_String (Paths.Issues_TSV), Content) then
         declare
            Inv : Issues_Inventory;
         begin
            if Parse_Issues_TSV (To_String (Content), Inv) then
               Result.Issues := Inv;
            end if;
         end;
      end if;

      --  Set combined ledger registry
      Result.Combined_Ledger.Registry := Result.Registry;
      Result.Actual_Ledger.Registry   := Result.Registry;
      Result.Plan_Ledger.Registry     := Result.Registry;
      Result.Budget_Ledger.Registry   := Result.Registry;

      State := Result;
      Error_Msg := Null_Unbounded_String;
      return True;
   end Load_Canonical_Household;

end ALedger.Household;
