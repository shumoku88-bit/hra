package body ALedger.Proof_Core
  with SPARK_Mode => On
is

   function Model_Sum_For
     (Postings  : Posting_Array;
      Commodity : Commodity_ID;
      Count     : Contributor_Count) return Long_Long_Integer
   is
   begin
      if Count = 0 then
         return 0;
      elsif Postings (Positive (Count)).Commodity = Commodity then
         return Model_Sum_For (Postings, Commodity, Count - 1) +
           Postings (Positive (Count)).Quantity;
      else
         return Model_Sum_For (Postings, Commodity, Count - 1);
      end if;
   end Model_Sum_For;

   function Sum_For
     (Postings  : Posting_Array;
      Commodity : Commodity_ID) return Long_Long_Integer
   is
      Sum : Long_Long_Integer := 0;
   begin
      for I in Postings'Range loop
         if Postings (I).Commodity = Commodity then
            Sum := Sum + Postings (I).Quantity;
         end if;
         pragma Loop_Invariant
           (Sum in
              -(Long_Long_Integer (I - Postings'First + 1) *
                 Max_Atomic_Quanta) ..
               Long_Long_Integer (I - Postings'First + 1) *
                 Max_Atomic_Quanta);
         pragma Loop_Invariant
           (Sum = Model_Sum_For
              (Postings, Commodity,
               Contributor_Count (I - Postings'First + 1)));
      end loop;
      return Sum;
   end Sum_For;

   function Is_Balanced (Postings : Posting_Array) return Boolean is
   begin
      return
        Postings'Length >= 2
        and then
          (for all I in Postings'Range =>
             Sum_For (Postings, Postings (I).Commodity) = 0);
   end Is_Balanced;

   function Is_Ordered_Inverse
     (Original  : Posting_Array;
      Reversal  : Posting_Array) return Boolean
   is
   begin
      return
        Original'Length = Reversal'Length
        and then Original'Length > 0
        and then
          (for all I in Original'Range =>
             Original (I).Account = Reversal (I).Account
             and then Original (I).Commodity = Reversal (I).Commodity
             and then Original (I).Quantity = -Reversal (I).Quantity);
   end Is_Ordered_Inverse;

   function Unreserved_Obligation
     (Input : Plan_Obligation_Input) return Atomic_Quanta
   is
   begin
      return Input.Amount - Input.Already_Excluded;
   end Unreserved_Obligation;

   function Evaluate_Envelope (Input : Envelope_Input) return Envelope_Result is
      Remaining : constant Derived_Quanta :=
        Input.Entitlement - Input.Consumption + Input.Refunds;
   begin
      return
        (Remaining          => Remaining,
         Post_Plan_Headroom => Remaining - Input.Plan_Reserve);
   end Evaluate_Envelope;

   function Positive_Part (Value : Derived_Quanta) return Derived_Quanta is
   begin
      return (if Value > 0 then Value else 0);
   end Positive_Part;

   function Model_Signed_Total
     (Lines : Envelope_Result_Array;
      Count : Contributor_Count) return Long_Long_Integer
   is
   begin
      if Count = 0 then
         return 0;
      else
         return Model_Signed_Total (Lines, Count - 1) +
           Lines (Positive (Count)).Remaining;
      end if;
   end Model_Signed_Total;

   function Model_Backing_Required
     (Lines : Envelope_Result_Array;
      Count : Contributor_Count) return Long_Long_Integer
   is
   begin
      if Count = 0 then
         return 0;
      else
         return Model_Backing_Required (Lines, Count - 1) +
           Positive_Part (Lines (Positive (Count)).Remaining);
      end if;
   end Model_Backing_Required;

   function Evaluate_Backing
     (Lines : Envelope_Result_Array;
      Input : Backing_Input) return Backing_Result
   is
      Signed_Total     : Long_Long_Integer := 0;
      Backing_Required : Long_Long_Integer := 0;
   begin
      for I in Lines'Range loop
         Signed_Total := Signed_Total + Lines (I).Remaining;
         Backing_Required :=
           Backing_Required + Positive_Part (Lines (I).Remaining);
         pragma Loop_Invariant
           (Signed_Total in
              -(Long_Long_Integer (I - Lines'First + 1) * 4 *
                 Max_Atomic_Quanta) ..
               Long_Long_Integer (I - Lines'First + 1) * 4 *
                 Max_Atomic_Quanta);
         pragma Loop_Invariant
           (Backing_Required in
              0 .. Long_Long_Integer (I - Lines'First + 1) * 4 *
                Max_Atomic_Quanta);
         pragma Loop_Invariant
           (Signed_Total = Model_Signed_Total
              (Lines, Contributor_Count (I - Lines'First + 1)));
         pragma Loop_Invariant
           (Backing_Required = Model_Backing_Required
              (Lines, Contributor_Count (I - Lines'First + 1)));
      end loop;

      declare
         Surplus : constant Long_Long_Integer :=
           Input.Funding_Balance - Backing_Required;
         Reconciliation : constant Long_Long_Integer :=
           Surplus - Input.Unassigned_Balance;
      begin
         return
           (Signed_Total         => Signed_Total,
            Backing_Required     => Backing_Required,
            Backing_Surplus      => Surplus,
            Reconciliation_Delta => Reconciliation,
            Is_Under_Backed      => Surplus < 0);
      end;
   end Evaluate_Backing;

end ALedger.Proof_Core;
