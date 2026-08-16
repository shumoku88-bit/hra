with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Containers.Indefinite_Vectors;
with ALedger.Ledger;
with ALedger.Journal_Evidence;

package ALedger.Actual_Admission is

   type Actual_Id is private;

   type Actual_Id_Status is
     (Success,
      Empty_Actual_Id,
      Actual_Id_Contains_Whitespace,
      Actual_Id_Contains_Control_Character);

   function Create_Actual_Id
     (Value  : String;
      ID     : out Actual_Id;
      Status : out Actual_Id_Status) return Boolean;

   function Text (ID : Actual_Id) return String;
   function "=" (Left, Right : Actual_Id) return Boolean;

   --  Durable identity/provenance is intentionally opaque at the package
   --  boundary. Callers may consume the normalized Ledger and observation
   --  cardinalities without learning which container represents identities.
   type Actual_Observation is private;

   function Empty_Observation return Actual_Observation;

   function Ledger_Value
     (Observation : Actual_Observation) return ALedger.Ledger.Ledger;

   function Identified_Count (Observation : Actual_Observation) return Natural;
   function Reversal_Count (Observation : Actual_Observation) return Natural;

   type Admission_Status is
     (Success,
      Source_Evidence_Error,
      Duplicate_Metadata,
      Invalid_Event_Id,
      Invalid_Plan_Id,
      Invalid_Reverses_Id,
      Duplicate_Actual_Id,
      Reversal_Missing_Event_Id,
      Reversal_Self_Reference,
      Unknown_Reversal_Target,
      Duplicate_Reversal_Target,
      Reversal_Posting_Mismatch,
      Reversal_Cycle);

   type Admission_Diagnostic is record
      Status      : Admission_Status := Success;
      Line_Number : Natural := 0;
      Actual_Id   : Unbounded_String;
      Message     : Unbounded_String;
   end record;

   function Admit
     (Actual_Ledger   : ALedger.Ledger.Ledger;
      Actual_Evidence : ALedger.Journal_Evidence.Journal_Evidence;
      Result          : out Actual_Observation;
      Diag            : out Admission_Diagnostic) return Boolean;

private

   type Actual_Id is record
      ID_Text : Unbounded_String;
   end record;

   type Identified_Actual is record
      ID     : Actual_Id;
      Tx     : ALedger.Ledger.Transaction;
      Source : ALedger.Journal_Evidence.Transaction_Source;
   end record;

   package Identified_Actual_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Identified_Actual);

   type Reversal_Declaration is record
      Reversal_ID : Actual_Id;
      Target_ID   : Actual_Id;
   end record;

   package Reversal_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Reversal_Declaration);

   type Actual_Observation is record
      Value      : ALedger.Ledger.Ledger;
      Identified : Identified_Actual_Vectors.Vector;
      Reversals  : Reversal_Vectors.Vector;
   end record;

   function Ledger_Value
     (Observation : Actual_Observation) return ALedger.Ledger.Ledger is
       (Observation.Value);

   function Identified_Count (Observation : Actual_Observation) return Natural is
     (Natural (Observation.Identified.Length));

   function Reversal_Count (Observation : Actual_Observation) return Natural is
     (Natural (Observation.Reversals.Length));

end ALedger.Actual_Admission;
