with Ada.Text_IO;          use Ada.Text_IO;
with ALedger.Dates;
with ALedger.Money;          use ALedger.Money;
with ALedger.Envelope;
with ALedger.Envelope_Entitlement; use ALedger.Envelope_Entitlement;

--  Standalone smoke test for ALedger.Envelope_Entitlement.
--  Verifies: empty obs, Grant, Transfer, Return, Entitlement_For, fold accumulation.
--  Uses Character'Val byte literals to avoid the String/Wide_Wide_String issue
--  with non-Latin-1 source text.

procedure Test_Envelope_Entitlement_Standalone is

   Passed : Natural := 0;
   Failed : Natural := 0;

   procedure Check (Condition : Boolean; Name : String) is
   begin
      if Condition then
         Put_Line ("[PASS] " & Name);
         Passed := Passed + 1;
      else
         Put_Line ("[FAIL] " & Name);
         Failed := Failed + 1;
      end if;
   end Check;

   function D (S : String) return ALedger.Dates.Date is
      Val    : ALedger.Dates.Date;
      Status : ALedger.Dates.Date_Status;
   begin
      if not ALedger.Dates.Parse (S, Val, Status) then
         raise Program_Error with "Invalid date in test: " & S;
      end if;
      return Val;
   end D;

   --  UTF-8 byte literals for Japanese envelope names
   --  食費: E9 A3 9F E8 B2 BB
   --  一般生活: E4 B8 80 E8 88 AC E7 94 9F E6 B4 BB
   Food_UTF8 : constant String :=
     Character'Val (16#E9#) & Character'Val (16#A3#) & Character'Val (16#9F#) &
     Character'Val (16#E8#) & Character'Val (16#B2#) & Character'Val (16#BB#);
   Gen_UTF8 : constant String :=
     Character'Val (16#E4#) & Character'Val (16#B8#) & Character'Val (16#80#) &
     Character'Val (16#E8#) & Character'Val (16#88#) & Character'Val (16#AC#) &
     Character'Val (16#E7#) & Character'Val (16#94#) & Character'Val (16#9F#) &
     Character'Val (16#E6#) & Character'Val (16#B4#) & Character'Val (16#BB#);

   JPY     : constant Commodity := Make_Commodity ("JPY");
   USD     : constant Commodity := Make_Commodity ("USD");
   Food_Id : constant ALedger.Envelope.Envelope_Id :=
     ALedger.Envelope.Make_Envelope_Id (Food_UTF8);
   Gen_Id  : constant ALedger.Envelope.Envelope_Id :=
     ALedger.Envelope.Make_Envelope_Id (Gen_UTF8);
   Obs     : Entitlement_Observation := Empty_Observation;
begin
   Put_Line ("--- ALedger.Envelope_Entitlement smoke test ---");

   --  Empty observation has zero unallocated
   Check
     (Is_Zero_Balance (Unallocated_Balance (Obs)),
      "Empty observation has zero unallocated");

   --  Entitlement_For on empty observation returns zero
   Check
     (Is_Zero_Balance (Entitlement_For (Obs, Food_Id)),
      "Empty observation returns zero for Food");

   --  Grant 1000 JPY from unallocated to Food
   Obs := Fold_Movement
     (Obs,
      (Kind    => Grant_From_Unallocated,
       Tx_Date => D ("2026-06-07"),
       Amt     => Make_Amount (JPY, 1000.0),
       Target  => Food_Id));
   Check
     (Lookup_Balance (Entitlement_For (Obs, Food_Id), JPY) = 1000.0,
      "After grant 1000 JPY: Food = 1000");
   Check
     (Lookup_Balance (Unallocated_Balance (Obs), JPY) = -1000.0,
      "After grant: unallocated = -1000 (deficit)");

   --  Grant 500 USD to Food as well (multi-commodity)
   Obs := Fold_Movement
     (Obs,
      (Kind    => Grant_From_Unallocated,
       Tx_Date => D ("2026-06-07"),
       Amt     => Make_Amount (USD, 500.0),
       Target  => Food_Id));
   Check
     (Lookup_Balance (Entitlement_For (Obs, Food_Id), JPY) = 1000.0
        and then Lookup_Balance (Entitlement_For (Obs, Food_Id), USD) = 500.0,
      "Food has both JPY 1000 and USD 500");

   --  Transfer 300 JPY from Food to Gen
   Obs := Fold_Movement
     (Obs,
      (Kind          => Transfer_Between_Envelopes,
       Tx_Date       => D ("2026-06-08"),
       Amt           => Make_Amount (JPY, 300.0),
       From_Envelope => Food_Id,
       To_Envelope   => Gen_Id));
   Check
     (Lookup_Balance (Entitlement_For (Obs, Food_Id), JPY) = 700.0,
      "After transfer 300 JPY: Food = 700");
   Check
     (Lookup_Balance (Entitlement_For (Obs, Gen_Id), JPY) = 300.0,
      "After transfer: Gen = 300");

   --  Return 100 JPY from Food to unallocated
   Obs := Fold_Movement
     (Obs,
      (Kind    => Return_To_Unallocated,
       Tx_Date => D ("2026-06-09"),
       Amt     => Make_Amount (JPY, 100.0),
       Source  => Food_Id));
   Check
     (Lookup_Balance (Entitlement_For (Obs, Food_Id), JPY) = 600.0,
      "After return 100 JPY: Food = 600");
   Check
     (Lookup_Balance (Unallocated_Balance (Obs), JPY) = -900.0,
      "After return: unallocated = -900 (deficit)");

   Put_Line ("---");
   Put_Line ("Passed =" & Natural'Image (Passed) &
             ", Failed =" & Natural'Image (Failed));
   if Failed > 0 then
      Put_Line ("RESULT: FAIL");
   else
      Put_Line ("RESULT: SUCCESS");
   end if;
end Test_Envelope_Entitlement_Standalone;