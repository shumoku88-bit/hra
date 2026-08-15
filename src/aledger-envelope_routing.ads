with ALedger.Envelope;
with ALedger.Account;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Containers.Indefinite_Vectors;

package ALedger.Envelope_Routing is

   --  ========================================================================
   --  Expense Routing
   --
   --  Maps Expense Accounts to Envelopes via explicit effective-dated routes.
   --  This replaces the legacy name-prefix matching (budget:X -> expenses:X)
   --  with a stable, historical routing table.
   --
   --  Key principles from h-kernel:
   --    - Missing routing is attention evidence (not silent fallback)
   --    - Historical routing is never reconstructed from current config
   --    - Current config changes do not rewrite old intent
   --
   --  Source: [[envelope-history.expense-routing]] in budget.toml
   --  ========================================================================

   --  ========================================================================
   --  Route Kind
   --  ========================================================================

   type Route_Kind is (Managed_By_Envelope, Not_Envelope_Managed);

   --  ========================================================================
   --  Expense Route
   --
   --  Discriminated record: Managed_By_Envelope carries a Target Envelope_Id.
   --  Not_Envelope_Managed carries no data.  The compiler prevents accessing
   --  Target on a Not_Envelope_Managed route.
   --  ========================================================================

   type Expense_Route (Kind : Route_Kind := Not_Envelope_Managed) is record
      case Kind is
         when Managed_By_Envelope =>
            Target : Envelope.Envelope_Id;
         when Not_Envelope_Managed =>
            null;
      end case;
   end record;

   function Managed_Route
     (Id : Envelope.Envelope_Id) return Expense_Route
     with Post => Managed_Route'Result.Kind = Managed_By_Envelope;

   function Not_Managed_Route return Expense_Route
     with Post => Not_Managed_Route'Result.Kind = Not_Envelope_Managed;

   --  ========================================================================
   --  Effective Date
   --  ========================================================================

   type Effective_Date_Kind is (Initial, From_Date);

   type Effective_Date (Kind : Effective_Date_Kind := Initial) is record
      case Kind is
         when Initial =>
            null;
         when From_Date =>
            Date : Unbounded_String;   -- "YYYY-MM-DD"
      end case;
   end record;

   function Initial_Effective_Date return Effective_Date
     with Post => Initial_Effective_Date'Result.Kind = Initial;

   function Dated_Effective (Date : String) return Effective_Date
     with Pre  => Date'Length > 0,
          Post => Dated_Effective'Result.Kind = From_Date;

   --  ========================================================================
   --  Routing Entry
   --  ========================================================================

   type Routing_Entry is record
      Effective : Effective_Date;
      Expense   : Account.Account;
      Route     : Expense_Route;
      Note      : Unbounded_String;
   end record;

   package Routing_Entry_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Positive, Element_Type => Routing_Entry);

   --  ========================================================================
   --  Routing History
   --
   --  Admitted once from canonical source.  Immutable after construction.
   --  Resolve returns the most recent applicable route for an Account on a
   --  given date.  Multiple entries for the same Account with different
   --  effective dates are allowed; the latest applicable one wins.
   --  ========================================================================

   type Routing_History is private;

   type History_Status is
     (Success,
      Empty_Expense_Account,
      Invalid_Expense_Account,
      Unknown_Envelope_In_Route,
      Duplicate_Routing_Entry);

   function Empty_History return Routing_History;

   function Admit
     (Entries  : Routing_Entry_Vectors.Vector;
      Registry : Envelope.Envelope_Registry;
      History  : out Routing_History;
      Status   : out History_Status) return Boolean;

   --  Resolve the route for Expense on the given Date.
   --
   --  Returns the entry with the latest effective date <= Date.
   --  "initial" entries are always applicable.
   --  If no entry applies, returns Not_Envelope_Managed.
   function Resolve
     (H       : Routing_History;
      Expense : Account.Account;
      Date    : String) return Expense_Route;

   --  True if any routing entry exists for this Account (regardless of date).
   function Has_Routing
     (H       : Routing_History;
      Expense : Account.Account) return Boolean;

   function Length (H : Routing_History) return Natural;

private

   type Routing_History is record
      Entries : Routing_Entry_Vectors.Vector;
   end record;

end ALedger.Envelope_Routing;
