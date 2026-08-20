with Ada.Text_IO; use Ada.Text_IO;
with HRA.Money; use HRA.Money;

procedure Test_Money is
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

   JPY, USD : Commodity;
   C_Status : Commodity_Status;
   Q1, Q2   : Quantity;
   B1, B2   : Balance;

begin
   Put_Line ("--- Testing HRA.Money focused laws ---");

   Assert
     (Create_Commodity ("JPY", JPY, C_Status) and then C_Status = Success,
      "valid JPY Commodity is admitted");
   Assert
     (Create_Commodity ("USD", USD, C_Status) and then C_Status = Success,
      "valid USD Commodity is admitted");
   Assert
     (not Create_Commodity ("", JPY, C_Status)
        and then C_Status = Empty_Commodity_Code,
      "empty Commodity code is rejected");
   Assert
     (not Create_Commodity ("JP Y", JPY, C_Status)
        and then C_Status = Commodity_Contains_Whitespace,
      "Commodity whitespace is rejected");

   Assert (Parse_Quantity ("1000", Q1), "integer Quantity parses exactly");
   Assert (Parse_Quantity ("-500.50", Q2), "signed decimal Quantity parses exactly");
   Assert (Render_Quantity (Q1) = "1,000", "integer Quantity renders canonically");
   Assert (Render_Quantity (Q2) = "-500.5", "decimal Quantity renders canonically");

   B1 := Singleton_Balance (Make_Amount (JPY, Q1));
   B2 := Singleton_Balance (Make_Amount (JPY, Q2));

   declare
      Sum : constant Balance := Add_Balance (B1, B2);
      Items : constant Balance_Entry_Array := Entries (Sum);
   begin
      Assert
        (Items'Length = 1 and then Items (1).Val = 499.5,
         "same-Commodity Balance addition remains exact");
   end;

   Assert
     (Is_Zero_Balance (Add_Balance (B1, Negate_Balance (B1))),
      "Balance negation cancels to canonical zero");
   Assert
     (Lookup_Balance (B1, USD) = Zero_Quantity,
      "missing Commodity coordinate is canonical zero");

   Put_Line
     (Natural'Image (Passed_Count) & " passed, " &
      Natural'Image (Failed_Count) & " failed");
   if Failed_Count > 0 then
      raise Program_Error with "Money tests failed";
   end if;
end Test_Money;
