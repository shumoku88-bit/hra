package HRA.Proof_Core
  with Pure, SPARK_Mode => On
is
   --  Proof-facing quantities are exact 10^-8 quanta. The deliberately
   --  bounded range leaves enough headroom to prove every fold and derived
   --  equation free of machine-integer overflow.
   Decimal_Scale : constant := 100_000_000;

   Max_Contributors : constant := 256;
   Max_Atomic_Quanta : constant Long_Long_Integer :=
     Long_Long_Integer'Last / (Max_Contributors * 8);

   subtype Atomic_Quanta is Long_Long_Integer range
     -Max_Atomic_Quanta .. Max_Atomic_Quanta;

   subtype Derived_Quanta is Long_Long_Integer range
     -4 * Max_Atomic_Quanta .. 4 * Max_Atomic_Quanta;

   subtype Contributor_Count is Natural range 0 .. Max_Contributors;
   subtype Commodity_ID is Positive range 1 .. 4_096;
   subtype Account_ID is Positive range 1 .. 65_535;

   type Posting_Fact is record
      Account   : Account_ID;
      Commodity : Commodity_ID;
      Quantity  : Atomic_Quanta;
   end record;

   type Posting_Array is array (Positive range <>) of Posting_Fact;

   function Model_Sum_For
     (Postings  : Posting_Array;
      Commodity : Commodity_ID;
      Count     : Contributor_Count) return Long_Long_Integer
     with Ghost,
          Pre => Postings'First = 1
            and then Postings'Length <= Max_Contributors
            and then Count <= Postings'Length,
          Post =>
            Model_Sum_For'Result in
              -(Long_Long_Integer (Count) * Max_Atomic_Quanta) ..
               Long_Long_Integer (Count) * Max_Atomic_Quanta
            and then Model_Sum_For'Result =
              (if Count = 0 then 0
               elsif Postings (Positive (Count)).Commodity = Commodity
               then Model_Sum_For (Postings, Commodity, Count - 1) +
                    Postings (Positive (Count)).Quantity
               else Model_Sum_For (Postings, Commodity, Count - 1)),
          Subprogram_Variant => (Decreases => Count);

   function Sum_For
     (Postings  : Posting_Array;
      Commodity : Commodity_ID) return Long_Long_Integer
     with Pre => Postings'First = 1
            and then Postings'Length <= Max_Contributors,
          Post => Sum_For'Result =
            Model_Sum_For
              (Postings, Commodity, Contributor_Count (Postings'Length));

   function Is_Balanced (Postings : Posting_Array) return Boolean
     with Pre => Postings'First = 1
            and then Postings'Length <= Max_Contributors,
          Post =>
            Is_Balanced'Result =
              (Postings'Length >= 2
               and then
                 (for all I in Postings'Range =>
                    Sum_For (Postings, Postings (I).Commodity) = 0));

   --  This is the narrow generated-reversal law: Posting order and identity
   --  are retained while every exact quantity is negated. Admission owns the
   --  durable reverses relation separately.
   function Is_Ordered_Inverse
     (Original  : Posting_Array;
      Reversal  : Posting_Array) return Boolean
     with Pre => Original'First = 1
       and then Reversal'First = 1
       and then Original'Length <= Max_Contributors
       and then Reversal'Length <= Max_Contributors,
          Post =>
            Is_Ordered_Inverse'Result =
              (Original'Length = Reversal'Length
               and then Original'Length > 0
               and then
                 (for all I in Original'Range =>
                    Original (I).Account = Reversal (I).Account
                    and then Original (I).Commodity = Reversal (I).Commodity
                    and then Original (I).Quantity = -Reversal (I).Quantity));

   --  Inputs are already admitted, stock-horizon observations for one
   --  Envelope/Commodity coordinate. Net consumption and net fulfillment are
   --  signed: reversals/refunds may make either negative. Open Plan commitment
   --  is a non-negative claim and affects Headroom, not Remaining.
   type Envelope_Input is record
      Entitlement     : Atomic_Quanta;
      Net_Consumption : Atomic_Quanta;
      Net_Fulfillment : Atomic_Quanta;
      Plan_Commitment : Atomic_Quanta;
   end record
     with Dynamic_Predicate => Envelope_Input.Plan_Commitment >= 0;

   type Envelope_Result is record
      Remaining          : Derived_Quanta;
      Post_Plan_Headroom : Derived_Quanta;
   end record;

   function Evaluate_Envelope (Input : Envelope_Input) return Envelope_Result
     with Post =>
       Evaluate_Envelope'Result.Remaining =
         Input.Entitlement
         - Input.Net_Consumption
         - Input.Net_Fulfillment
       and then Evaluate_Envelope'Result.Post_Plan_Headroom =
         Evaluate_Envelope'Result.Remaining - Input.Plan_Commitment;

   function Positive_Part (Value : Derived_Quanta) return Derived_Quanta
     with Post =>
       Positive_Part'Result >= 0
       and then (if Value > 0
                 then Positive_Part'Result = Value
                 else Positive_Part'Result = 0);

   type Envelope_Result_Array is
     array (Positive range <>) of Envelope_Result;

   function Model_Gross_Envelope_Required
     (Lines : Envelope_Result_Array;
      Count : Contributor_Count) return Long_Long_Integer
     with Ghost,
          Pre => Lines'First = 1
            and then Lines'Length <= Max_Contributors
            and then Count <= Lines'Length,
          Post =>
            Model_Gross_Envelope_Required'Result in
              0 .. Long_Long_Integer (Count) * 4 * Max_Atomic_Quanta
            and then Model_Gross_Envelope_Required'Result =
              (if Count = 0 then 0
               else Model_Gross_Envelope_Required (Lines, Count - 1) +
                    Positive_Part (Lines (Positive (Count)).Remaining)),
          Subprogram_Variant => (Decreases => Count);

   function Model_Available_Envelope_Required
     (Lines : Envelope_Result_Array;
      Count : Contributor_Count) return Long_Long_Integer
     with Ghost,
          Pre => Lines'First = 1
            and then Lines'Length <= Max_Contributors
            and then Count <= Lines'Length,
          Post =>
            Model_Available_Envelope_Required'Result in
              0 .. Long_Long_Integer (Count) * 4 * Max_Atomic_Quanta
            and then Model_Available_Envelope_Required'Result =
              (if Count = 0 then 0
               else Model_Available_Envelope_Required (Lines, Count - 1) +
                    Positive_Part
                      (Lines (Positive (Count)).Post_Plan_Headroom)),
          Subprogram_Variant => (Decreases => Count);

   type Backing_Input is record
      Funding_Balance    : Derived_Quanta;
      Funding_Commitment : Derived_Quanta;
   end record
     with Dynamic_Predicate => Backing_Input.Funding_Commitment >= 0;

   type Backing_Result is record
      Gross_Envelope_Required     : Long_Long_Integer;
      Available_Envelope_Required : Long_Long_Integer;
      Available_Funding           : Long_Long_Integer;
      Gross_Surplus               : Long_Long_Integer;
      Available_Surplus           : Long_Long_Integer;
      Is_Gross_Under_Backed       : Boolean;
      Is_Available_Under_Backed   : Boolean;
   end record;

   function Evaluate_Backing
     (Lines : Envelope_Result_Array;
      Input : Backing_Input) return Backing_Result
     with Pre => Lines'First = 1
            and then Lines'Length <= Max_Contributors,
          Post =>
            Evaluate_Backing'Result.Gross_Envelope_Required =
              Model_Gross_Envelope_Required
                (Lines, Contributor_Count (Lines'Length))
            and then Evaluate_Backing'Result.Available_Envelope_Required =
              Model_Available_Envelope_Required
                (Lines, Contributor_Count (Lines'Length))
            and then Evaluate_Backing'Result.Available_Funding =
              Input.Funding_Balance - Input.Funding_Commitment
            and then Evaluate_Backing'Result.Gross_Surplus =
              Input.Funding_Balance -
              Evaluate_Backing'Result.Gross_Envelope_Required
            and then Evaluate_Backing'Result.Available_Surplus =
              Evaluate_Backing'Result.Available_Funding -
              Evaluate_Backing'Result.Available_Envelope_Required
            and then Evaluate_Backing'Result.Is_Gross_Under_Backed =
              (Evaluate_Backing'Result.Gross_Surplus < 0)
            and then Evaluate_Backing'Result.Is_Available_Under_Backed =
              (Evaluate_Backing'Result.Available_Surplus < 0);

end HRA.Proof_Core;
