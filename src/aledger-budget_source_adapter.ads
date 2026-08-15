with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Containers.Indefinite_Vectors;
with ALedger.Ledger;
with ALedger.Household_Config;
with ALedger.Envelope;
with ALedger.Envelope_Entitlement;

package ALedger.Budget_Source_Adapter is

   --  ========================================================================
   --  Budget Source Adapter
   --
   --  Translates raw budget.journal 2-posting transactions into pure
   --  Entitlement_Movements based on Household configuration and Envelope
   --  registry.
   --
   --  Key laws from h-kernel:
   --    - Posting 1 is From, Posting 2 is To.
   --    - If Amount is negative, From and To are swapped and Amount is negated.
   --    - Zero amounts generate no movement (ignored).
   --    - Execution (spent) movements do not alter Entitlement (ignored).
   --    - Envelope -> Envelope is Transfer_Between_Envelopes.
   --    - Envelope -> Other (Unallocated/Opening) is Return_To_Unallocated.
   --    - Other (Unallocated/Opening) -> Envelope is Grant_From_Unallocated.
   --    - Other -> Other (e.g. Opening -> Unallocated) generates no movement.
   --  ========================================================================

   type Adapter_Status is
     (Success,
      Transaction_Not_Binary,
      Postings_Not_Opposites,
      Unrecognized_Budget_Account,
      Unknown_Envelope_Identity);

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

   function Observe_Entitlements
     (Transactions : Ledger.Transaction_Vectors.Vector;
      Config       : Household_Config.Household_Configuration;
      Registry     : Envelope.Envelope_Registry;
      Observation  : out Envelope_Entitlement.Entitlement_Observation;
      Diag         : out Adapter_Diagnostic) return Boolean;

end ALedger.Budget_Source_Adapter;
