with ALedger.Money;
with ALedger.Proof_Core;

--  Narrow ordinary-Ada boundary between production Money values and the
--  bounded integer quanta consumed/returned by ALedger.Proof_Core.
--
--  This package owns representation conversion only. It does not classify
--  Household facts, assign durable Commodity identity, perform proof
--  calculations, or render/parse decimal text.
package ALedger.Proof_Money_Bridge is

   type Bridge_Status is
     (Success,
      Out_Of_Proof_Input_Range,
      Out_Of_Money_Output_Range,
      Non_Exact_Conversion);

   --  Admit one production Quantity as an Atomic_Quanta proof input.
   --  No rounding, truncation, or saturation is permitted. A production
   --  Quantity that is exact but outside the proof operational profile is an
   --  explicit admission failure at this boundary.
   function To_Atomic_Quanta
     (Value  : ALedger.Money.Quantity;
      Result : out ALedger.Proof_Core.Atomic_Quanta;
      Status : out Bridge_Status) return Boolean;

   --  Extract exactly one Commodity coordinate from a canonical Balance and
   --  admit it as Atomic_Quanta. Missing coordinates are the exact zero value
   --  already defined by Money.Lookup_Balance; this function adds no routing or
   --  Commodity identity semantics of its own.
   function Balance_To_Atomic_Quanta
     (Value     : ALedger.Money.Balance;
      Commodity : ALedger.Money.Commodity;
      Result    : out ALedger.Proof_Core.Atomic_Quanta;
      Status    : out Bridge_Status) return Boolean;

   --  Convert proof quanta back to production Quantity. This accepts the base
   --  integer type rather than only Atomic_Quanta because Envelope derived
   --  values and Backing aggregates are wider proof results. Values outside
   --  the production Money.Quantity range fail explicitly.
   function To_Money_Quantity
     (Value  : Long_Long_Integer;
      Result : out ALedger.Money.Quantity;
      Status : out Bridge_Status) return Boolean;

   --  Reattach an already-known Commodity coordinate to one proof result. This
   --  is deliberately a singleton Balance constructor, not a generic
   --  multi-Commodity aggregation framework.
   function To_Singleton_Balance
     (Commodity : ALedger.Money.Commodity;
      Value     : Long_Long_Integer;
      Result    : out ALedger.Money.Balance;
      Status    : out Bridge_Status) return Boolean;

end ALedger.Proof_Money_Bridge;
