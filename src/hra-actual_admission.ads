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

   type Actual_Id_Option (Present : Boolean := False) is record
      case Present is
         when True =>
            Value : Actual_Id;
         when False =>
            null;
      end case;
   end record;

   --  One root-source Actual fact. In this owner Tx.Date is the event
   --  coordinate: when the admitted household transaction happened. It is not
   --  an admission timestamp or a record of when HRA learned the fact.
   --  Transaction, optional durable identity, and parser-owned provenance stay
   --  aligned as one admitted value. Ordinary identity-free Actual remains a
   --  first-class entry.
   type Actual_Transaction_Entry is record
      Tx       : HRA.Ledger.Transaction;
      Identity : Actual_Id_Option;
      Source   : HRA.Journal_Evidence.Transaction_Source;
   end record;

   type Reversal_Relation is record
      Reversal_ID : Actual_Id;
      Target_ID   : Actual_Id;
   end record;

   --  The admitted aggregate stays opaque. Callers cannot manufacture an
   --  Actual observation by pairing an arbitrary Ledger with unrelated source
   --  evidence or identity text.
   type Actual_Observation is private;

   function Empty_Observation return Actual_Observation;

   function Ledger_Of
     (Observation : Actual_Observation) return HRA.Ledger.Ledger;

   --  Provenance is projected only from the source-aligned entries retained by
   --  the admitted observation. Callers never need a second source scan or an
   --  independently stored Journal_Evidence authority after admission.
   function Evidence_Of
     (Observation : Actual_Observation)
      return HRA.Journal_Evidence.Journal_Evidence;

   function Transaction_Count
     (Observation : Actual_Observation) return Natural;

   function Transaction_At
     (Observation : Actual_Observation;
      Index       : Positive) return Actual_Transaction_Entry
     with Pre => Index <= Transaction_Count (Observation);

   function Identified_Count (Observation : Actual_Observation) return Natural;
   function Reversal_Count (Observation : Actual_Observation) return Natural;

   function Reversal_At
     (Observation : Actual_Observation;
      Index       : Positive) return Reversal_Relation
     with Pre => Index <= Reversal_Count (Observation);

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

   package Actual_Transaction_Entry_Vectors is new
     Ada.Containers.Indefinite_Vectors
       (Index_Type   => Positive,
        Element_Type => Actual_Transaction_Entry);

   package Reversal_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Reversal_Relation);

   type Actual_Observation is record
      Value     : HRA.Ledger.Ledger;
      In_Order  : Actual_Transaction_Entry_Vectors.Vector;
      Reversals : Reversal_Vectors.Vector;
   end record;

   function Ledger_Of
     (Observation : Actual_Observation) return HRA.Ledger.Ledger is
     (Observation.Value);

   function Transaction_Count
     (Observation : Actual_Observation) return Natural is
     (Natural (Observation.In_Order.Length));

   function Transaction_At
     (Observation : Actual_Observation;
      Index       : Positive) return Actual_Transaction_Entry is
     (Observation.In_Order.Element (Index));

   function Reversal_Count (Observation : Actual_Observation) return Natural is
     (Natural (Observation.Reversals.Length));

   function Reversal_At
     (Observation : Actual_Observation;
      Index       : Positive) return Reversal_Relation is
     (Observation.Reversals.Element (Index));

end HRA.Actual_Admission;
