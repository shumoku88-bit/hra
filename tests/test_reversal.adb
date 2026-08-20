with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO; use Ada.Text_IO;
with HRA.Account;
with HRA.Dates;
with HRA.Ledger;
with HRA.Money;

procedure Test_Reversal is
   use type HRA.Ledger.Transaction_Error;

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

   function D (Text : String) return HRA.Dates.Date is
      Value  : HRA.Dates.Date;
      Status : HRA.Dates.Date_Status;
   begin
      if not HRA.Dates.Parse (Text, Value, Status) then
         raise Program_Error with "invalid synthetic date";
      end if;
      return Value;
   end D;

   JPY : constant HRA.Money.Commodity := HRA.Money.Make_Commodity ("JPY");
   Cash : constant HRA.Account.Account := HRA.Account.Make_Account ("assets:cash");
   Expense : constant HRA.Account.Account :=
     HRA.Account.Make_Account ("expenses:gadgets");
   Postings : HRA.Ledger.Posting_Vectors.Vector;
   Original : HRA.Ledger.Transaction;
   Reversal : HRA.Ledger.Transaction;
   Status   : HRA.Ledger.Transaction_Error;

begin
   Put_Line ("--- Testing focused reversal laws ---");

   Postings.Append
     (HRA.Ledger.Make_Posting
        (Expense, HRA.Money.Make_Amount (JPY, 5000.0)));
   Postings.Append
     (HRA.Ledger.Make_Posting
        (Cash, HRA.Money.Make_Amount (JPY, -5000.0)));

   Assert
     (HRA.Ledger.Create_Transaction
        (D ("2026-08-10"), "Gadget purchase", Postings, Original, Status)
        and then Status = HRA.Ledger.Success,
      "balanced original transaction is admitted");
   Original.Event_ID := To_Unbounded_String ("evt-original");

   Assert
     (HRA.Ledger.Create_Reversal_Transaction
        (Original,
         "evt-reversal",
         D ("2026-08-11"),
         "return gadget",
         Reversal,
         Status)
        and then Status = HRA.Ledger.Success,
      "generated reversal is admitted");
   Assert
     (To_String (Reversal.Event_ID) = "evt-reversal"
        and then To_String (Reversal.Reverses_ID) = "evt-original",
      "generated reversal preserves durable relation identity");
   Assert
     (HRA.Ledger.Is_Reversal_Of (Reversal, Original),
      "generated reversal is the exact inverse of its target");

   declare
      Reordered : HRA.Ledger.Transaction := Reversal;
      First     : constant HRA.Ledger.Posting := Reordered.Postings.Element (1);
      Second    : constant HRA.Ledger.Posting := Reordered.Postings.Element (2);
   begin
      Reordered.Postings.Replace_Element (1, Second);
      Reordered.Postings.Replace_Element (2, First);
      Assert
        (HRA.Ledger.Is_Reversal_Of (Reordered, Original),
         "reversal identity depends on exact inverse postings, not display order");
   end;

   declare
      Wrong : HRA.Ledger.Transaction := Reversal;
      P     : HRA.Ledger.Posting := Wrong.Postings.Element (1);
   begin
      P.Acc := Cash;
      Wrong.Postings.Replace_Element (1, P);
      Assert
        (HRA.Ledger.Is_Balanced (Wrong)
           and then not HRA.Ledger.Is_Reversal_Of (Wrong, Original),
         "a balanced transaction that is not the target inverse is rejected");
   end;

   declare
      Book : HRA.Ledger.Ledger := HRA.Ledger.Empty_Ledger;
   begin
      Assert
        (HRA.Ledger.Add_Transaction (Book, Original, Status)
           and then HRA.Ledger.Add_Transaction (Book, Reversal, Status)
           and then HRA.Money.Is_Zero_Balance
             (HRA.Ledger.Compute_Account_Balance (Book, Cash))
           and then HRA.Money.Is_Zero_Balance
             (HRA.Ledger.Compute_Account_Balance (Book, Expense)),
         "original plus reversal cancels account balances exactly");
   end;

   Put_Line
     (Natural'Image (Passed_Count) & " passed, " &
      Natural'Image (Failed_Count) & " failed");
   if Failed_Count > 0 then
      raise Program_Error with "Reversal tests failed";
   end if;
end Test_Reversal;
