with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Containers.Indefinite_Vectors;
with HRA.Dates;
with HRA.Ledger;
with HRA.Plan;
with HRA.Journal_Evidence;

package HRA.Plan_Observation is

   type Open_Plan is record
      ID : HRA.Plan.Plan_Id;
      Tx : HRA.Ledger.Transaction;
   end record;

   package Open_Plan_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Open_Plan);

   --  One whole admitted Plan paired with the explicit Actual transaction that
   --  completes it. Source evidence stays attached to the physical Journal
   --  documents that owned the metadata.
   type Completed_Plan is record
      ID            : HRA.Plan.Plan_Id;
      Plan_Tx       : HRA.Ledger.Transaction;
      Actual_Tx     : HRA.Ledger.Transaction;
      Plan_Source   : HRA.Journal_Evidence.Transaction_Source;
      Actual_Source : HRA.Journal_Evidence.Transaction_Source;
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

   function Admit_Plan_Identities
     (Plan_Ledger   : HRA.Ledger.Ledger;
      Plan_Evidence : HRA.Journal_Evidence.Journal_Evidence;
      Result        : out HRA.Plan.Plan_Id_Universe;
      Diag          : out Admission_Diagnostic) return Boolean;

   function Admit_Plan_Identities
     (Plan_Ledger      : HRA.Ledger.Ledger;
      Plan_Source_Text : String;
      Result           : out HRA.Plan.Plan_Id_Universe;
      Diag             : out Admission_Diagnostic) return Boolean;

   --  Cross-source admission law for explicit Actual -> Plan completion
   --  evidence. This is independent of observation date and report projection.
   function Admit_Plan_Completions
     (Known_Plans     : HRA.Plan.Plan_Id_Universe;
      Actual_Ledger   : HRA.Ledger.Ledger;
      Actual_Evidence : HRA.Journal_Evidence.Journal_Evidence;
      Diag            : out Admission_Diagnostic) return Boolean;

   function Observe_Plans
     (Plan_Ledger       : HRA.Ledger.Ledger;
      Plan_Evidence     : HRA.Journal_Evidence.Journal_Evidence;
      Actual_Ledger     : HRA.Ledger.Ledger;
      Actual_Evidence   : HRA.Journal_Evidence.Journal_Evidence;
      As_Of_Date        : HRA.Dates.Date;
      Open_Result       : out Open_Plan_Vectors.Vector;
      Completed_Result  : out Completed_Plan_Vectors.Vector;
      Diag              : out Admission_Diagnostic) return Boolean;

   function Observe_Plans
     (Plan_Ledger        : HRA.Ledger.Ledger;
      Plan_Source_Text   : String;
      Actual_Ledger      : HRA.Ledger.Ledger;
      Actual_Source_Text : String;
      As_Of_Date         : HRA.Dates.Date;
      Open_Result        : out Open_Plan_Vectors.Vector;
      Completed_Result   : out Completed_Plan_Vectors.Vector;
      Diag               : out Admission_Diagnostic) return Boolean;

   function Observe_Open_Plans
     (Plan_Ledger      : HRA.Ledger.Ledger;
      Plan_Evidence    : HRA.Journal_Evidence.Journal_Evidence;
      Actual_Ledger    : HRA.Ledger.Ledger;
      Actual_Evidence  : HRA.Journal_Evidence.Journal_Evidence;
      As_Of_Date       : HRA.Dates.Date;
      Result           : out Open_Plan_Vectors.Vector;
      Diag             : out Admission_Diagnostic) return Boolean;

   function Observe_Open_Plans
     (Plan_Ledger        : HRA.Ledger.Ledger;
      Plan_Source_Text   : String;
      Actual_Ledger      : HRA.Ledger.Ledger;
      Actual_Source_Text : String;
      As_Of_Date         : HRA.Dates.Date;
      Result             : out Open_Plan_Vectors.Vector;
      Diag               : out Admission_Diagnostic) return Boolean;

end HRA.Plan_Observation;
