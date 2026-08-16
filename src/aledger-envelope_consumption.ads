with Ada.Containers.Indefinite_Ordered_Maps;
with ALedger.Money;            use ALedger.Money;
with ALedger.Dates;
with ALedger.Envelope;         use ALedger.Envelope;
with ALedger.Envelope_Routing; use ALedger.Envelope_Routing;
with ALedger.Envelope_Entitlement;
with ALedger.Ledger;

package ALedger.Envelope_Consumption is

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

   package Envelope_Amounts_Maps is new Ada.Containers.Indefinite_Ordered_Maps
     (Key_Type     => String,
      Element_Type => Consumption_Amounts);

   package Account_Amounts_Maps is new Ada.Containers.Indefinite_Ordered_Maps
     (Key_Type     => String,
      Element_Type => Consumption_Amounts);

   type Consumption_Scope_Kind is (All_Transactions, Through_Date);

   type Consumption_Scope
     (Kind : Consumption_Scope_Kind := All_Transactions)
   is record
      case Kind is
         when All_Transactions =>
            null;
         when Through_Date =>
            Through : ALedger.Dates.Date;
      end case;
   end record;

   type Envelope_Consumption is record
      Scope     : Consumption_Scope;
      Managed   : Envelope_Amounts_Maps.Map;
      Unmanaged : Account_Amounts_Maps.Map;
      Unrouted  : Account_Amounts_Maps.Map;
   end record;

   function Empty_Consumption return Envelope_Consumption;

   --  Activity observations. These preserve the historical API for bounded or
   --  all-time Expense observation and do not impose an Entitlement origin.
   function Observe_Consumption
     (L       : Ledger.Ledger;
      Routing : Envelope_Routing.Routing_History) return Envelope_Consumption;

   function Observe_Consumption
     (L            : Ledger.Ledger;
      Routing      : Envelope_Routing.Routing_History;
      Through_Date : ALedger.Dates.Date) return Envelope_Consumption;

   --  Stock observations used by Household Remaining/Backing. A Commodity is
   --  absent before its source-owned Entitlement origin. Reversals inherit the
   --  root Actual date for both routing and stock membership.
   function Observe_Stock_Consumption
     (L           : Ledger.Ledger;
      Routing     : Envelope_Routing.Routing_History;
      Entitlement : Envelope_Entitlement.Entitlement_Observation)
      return Envelope_Consumption;

   function Observe_Stock_Consumption
     (L            : Ledger.Ledger;
      Routing      : Envelope_Routing.Routing_History;
      Entitlement  : Envelope_Entitlement.Entitlement_Observation;
      Through_Date : ALedger.Dates.Date) return Envelope_Consumption;

   function Consumption_For
     (Obs : Envelope_Consumption;
      Env : Envelope.Envelope_Id) return Consumption_Amounts;

   function Net_For
     (Obs : Envelope_Consumption;
      Env : Envelope.Envelope_Id) return Balance;

   function Has_Unrouted (Obs : Envelope_Consumption) return Boolean;

   procedure For_Each_Managed
     (Obs     : Envelope_Consumption;
      Process : not null access procedure
        (Env_Id  : Envelope.Envelope_Id;
         Amounts : Consumption_Amounts));

   procedure For_Each_Unrouted
     (Obs     : Envelope_Consumption;
      Process : not null access procedure
        (Acc_Name : String;
         Amounts  : Consumption_Amounts));

end ALedger.Envelope_Consumption;
