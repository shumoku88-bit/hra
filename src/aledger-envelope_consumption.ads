with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Containers.Indefinite_Ordered_Maps;
with ALedger.Money;          use ALedger.Money;
with ALedger.Account;        use ALedger.Account;
with ALedger.Envelope;        use ALedger.Envelope;
with ALedger.Envelope_Routing; use ALedger.Envelope_Routing;
with ALedger.Ledger;

package ALedger.Envelope_Consumption is

   --  ========================================================================
   --  Consumption Amounts
   --
   --  Gross charges and refunds for one consumption coordinate.
   --  Refunds are stored as positive magnitudes; net is Charges - Refunds.
   --  ========================================================================

   type Consumption_Amounts is record
      Charges : Balance;
      Refunds : Balance;
   end record;

   function Empty_Amounts return Consumption_Amounts
     with Post => Is_Zero_Balance (Empty_Amounts'Result.Charges)
       and then Is_Zero_Balance (Empty_Amounts'Result.Refunds);

   function Make_Amounts (Charges, Refunds : Balance) return Consumption_Amounts;

   function Add_Amounts (Left, Right : Consumption_Amounts) return Consumption_Amounts;

   function Net_Consumption (Amounts : Consumption_Amounts) return Balance;

   function "=" (Left, Right : Consumption_Amounts) return Boolean;

   --  ========================================================================
   --  Envelope Consumption Observation
   --
   --  Tracks managed envelope consumption, unmanaged account consumption,
   --  and unrouted account consumption (attention evidence).
   --  ========================================================================

   package Envelope_Amounts_Maps is new Ada.Containers.Indefinite_Ordered_Maps
     (Key_Type     => String,
      Element_Type => Consumption_Amounts);

   package Account_Amounts_Maps is new Ada.Containers.Indefinite_Ordered_Maps
     (Key_Type     => String,
      Element_Type => Consumption_Amounts);

   type Envelope_Consumption is record
      Observed_Through : Unbounded_String;
      Managed          : Envelope_Amounts_Maps.Map;
      Unmanaged        : Account_Amounts_Maps.Map;
      Unrouted         : Account_Amounts_Maps.Map;
   end record;

   function Empty_Consumption return Envelope_Consumption;

   --  ========================================================================
   --  Observation calculation
   --  ========================================================================

   --  Observe consumption across all transactions in Ledger using the given
   --  Routing_History and Account_Registry (for Expense classification).
   --  If Through_Date is non-empty, only transactions on or before Through_Date
   --  are considered.
   function Observe_Consumption
     (L            : Ledger.Ledger;
      Routing      : Envelope_Routing.Routing_History;
      Through_Date : String := "") return Envelope_Consumption;

   --  Query consumption for a specific Envelope
   function Consumption_For
     (Obs : Envelope_Consumption;
      Env : Envelope.Envelope_Id) return Consumption_Amounts;

   --  Query net consumption balance for a specific Envelope
   function Net_For
     (Obs : Envelope_Consumption;
      Env : Envelope.Envelope_Id) return Balance;

   --  Check if there are any unrouted expense accounts (attention evidence)
   function Has_Unrouted (Obs : Envelope_Consumption) return Boolean;

   --  Iterate all managed envelope consumptions
   procedure For_Each_Managed
     (Obs     : Envelope_Consumption;
      Process : not null access procedure
        (Env_Id  : Envelope.Envelope_Id;
         Amounts : Consumption_Amounts));

   --  Iterate all unrouted account consumptions
   procedure For_Each_Unrouted
     (Obs     : Envelope_Consumption;
      Process : not null access procedure
        (Acc_Name : String;
         Amounts  : Consumption_Amounts));

end ALedger.Envelope_Consumption;
