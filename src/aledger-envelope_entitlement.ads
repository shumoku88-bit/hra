with Ada.Containers.Indefinite_Ordered_Maps;
with ALedger.Dates;
with ALedger.Money;          use ALedger.Money;
with ALedger.Envelope;       use ALedger.Envelope;

--  ========================================================================
--  ALedger.Envelope_Entitlement
--
--  Per-Envelope Entitlement Observation.
--
--  Source: budget.journal movements (2-posting transfers).
--  Native: an Envelope's Entitlement is the sum of all grants received
--          minus all transfers out minus all returns to Unallocated.
--
--  Stock origin is the earliest admitted budget.journal movement day for each
--  Commodity, including a zero movement that establishes a clean epoch.
--  ========================================================================

package ALedger.Envelope_Entitlement is

   use type ALedger.Dates.Date;

   type Entitlement_Kind is
     (Grant_From_Unallocated,
      Transfer_Between_Envelopes,
      Return_To_Unallocated);

   type Entitlement_Movement
     (Kind : Entitlement_Kind := Grant_From_Unallocated)
   is record
      Tx_Date : ALedger.Dates.Date;
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

   package Envelope_Balance_Maps is new Ada.Containers.Indefinite_Ordered_Maps
     (Key_Type     => String,
      Element_Type => Balance);

   package Commodity_Date_Maps is new Ada.Containers.Indefinite_Ordered_Maps
     (Key_Type     => String,
      Element_Type => ALedger.Dates.Date);

   type Entitlement_Observation is record
      Per_Envelope : Envelope_Balance_Maps.Map;
      Unallocated  : Balance;
      Origins      : Commodity_Date_Maps.Map;
   end record;

   function Empty_Observation return Entitlement_Observation
     with Post => Is_Zero_Balance (Empty_Observation'Result.Unallocated);

   function Fold_Movement
     (Obs      : Entitlement_Observation;
      Movement : Entitlement_Movement) return Entitlement_Observation;

   function Record_Origin
     (Obs      : Entitlement_Observation;
      Comm     : Commodity;
      Tx_Date  : ALedger.Dates.Date) return Entitlement_Observation;

   function Has_Origin
     (Obs  : Entitlement_Observation;
      Comm : Commodity) return Boolean;

   function Origin_For
     (Obs  : Entitlement_Observation;
      Comm : Commodity) return ALedger.Dates.Date
     with Pre => Has_Origin (Obs, Comm);

   function Entitlement_For
     (Obs : Entitlement_Observation;
      Env : Envelope.Envelope_Id) return Balance;

   function Unallocated_Balance
     (Obs : Entitlement_Observation) return Balance;

   procedure For_Each_Envelope
     (Obs     : Entitlement_Observation;
      Process : not null access procedure
        (Env_Id : Envelope.Envelope_Id;
         Bal    : Balance));

end ALedger.Envelope_Entitlement;
