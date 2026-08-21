with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA.Dates;
with HRA.Ledger;
with HRA.Plan;
with HRA.Journal_Evidence;
with HRA.Plan_Temporal_Observation;

--  Legacy source-admission convenience surface. Production Household consumers
--  use HRA.Plan_Admission + HRA.Plan_Completion + HRA.Plan_Temporal_Observation.
--  While focused tests are migrated, this package re-exports the temporal
--  projection types rather than owning duplicate Open/Completed Plan types.
package HRA.Plan_Observation is

   subtype Open_Plan is HRA.Plan_Temporal_Observation.Open_Plan;
   package Open_Plan_Vectors renames
     HRA.Plan_Temporal_Observation.Open_Plan_Vectors;

   subtype Completed_Plan is HRA.Plan_Temporal_Observation.Completed_Plan;
   package Completed_Plan_Vectors renames
     HRA.Plan_Temporal_Observation.Completed_Plan_Vectors;

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
