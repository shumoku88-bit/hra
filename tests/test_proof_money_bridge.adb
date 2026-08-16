with Ada.Text_IO; use Ada.Text_IO;
with ALedger.Money; use ALedger.Money;
with ALedger.Proof_Core; use ALedger.Proof_Core;
with ALedger.Proof_Money_Bridge; use ALedger.Proof_Money_Bridge;

procedure Test_Proof_Money_Bridge is
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

begin
   Put_Line ("--- Testing ALedger.Proof_Money_Bridge ---");

   --  ========================================================================
   --  Law A: Zero
   --  Money 0 -> quanta 0 -> Money 0
   --  ========================================================================
   declare
      Q_In   : constant Quantity := Zero_Quantity;
      Quanta : Atomic_Quanta := -1;
      Status : Bridge_Status;
      Q_Out  : Quantity := 99.0;
   begin
      Assert
        (To_Atomic_Quanta (Q_In, Quanta, Status)
           and then Status = Success
           and then Quanta = 0,
         "Law A: To_Atomic_Quanta converts Money zero to 0 quanta");

      Assert
        (To_Money_Quantity (0, Q_Out, Status)
           and then Status = Success
           and then Q_Out = Zero_Quantity,
         "Law A: To_Money_Quantity converts 0 quanta to Money zero");
   end;

   --  ========================================================================
   --  Law B: Minimum Quantum
   --  0.00000001 -> 1
   --  ========================================================================
   declare
      Q_Min_Pos : Quantity;
      Q_Min_Neg : Quantity;
      Quanta    : Atomic_Quanta := 0;
      Status    : Bridge_Status;
      Q_Out     : Quantity;
   begin
      Assert (Parse_Quantity ("0.00000001", Q_Min_Pos), "Parse min pos quantum");
      Assert (Parse_Quantity ("-0.00000001", Q_Min_Neg), "Parse min neg quantum");

      Assert
        (To_Atomic_Quanta (Q_Min_Pos, Quanta, Status)
           and then Status = Success
           and then Quanta = 1,
         "Law B: 0.00000001 converts to 1 quantum");

      Assert
        (To_Money_Quantity (1, Q_Out, Status)
           and then Status = Success
           and then Q_Out = Q_Min_Pos,
         "Law B: 1 quantum round-trips to 0.00000001");

      Assert
        (To_Atomic_Quanta (Q_Min_Neg, Quanta, Status)
           and then Status = Success
           and then Quanta = -1,
         "Law B: -0.00000001 converts to -1 quantum");

      Assert
        (To_Money_Quantity (-1, Q_Out, Status)
           and then Status = Success
           and then Q_Out = Q_Min_Neg,
         "Law B: -1 quantum round-trips to -0.00000001");
   end;

   --  ========================================================================
   --  Law C: Signed Exact Decimal
   --  -123.45678901 -> -12_345_678_901 quanta -> exact round-trip
   --  ========================================================================
   declare
      Q_Val  : Quantity;
      Quanta : Atomic_Quanta := 0;
      Status : Bridge_Status;
      Q_Out  : Quantity;
   begin
      Assert (Parse_Quantity ("-123.45678901", Q_Val), "Parse signed decimal");

      Assert
        (To_Atomic_Quanta (Q_Val, Quanta, Status)
           and then Status = Success
           and then Quanta = -12_345_678_901,
         "Law C: -123.45678901 converts to -12_345_678_901 quanta");

      Assert
        (To_Money_Quantity (-12_345_678_901, Q_Out, Status)
           and then Status = Success
           and then Q_Out = Q_Val,
         "Law C: -12_345_678_901 quanta round-trips to original Quantity");

      -- Positive signed decimal test
      Assert (Parse_Quantity ("123.45678901", Q_Val), "Parse positive decimal");
      Assert
        (To_Atomic_Quanta (Q_Val, Quanta, Status)
           and then Status = Success
           and then Quanta = 12_345_678_901,
         "Law C: 123.45678901 converts to 12_345_678_901 quanta");
      Assert
        (To_Money_Quantity (12_345_678_901, Q_Out, Status)
           and then Status = Success
           and then Q_Out = Q_Val,
         "Law C: 12_345_678_901 quanta round-trips to positive decimal");
   end;

   --  ========================================================================
   --  Law D: Atomic Upper/Lower Boundary
   --  Atomic_Quanta'First / 'Last -> Money.Quantity -> Atomic exact match
   --  ========================================================================
   declare
      Status     : Bridge_Status;
      Q_Last     : Quantity;
      Q_First    : Quantity;
      Quanta_Out : Atomic_Quanta;
   begin
      -- Atomic_Quanta'Last
      Assert
        (To_Money_Quantity (Atomic_Quanta'Last, Q_Last, Status)
           and then Status = Success,
         "Law D: Atomic_Quanta'Last converts to Money.Quantity");

      Assert
        (To_Atomic_Quanta (Q_Last, Quanta_Out, Status)
           and then Status = Success
           and then Quanta_Out = Atomic_Quanta'Last,
         "Law D: Atomic_Quanta'Last exact round-trip match");

      -- Atomic_Quanta'First
      Assert
        (To_Money_Quantity (Atomic_Quanta'First, Q_First, Status)
           and then Status = Success,
         "Law D: Atomic_Quanta'First converts to Money.Quantity");

      Assert
        (To_Atomic_Quanta (Q_First, Quanta_Out, Status)
           and then Status = Success
           and then Quanta_Out = Atomic_Quanta'First,
         "Law D: Atomic_Quanta'First exact round-trip match");
   end;

   --  ========================================================================
   --  Law E: Just Outside Atomic Range
   --  Atomic_Quanta'Last + 1 quanta equivalent is Money-legal but rejected as Out_Of_Proof_Input_Range
   --  ========================================================================
   declare
      Status     : Bridge_Status;
      Q_Last     : Quantity;
      Q_First    : Quantity;
      Q_Plus_One : Quantity;
      Q_Minus_One: Quantity;
      Quanta_Out : Atomic_Quanta := 0;
   begin
      Assert (To_Money_Quantity (Atomic_Quanta'Last, Q_Last, Status), "Setup Q_Last");
      Assert (To_Money_Quantity (Atomic_Quanta'First, Q_First, Status), "Setup Q_First");

      -- Q_Plus_One is Money-legal (Atomic_Quanta'Last + 0.00000001)
      Q_Plus_One := Q_Last + 0.00000001;
      Assert
        (not To_Atomic_Quanta (Q_Plus_One, Quanta_Out, Status)
           and then Status = Out_Of_Proof_Input_Range
           and then Quanta_Out = 0,
         "Law E: Atomic_Quanta'Last + 1 rejected as Out_Of_Proof_Input_Range");

      -- Q_Minus_One is Money-legal (Atomic_Quanta'First - 0.00000001)
      Q_Minus_One := Q_First - 0.00000001;
      Assert
        (not To_Atomic_Quanta (Q_Minus_One, Quanta_Out, Status)
           and then Status = Out_Of_Proof_Input_Range
           and then Quanta_Out = 0,
         "Law E: Atomic_Quanta'First - 1 rejected as Out_Of_Proof_Input_Range");

      -- Large Quantity within Money capacity but far outside Atomic range
      declare
         Q_Far : Quantity;
      begin
         Assert (Parse_Quantity ("100000000.00000000", Q_Far), "Parse 100M");
         Assert
           (not To_Atomic_Quanta (Q_Far, Quanta_Out, Status)
              and then Status = Out_Of_Proof_Input_Range,
            "Law E: 100,000,000.0 rejected as Out_Of_Proof_Input_Range");
      end;
   end;

   --  ========================================================================
   --  Law F: Wider Proof Result
   --  Values larger than Atomic range but fitting Money.Quantity succeed in To_Money_Quantity
   --  ========================================================================
   declare
      Derived_Max : constant Long_Long_Integer := Derived_Quanta'Last;
      Derived_Min : constant Long_Long_Integer := Derived_Quanta'First;
      Status      : Bridge_Status;
      Q_Derived   : Quantity;
   begin
      -- Derived_Quanta'Last = 4 * Max_Atomic_Quanta (~180 million Money units)
      Assert
        (To_Money_Quantity (Derived_Max, Q_Derived, Status)
           and then Status = Success,
         "Law F: Derived_Quanta'Last converts to Money.Quantity");

      -- Derived_Quanta'First = -4 * Max_Atomic_Quanta
      Assert
        (To_Money_Quantity (Derived_Min, Q_Derived, Status)
           and then Status = Success,
         "Law F: Derived_Quanta'First converts to Money.Quantity");

      -- Large aggregate within Money capacity (e.g. 50 * Max_Atomic_Quanta)
      declare
         Aggregate : constant Long_Long_Integer := 50 * Max_Atomic_Quanta;
         Q_Agg     : Quantity;
      begin
         Assert
           (To_Money_Quantity (Aggregate, Q_Agg, Status)
              and then Status = Success,
            "Law F: 50 * Max_Atomic_Quanta converts to Money.Quantity");
      end;
   end;

   --  ========================================================================
   --  Law G: Money Output Range Rejection
   --  Long_Long_Integer outside Money.Quantity range rejected with Out_Of_Money_Output_Range
   --  ========================================================================
   declare
      Status : Bridge_Status;
      Q_Out  : Quantity := 123.0;
   begin
      -- Long_Long_Integer'Last (~9.22 * 10^18 quanta > 10^18 capacity)
      Assert
        (not To_Money_Quantity (Long_Long_Integer'Last, Q_Out, Status)
           and then Status = Out_Of_Money_Output_Range
           and then Q_Out = Zero_Quantity,
         "Law G: Long_Long_Integer'Last rejected as Out_Of_Money_Output_Range");

      -- Long_Long_Integer'First
      Assert
        (not To_Money_Quantity (Long_Long_Integer'First, Q_Out, Status)
           and then Status = Out_Of_Money_Output_Range
           and then Q_Out = Zero_Quantity,
         "Law G: Long_Long_Integer'First rejected as Out_Of_Money_Output_Range");

      -- Exactly 10^18 (1 followed by 18 zeros = 19 digits)
      Assert
        (not To_Money_Quantity (1_000_000_000_000_000_000, Q_Out, Status)
           and then Status = Out_Of_Money_Output_Range
           and then Q_Out = Zero_Quantity,
         "Law G: 10^18 quanta rejected as Out_Of_Money_Output_Range");

      -- Exactly -10^18
      Assert
        (not To_Money_Quantity (-1_000_000_000_000_000_000, Q_Out, Status)
           and then Status = Out_Of_Money_Output_Range
           and then Q_Out = Zero_Quantity,
         "Law G: -10^18 quanta rejected as Out_Of_Money_Output_Range");
   end;

   --  ========================================================================
   --  Law H: Balance Coordinate
   --  JPY Balance -> exact JPY quanta; USD from same Balance -> 0
   --  ========================================================================
   declare
      JPY_Comm : constant Commodity := Make_Commodity ("JPY");
      USD_Comm : constant Commodity := Make_Commodity ("USD");
      BTC_Comm : constant Commodity := Make_Commodity ("BTC");
      Bal      : Balance := Empty_Balance;
      Quanta   : Atomic_Quanta := -1;
      Status   : Bridge_Status;
   begin
      Bal := Add_Balance
        (Singleton_Balance (Make_Amount (JPY_Comm, 1250.0)),
         Singleton_Balance (Make_Amount (USD_Comm, -50.25)));

      -- Extract JPY
      Assert
        (Balance_To_Atomic_Quanta (Bal, JPY_Comm, Quanta, Status)
           and then Status = Success
           and then Quanta = 125_000_000_000,
         "Law H: Balance_To_Atomic_Quanta extracts exact JPY coordinate");

      -- Extract USD
      Assert
        (Balance_To_Atomic_Quanta (Bal, USD_Comm, Quanta, Status)
           and then Status = Success
           and then Quanta = -5_025_000_000,
         "Law H: Balance_To_Atomic_Quanta extracts exact USD coordinate");

      -- Extract missing BTC
      Assert
        (Balance_To_Atomic_Quanta (Bal, BTC_Comm, Quanta, Status)
           and then Status = Success
           and then Quanta = 0,
         "Law H: Balance_To_Atomic_Quanta returns 0 for missing coordinate");
   end;

   --  ========================================================================
   --  Law I: Singleton Balance
   --  known Commodity + proof quanta -> singleton Balance -> Lookup_Balance exact
   --  ========================================================================
   declare
      JPY_Comm : constant Commodity := Make_Commodity ("JPY");
      USD_Comm : constant Commodity := Make_Commodity ("USD");
      Bal      : Balance;
      Status   : Bridge_Status;
   begin
      -- Standard non-zero singleton
      Assert
        (To_Singleton_Balance (JPY_Comm, 500_000_000_000, Bal, Status)
           and then Status = Success
           and then Lookup_Balance (Bal, JPY_Comm) = 5000.0
           and then Lookup_Balance (Bal, USD_Comm) = Zero_Quantity,
         "Law I: To_Singleton_Balance creates exact single-coordinate Balance");

      -- Zero singleton produces canonical empty balance
      Assert
        (To_Singleton_Balance (JPY_Comm, 0, Bal, Status)
           and then Status = Success
           and then Is_Zero_Balance (Bal)
           and then Lookup_Balance (Bal, JPY_Comm) = Zero_Quantity,
         "Law I: To_Singleton_Balance with 0 quanta produces canonical zero balance");

      -- Out of range rejection
      Assert
        (not To_Singleton_Balance (JPY_Comm, Long_Long_Integer'Last, Bal, Status)
           and then Status = Out_Of_Money_Output_Range,
         "Law I: To_Singleton_Balance rejects out-of-range proof output");
   end;

   --  ========================================================================
   --  Law J: Current Scale Characterization
   --  Money.Quantity'Small matches 10^-8 contract
   --  ========================================================================
   declare
      pragma Warnings (Off, "condition is always True");
      Small_Matches_Scale : constant Boolean :=
        (Quantity'Small = 0.00000001);
      Scale_Matches_Proof : constant Boolean :=
        (Decimal_Scale = 100_000_000);
      pragma Warnings (On, "condition is always True");
   begin
      Assert (Small_Matches_Scale, "Law J: Money.Quantity'Small is 10^-8");
      Assert (Scale_Matches_Proof, "Law J: Proof_Core.Decimal_Scale is 10^8");
   end;

   Put_Line
     (Natural'Image (Passed_Count) & " passed, " &
      Natural'Image (Failed_Count) & " failed");

   if Failed_Count > 0 then
      raise Program_Error with "proof money bridge tests failed";
   end if;
end Test_Proof_Money_Bridge;
