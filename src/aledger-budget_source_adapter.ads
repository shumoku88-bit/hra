with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Containers.Indefinite_Vectors;
with ALedger.Dates;
with ALedger.Ledger;
with ALedger.Household_Config;
with ALedger.Envelope;
with ALedger.Envelope_Entitlement;

package ALedger.Budget_Source_Adapter is

   --  ========================================================================
   --  Budget Source Adapter
   --
   --  Translates admitted budget.journal 2-posting transactions into pure
   --  Entitlement_Movements using only explicit Household coordinates:
   --  allocation Accounts, opening Accounts, and unassigned Accounts.
   --
   --  Laws:
   --    - Posting signs determine From/To; the admitted amount is positive.
   --    - Zero amounts generate no entitlement movement.
   --    - Envelope -> Envelope is Transfer_Between_Envelopes.
   --    - Envelope -> non-Envelope is Return_To_Unallocated.
   --    - non-Envelope -> Envelope is Grant_From_Unallocated.
   --    - Opening/Unassigned -> Opening/Unassigned changes no Envelope stock.
   --    - Unknown Budget coordinates fail closed.
   --  ========================================================================

   type Adapter_Status is
     (Success,
      Transaction_Not_Binary,
      Postings_Not_Opposites,
      Unrecognized_Budget_Account);

   type Adapter_Diagnostic is record
      Status            : Adapter_Status := Success;
      Transaction_Index : Natural := 0;
      Message           : Unbounded_String;
   end record;

   package Movement_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Envelope_Entitlement.Entitlement_Movement,
      "="          => Envelope_Entitlement."=");

   function Adapt_Budget_Journal
     (Transactions : Ledger.Transaction_Vectors.Vector;
      Config       : Household_Config.Household_Configuration;
      Registry     : Envelope.Envelope_Registry;
      Movements    : out Movement_Vectors.Vector;
      Diag         : out Adapter_Diagnostic) return Boolean;

   --  Complete admitted stock observation.
   function Observe_Entitlements
     (Transactions : Ledger.Transaction_Vectors.Vector;
      Config       : Household_Config.Household_Configuration;
      Registry     : Envelope.Envelope_Registry;
      Observation  : out Envelope_Entitlement.Entitlement_Observation;
      Diag         : out Adapter_Diagnostic) return Boolean;

   --  Inclusive historical observation. The complete in-memory Budget source is
   --  still validated fail-closed, but only source facts at or before Through_Date
   --  contribute an origin or Entitlement movement.
   function Observe_Entitlements
     (Transactions : Ledger.Transaction_Vectors.Vector;
      Config       : Household_Config.Household_Configuration;
      Registry     : Envelope.Envelope_Registry;
      Through_Date : ALedger.Dates.Date;
      Observation  : out Envelope_Entitlement.Entitlement_Observation;
      Diag         : out Adapter_Diagnostic) return Boolean;

end ALedger.Budget_Source_Adapter;
