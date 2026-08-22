with Ada.Command_Line;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO; use Ada.Text_IO;
with HRA.Account;
with HRA.Dates;
with HRA.Household;
with HRA.Household_Actual_Draft;
with HRA.Ledger;
with HRA.Money;

procedure Test_Household_Actual_Draft is
   use type HRA.Household_Actual_Draft.Build_Status;
   use type HRA.Ledger.Transaction_Error;
   use type HRA.Money.Commodity;
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

   function D (Value : String) return HRA.Dates.Date is
      Result : HRA.Dates.Date;
      Status : HRA.Dates.Date_Status;
   begin
      if not HRA.Dates.Parse (Value, Result, Status) then
         raise Program_Error with "invalid draft test date: " & Value;
      end if;
      return Result;
   end D;

   function State_With_Registry
     (Has_Primary : Boolean := True) return HRA.Household.Household_State
   is
      State  : HRA.Household.Household_State := HRA.Household.Empty_Household_State;
      Status : HRA.Account.Registry_Status;
      JPY    : constant HRA.Money.Commodity := HRA.Money.Make_Commodity ("JPY");
   begin
      if not HRA.Account.Register_Account
        (State.Registry,
         HRA.Account.Declare_Account
           (HRA.Account.Make_Account ("assets:wallet"), HRA.Account.Asset),
         Status)
      then
         raise Program_Error with "failed to register draft asset Account";
      end if;
      if not HRA.Account.Register_Account
        (State.Registry,
         HRA.Account.Declare_Account
           (HRA.Account.Make_Account ("expenses:coffee"), HRA.Account.Expense),
         Status)
      then
         raise Program_Error with "failed to register draft coffee Account";
      end if;
      if not HRA.Account.Register_Account
        (State.Registry,
         HRA.Account.Declare_Account
           (HRA.Account.Make_Account ("expenses:snack"), HRA.Account.Expense),
         Status)
      then
         raise Program_Error with "failed to register draft snack Account";
      end if;
      State.Household_Policy.Has_Primary_Commodity := Has_Primary;
      State.Household_Policy.Primary_Commodity := JPY;
      return State;
   end State_With_Registry;

   function Two_Posting_Draft
     (Left_Account  : String;
      Left_Amount   : String;
      Right_Account : String;
      Right_Amount  : String) return HRA.Household_Actual_Draft.Record_Draft
   is
      Draft : HRA.Household_Actual_Draft.Record_Draft :=
        HRA.Household_Actual_Draft.Start (D ("2026-08-20"));
   begin
      Draft := HRA.Household_Actual_Draft.Set_Description (Draft, "Coffee");
      Draft := HRA.Household_Actual_Draft.Set_Posting
        (Draft, 1, Left_Account, Left_Amount);
      Draft := HRA.Household_Actual_Draft.Set_Posting
        (Draft, 2, Right_Account, Right_Amount);
      return Draft;
   end Two_Posting_Draft;

begin
   Put_Line ("--- Testing Household Actual draft ---");

   declare
      Draft : HRA.Household_Actual_Draft.Record_Draft :=
        HRA.Household_Actual_Draft.Start (D ("2026-08-20"));
   begin
      Assert
        (HRA.Household_Actual_Draft.Posting_Count (Draft) = 2,
         "General Record starts with exactly two posting rows");
      Draft := HRA.Household_Actual_Draft.Set_Posting
        (Draft, 1, "assets:wallet", "-1000");
      Draft := HRA.Household_Actual_Draft.Resize_Postings (Draft, 3);
      Assert
        (HRA.Household_Actual_Draft.Posting_Count (Draft) = 3
         and then HRA.Household_Actual_Draft.Posting_At (Draft, 1).Account_Text =
           HRA.Account.To_Unbounded (HRA.Account.Make_Account ("assets:wallet")),
         "Growing posting rows preserves retained row contents and order");
      Draft := HRA.Household_Actual_Draft.Resize_Postings (Draft, 0);
      Assert
        (HRA.Household_Actual_Draft.Posting_Count (Draft) = 2,
         "General Record cannot resize below Ledger's two-posting interaction minimum");
   end;

   declare
      State : constant HRA.Household.Household_State := State_With_Registry;
      Draft : constant HRA.Household_Actual_Draft.Record_Draft :=
        Two_Posting_Draft
          (" assets:wallet ", "-700", "expenses:coffee", "700");
      Tx   : HRA.Ledger.Transaction;
      Diag : HRA.Household_Actual_Draft.Build_Diagnostic;
   begin
      Assert
        (HRA.Household_Actual_Draft.Build_Transaction (State, Draft, Tx, Diag)
         and then Diag.Status = HRA.Household_Actual_Draft.Success
         and then Natural (Tx.Postings.Length) = 2
         and then HRA.Money.Code (Tx.Postings.Element (1).Amt.Comm) = "JPY"
         and then Tx.Postings.Element (1).Amt.Val = -700.0
         and then Tx.Postings.Element (2).Amt.Val = 700.0,
         "Omitted Commodity lowers signed posting rows through Household primary commodity");
   end;

   declare
      State : constant HRA.Household.Household_State := State_With_Registry;
      Draft : constant HRA.Household_Actual_Draft.Record_Draft :=
        Two_Posting_Draft
          ("assets:wallet", "-12.50 USD", "expenses:coffee", "12.50 USD");
      Tx   : HRA.Ledger.Transaction;
      Diag : HRA.Household_Actual_Draft.Build_Diagnostic;
   begin
      Assert
        (HRA.Household_Actual_Draft.Build_Transaction (State, Draft, Tx, Diag)
         and then HRA.Money.Code (Tx.Postings.Element (1).Amt.Comm) = "USD"
         and then Tx.Postings.Element (2).Amt.Val = 12.50,
         "Explicit posting Commodity overrides Household primary commodity without changing draft shape");
   end;

   declare
      State : constant HRA.Household.Household_State := State_With_Registry;
      Draft : HRA.Household_Actual_Draft.Record_Draft :=
        HRA.Household_Actual_Draft.Start (D ("2026-08-20"));
      Tx   : HRA.Ledger.Transaction;
      Diag : HRA.Household_Actual_Draft.Build_Diagnostic;
   begin
      Draft := HRA.Household_Actual_Draft.Set_Description (Draft, "Split");
      Draft := HRA.Household_Actual_Draft.Resize_Postings (Draft, 3);
      Draft := HRA.Household_Actual_Draft.Set_Posting
        (Draft, 1, "assets:wallet", "-1000");
      Draft := HRA.Household_Actual_Draft.Set_Posting
        (Draft, 2, "expenses:coffee", "700");
      Draft := HRA.Household_Actual_Draft.Set_Posting
        (Draft, 3, "expenses:snack", "300");
      Assert
        (HRA.Household_Actual_Draft.Build_Transaction (State, Draft, Tx, Diag)
         and then Natural (Tx.Postings.Length) = 3,
         "Three-posting split remains one ordinary balanced typed transaction");
   end;

   declare
      State : constant HRA.Household.Household_State := State_With_Registry;
      Draft : constant HRA.Household_Actual_Draft.Record_Draft :=
        Two_Posting_Draft
          ("assets:wallet", "-100", "expenses:rogue", "100");
      Tx   : HRA.Ledger.Transaction;
      Diag : HRA.Household_Actual_Draft.Build_Diagnostic;
   begin
      Assert
        (not HRA.Household_Actual_Draft.Build_Transaction (State, Draft, Tx, Diag)
         and then Diag.Status = HRA.Household_Actual_Draft.Undeclared_Account
         and then Diag.Posting_Index = 2,
         "Draft lowering rejects Account text outside the admitted canonical registry");
   end;

   declare
      State : constant HRA.Household.Household_State :=
        State_With_Registry (Has_Primary => False);
      Draft : constant HRA.Household_Actual_Draft.Record_Draft :=
        Two_Posting_Draft
          ("assets:wallet", "-100", "expenses:coffee", "100");
      Tx   : HRA.Ledger.Transaction;
      Diag : HRA.Household_Actual_Draft.Build_Diagnostic;
   begin
      Assert
        (not HRA.Household_Actual_Draft.Build_Transaction (State, Draft, Tx, Diag)
         and then Diag.Status = HRA.Household_Actual_Draft.Missing_Primary_Commodity
         and then Diag.Posting_Index = 1,
         "Commodity omission never invents a currency when Household primary commodity is absent");
   end;

   declare
      State : constant HRA.Household.Household_State := State_With_Registry;
      Draft : constant HRA.Household_Actual_Draft.Record_Draft :=
        Two_Posting_Draft
          ("assets:wallet", "-100", "expenses:coffee", "90");
      Tx   : HRA.Ledger.Transaction;
      Diag : HRA.Household_Actual_Draft.Build_Diagnostic;
   begin
      Assert
        (not HRA.Household_Actual_Draft.Build_Transaction (State, Draft, Tx, Diag)
         and then Diag.Status = HRA.Household_Actual_Draft.Transaction_Rejected
         and then Diag.Ledger_Status = HRA.Ledger.Unbalanced_Transaction,
         "Draft lowering leaves complete balance law to typed Ledger transaction admission");
   end;

   Put_Line
     ("Summary: Passed =" & Natural'Image (Passed_Count) &
      ", Failed =" & Natural'Image (Failed_Count));
   if Failed_Count > 0 then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   else
      Put_Line ("RESULT: SUCCESS");
   end if;
end Test_Household_Actual_Draft;
