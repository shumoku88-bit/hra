with ALedger.Envelope;
with ALedger.Account;
with ALedger.Dates;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Containers.Indefinite_Vectors;

package ALedger.Envelope_Routing is

   type Route_Kind is (Managed_By_Envelope, Not_Envelope_Managed);

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

   type Effective_Date_Kind is (Initial, From_Date);

   type Effective_Date (Kind : Effective_Date_Kind := Initial) is record
      case Kind is
         when Initial =>
            null;
         when From_Date =>
            Date : ALedger.Dates.Date;
      end case;
   end record;

   function Initial_Effective_Date return Effective_Date
     with Post => Initial_Effective_Date'Result.Kind = Initial;

   function Dated_Effective (Date : ALedger.Dates.Date) return Effective_Date
     with Post => Dated_Effective'Result.Kind = From_Date;

   type Routing_Entry is record
      Effective : Effective_Date;
      Expense   : Account.Account;
      Route     : Expense_Route;
      Note      : Unbounded_String;
   end record;

   package Routing_Entry_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Positive, Element_Type => Routing_Entry);

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

   function Resolve
     (H       : Routing_History;
      Expense : Account.Account;
      Date    : ALedger.Dates.Date) return Expense_Route;

   function Has_Routing_At
     (H       : Routing_History;
      Expense : Account.Account;
      Date    : ALedger.Dates.Date) return Boolean;

   function Has_Routing
     (H       : Routing_History;
      Expense : Account.Account) return Boolean;

   function Length (H : Routing_History) return Natural;

private

   type Routing_History is record
      Entries : Routing_Entry_Vectors.Vector;
   end record;

end ALedger.Envelope_Routing;
