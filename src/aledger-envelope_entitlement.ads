with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Containers.Indefinite_Ordered_Maps;
with ALedger.Money;          use ALedger.Money;
with ALedger.Envelope;        use ALedger.Envelope;

--  ========================================================================
--  ALedger.Envelope_Entitlement
--
--  Per-Envelope Entitlement Observation.
--
--  Source: budget.journal movements (2-posting transfers).
--  Native: an Envelope's Entitlement is the sum of all grants received
--          minus all transfers out minus all returns to Unallocated.
--
--  Unallocated is entitlement space, NOT an Envelope and NOT an Asset.
--  Whether real assets support that entitlement is a separate Backing
--  question (future step).
--
--  Owns:
--    - Entitlement_Movement: one grant/transfer/return
--    - Entitlement_Observation: per-Envelope balance + Unallocated balance
--    - Fold_Movement: pure fold operation
--
--  Pure: no I/O, no clock, no identity mutation.  Source adapter is
--  responsible for translating budget.journal into Entitlement_Movement.
--  ========================================================================

package ALedger.Envelope_Entitlement is

   --  ========================================================================
   --  Entitlement Movement Kind
   --  ========================================================================

   type Entitlement_Kind is
     (Grant_From_Unallocated,
      Transfer_Between_Envelopes,
      Return_To_Unallocated);

   --  ========================================================================
   --  Entitlement Movement
   --
   --  One grant/transfer/return recorded by the source adapter.
   --  All amounts carry their Commodity; Balance algebra is multi-Commodity.
   --  Field name is 'Amt' (not 'Amount') to avoid clash with ALedger.Money.Amount.
   --  ========================================================================

   type Entitlement_Movement
     (Kind : Entitlement_Kind := Grant_From_Unallocated)
   is record
      Tx_Date : Unbounded_String;
      Amt     : Amount;
      case Kind is
         when Grant_From_Unallocated =>
            Target : Envelope.Envelope_Id;
         when Transfer_Between_Envelopes =>
            From_Envelope : Envelope.Envelope_Id;
            To_Envelope   : Envelope.Envelope_Id;
         when Return_To_Unallocated =>
            Source : Envelope.Envelope_Id;
      end case;
   end record;

   function "=" (Left, Right : Entitlement_Movement) return Boolean;

   --  ========================================================================
   --  Entitlement Observation
   --
   --  Folded per-Envelope balance plus Unallocated balance.
   --  Immutable: Fold_Movement returns a new observation.
   --  ========================================================================

   package Envelope_Balance_Maps is new Ada.Containers.Indefinite_Ordered_Maps
     (Key_Type     => String,
      Element_Type => Balance);

   type Entitlement_Observation is record
      Per_Envelope : Envelope_Balance_Maps.Map;
      Unallocated  : Balance;
   end record;

   function Empty_Observation return Entitlement_Observation
     with Post => Is_Zero_Balance (Empty_Observation'Result.Unallocated);

   --  Fold one movement into an existing observation.
   function Fold_Movement
     (Obs      : Entitlement_Observation;
      Movement : Entitlement_Movement) return Entitlement_Observation;

   --  Query per-Envelope balance (multi-Commodity).
   function Entitlement_For
     (Obs : Entitlement_Observation;
      Env : Envelope.Envelope_Id) return Balance;

   --  Query Unallocated balance.
   function Unallocated_Balance
     (Obs : Entitlement_Observation) return Balance;

   --  Iterate all Envelopes that have non-zero entitlement.
   procedure For_Each_Envelope
     (Obs     : Entitlement_Observation;
      Process : not null access procedure
        (Env_Id : Envelope.Envelope_Id;
         Bal    : Balance));

end ALedger.Envelope_Entitlement;