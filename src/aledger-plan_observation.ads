with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Containers.Indefinite_Vectors;
with ALedger.Ledger;
with ALedger.Plan;
with ALedger.Journal_Evidence;

package ALedger.Plan_Observation is

   type Open_Plan is record
      ID : ALedger.Plan.Plan_Id;
      Tx : ALedger.Ledger.Transaction;
   end record;

   package Open_Plan_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Open_Plan);

   --  One whole admitted Plan paired with the explicit Actual transaction that
   --  completes it. Source evidence stays attached to the physical Journal
   --  documents that owned the metadata.
   type Completed_Plan is record
      ID            : ALedger.Plan.Plan_Id;
      Plan_Tx       : ALedger.Ledger.Transaction;
      Actual_Tx     : ALedger.Ledger.Transaction;
      Plan_Source   : ALedger.Journal_Evidence.Transaction_Source;
      Actual_Source : ALedger.Journal_Evidence.Transaction_Source;
   end record;

   package Completed_Plan_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Completed_Plan);

   type Admission_Status is
     (Success,
      Plan_Source_Evidence_Error,
      Actual_Source_Evidence_Error,
      Invalid_Observation_Date,
      Missing_Plan_Id,
      Duplicate_Plan_Metadata,
      Invalid_Plan_Id,
      Duplicate_Plan_Id,
      Invalid_Lifecycle_Metadata,
      Invalid_Lifecycle_Date,
      Invalid_Supersession_Target,
      Unknown_Supersession_Target,
      Supersession_Cycle,
      Invalid_Actual_Plan_Id,
      Unknown_Completion_Plan,
      Multiple_Completion_Actuals);

   type Admission_Diagnostic is record
      Status      : Admission_Status := Success;
      Line_Number : Natural := 0;
      Plan_Id     : Unbounded_String;
      Message     : Unbounded_String;
   end record;

   --  Core identity admission consumes already-admitted Journal evidence.
   --  Lifecycle state is not part of identity existence: completed, cancelled,
   --  and superseded Plans remain valid stable references.
   function Admit_Plan_Identities
     (Plan_Ledger   : ALedger.Ledger.Ledger;
      Plan_Evidence : ALedger.Journal_Evidence.Journal_Evidence;
      Result        : out ALedger.Plan.Plan_Id_Universe;
      Diag          : out Admission_Diagnostic) return Boolean;

   --  Compatibility wrapper for root-only callers. Production graph admission
   --  should pass Journal_Evidence directly and must not re-extract raw text.
   function Admit_Plan_Identities
     (Plan_Ledger      : ALedger.Ledger.Ledger;
      Plan_Source_Text : String;
      Result           : out ALedger.Plan.Plan_Id_Universe;
      Diag             : out Admission_Diagnostic) return Boolean;

   --  Core role-neutral lifecycle observation. Ledger and Evidence are one
   --  admitted pair for each source. Planned similarity never creates
   --  completion evidence; only explicit Actual plan-id metadata does.
   function Observe_Plans
     (Plan_Ledger       : ALedger.Ledger.Ledger;
      Plan_Evidence     : ALedger.Journal_Evidence.Journal_Evidence;
      Actual_Ledger     : ALedger.Ledger.Ledger;
      Actual_Evidence   : ALedger.Journal_Evidence.Journal_Evidence;
      As_Of_Date        : String;
      Open_Result       : out Open_Plan_Vectors.Vector;
      Completed_Result  : out Completed_Plan_Vectors.Vector;
      Diag              : out Admission_Diagnostic) return Boolean;

   --  Compatibility wrapper for root-only callers.
   function Observe_Plans
     (Plan_Ledger        : ALedger.Ledger.Ledger;
      Plan_Source_Text   : String;
      Actual_Ledger      : ALedger.Ledger.Ledger;
      Actual_Source_Text : String;
      As_Of_Date         : String;
      Open_Result        : out Open_Plan_Vectors.Vector;
      Completed_Result   : out Completed_Plan_Vectors.Vector;
      Diag               : out Admission_Diagnostic) return Boolean;

   --  Evidence-native projection for callers that only need open Plans.
   function Observe_Open_Plans
     (Plan_Ledger      : ALedger.Ledger.Ledger;
      Plan_Evidence    : ALedger.Journal_Evidence.Journal_Evidence;
      Actual_Ledger    : ALedger.Ledger.Ledger;
      Actual_Evidence  : ALedger.Journal_Evidence.Journal_Evidence;
      As_Of_Date       : String;
      Result           : out Open_Plan_Vectors.Vector;
      Diag             : out Admission_Diagnostic) return Boolean;

   --  Compatibility projection for root-only callers.
   function Observe_Open_Plans
     (Plan_Ledger        : ALedger.Ledger.Ledger;
      Plan_Source_Text   : String;
      Actual_Ledger      : ALedger.Ledger.Ledger;
      Actual_Source_Text : String;
      As_Of_Date         : String;
      Result             : out Open_Plan_Vectors.Vector;
      Diag               : out Admission_Diagnostic) return Boolean;

end ALedger.Plan_Observation;
