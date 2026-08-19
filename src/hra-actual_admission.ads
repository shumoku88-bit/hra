with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Containers.Indefinite_Vectors;
with HRA.Ledger;
with HRA.Journal_Evidence;

package HRA.Actual_Admission is

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

   --  Durable identity/provenance collections stay opaque. The normalized
   --  Ledger remains an explicit observation coordinate because downstream
   --  accounting projections consume it directly.
   type Identified_Actual_Collection is tagged private;
   type Reversal_Collection is tagged private;

   type Actual_Observation is record
      Value      : HRA.Ledger.Ledger;
      Identified : Identified_Actual_Collection;
      Reversals  : Reversal_Collection;
   end record;

   function Empty_Observation return Actual_Observation;

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
     (Actual_Ledger   : HRA.Ledger.Ledger;
      Actual_Evidence : HRA.Journal_Evidence.Journal_Evidence;
      Result          : out Actual_Observation;
      Diag            : out Admission_Diagnostic) return Boolean;

private

   type Actual_Id is record
      ID_Text : Unbounded_String;
   end record;

   type Identified_Actual is record
      ID     : Actual_Id;
      Tx     : HRA.Ledger.Transaction;
      Source : HRA.Journal_Evidence.Transaction_Source;
   end record;

   package Identified_Actual_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Identified_Actual);

   type Identified_Actual_Collection is
     new Identified_Actual_Vectors.Vector with null record;

   type Reversal_Declaration is record
      Reversal_ID : Actual_Id;
      Target_ID   : Actual_Id;
   end record;

   package Reversal_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Reversal_Declaration);

   type Reversal_Collection is new Reversal_Vectors.Vector with null record;

   function Identified_Count (Observation : Actual_Observation) return Natural is
     (Natural (Observation.Identified.Length));

   function Reversal_Count (Observation : Actual_Observation) return Natural is
     (Natural (Observation.Reversals.Length));

end HRA.Actual_Admission;
