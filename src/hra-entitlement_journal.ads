with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Containers.Indefinite_Vectors;
with HRA.Dates;
with HRA.Envelope;
with HRA.Envelope_Entitlement;

--  Dedicated admission owner for canonical entitlement.journal.
--  This source is not an accounting Journal and does not depend on Account
--  identity or Budget allocation coordinates.
package HRA.Entitlement_Journal is

   type Admission_Status is
     (Success,
      Syntax_Error,
      Invalid_Date,
      Invalid_Commodity,
      Invalid_Quantity,
      Non_Positive_Quantity,
      Same_Endpoint,
      Unknown_Envelope,
      Duplicate_Origin,
      Missing_Origin,
      Origin_After_Transfer,
      Negative_Envelope_Stock);

   type Admission_Diagnostic is record
      Status      : Admission_Status := Success;
      Line_Number : Natural := 0;
      Message     : Unbounded_String;
   end record;

   package Movement_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => HRA.Envelope_Entitlement.Entitlement_Movement,
      "="          => HRA.Envelope_Entitlement."=");

   type Entitlement_History is record
      Origins   : HRA.Envelope_Entitlement.Commodity_Date_Maps.Map;
      Movements : Movement_Vectors.Vector;
   end record;

   function Empty_History return Entitlement_History;

   function Admit
     (Text     : String;
      Registry : HRA.Envelope.Envelope_Registry;
      History  : out Entitlement_History;
      Diag     : out Admission_Diagnostic) return Boolean;

   --  Inclusive historical projection over already-admitted native facts.
   function Observe
     (History      : Entitlement_History;
      Through_Date : HRA.Dates.Date)
      return HRA.Envelope_Entitlement.Entitlement_Observation;

   function Movement_Count (History : Entitlement_History) return Natural;

end HRA.Entitlement_Journal;
