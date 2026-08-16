with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Containers.Indefinite_Vectors;
with ALedger.Dates;
with ALedger.Plan;
with ALedger.Envelope;

package ALedger.Fulfillment_Routing is

   type Fulfillment_Route_Kind is
     (Fulfills_Envelope,
      Not_Fulfillment_Target);

   type Fulfillment_Route
     (Kind : Fulfillment_Route_Kind := Not_Fulfillment_Target)
   is record
      case Kind is
         when Fulfills_Envelope =>
            Target : ALedger.Envelope.Envelope_Id;
         when Not_Fulfillment_Target =>
            null;
      end case;
   end record;

   function Fulfills
     (Target : ALedger.Envelope.Envelope_Id) return Fulfillment_Route;

   function Not_Target return Fulfillment_Route;

   type Fulfillment_Routing_Decision is record
      Effective_From : ALedger.Dates.Date;
      Plan_ID        : ALedger.Plan.Plan_Id;
      Route          : Fulfillment_Route;
      Note           : Unbounded_String;
   end record;

   package Decision_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Fulfillment_Routing_Decision);

   type Fulfillment_Routing_History is private;

   type Admission_Status is
     (Success,
      Duplicate_Plan_Date_Coordinate,
      Unknown_Plan_Reference,
      Unknown_Envelope_Reference);

   function Empty_History return Fulfillment_Routing_History;

   function Admit
     (Decisions   : Decision_Vectors.Vector;
      Known_Plans : ALedger.Plan.Plan_Id_Universe;
      Registry    : ALedger.Envelope.Envelope_Registry;
      History     : out Fulfillment_Routing_History;
      Status      : out Admission_Status) return Boolean;

   function Resolve_Decision
     (History  : Fulfillment_Routing_History;
      Plan_ID  : ALedger.Plan.Plan_Id;
      Date     : ALedger.Dates.Date;
      Decision : out Fulfillment_Routing_Decision) return Boolean;

   function Has_Routing_At
     (History : Fulfillment_Routing_History;
      Plan_ID : ALedger.Plan.Plan_Id;
      Date    : ALedger.Dates.Date) return Boolean;

   function Resolve
     (History : Fulfillment_Routing_History;
      Plan_ID : ALedger.Plan.Plan_Id;
      Date    : ALedger.Dates.Date) return Fulfillment_Route;

   function Length (History : Fulfillment_Routing_History) return Natural;

private

   type Fulfillment_Routing_History is record
      Decisions : Decision_Vectors.Vector;
   end record;

end ALedger.Fulfillment_Routing;
