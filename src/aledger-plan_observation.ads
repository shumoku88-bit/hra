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
   --  completes it. Source evidence comes from the exact bytes already held by
   --  the canonical Household observation; no posting or amount is reparsed.
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

   --  Admit the stable PlanId universe from the already admitted Plan ledger
   --  and the exact source bytes that produced it. Lifecycle state is not part
   --  of identity existence: completed, cancelled, and superseded Plans remain
   --  valid stable references for historical relations.
   function Admit_Plan_Identities
     (Plan_Ledger      : ALedger.Ledger.Ledger;
      Plan_Source_Text : String;
      Result           : out ALedger.Plan.Plan_Id_Universe;
      Diag             : out Admission_Diagnostic) return Boolean;

   --  Observe role-neutral Plan lifecycle once and publish both open Plans and
   --  explicit completion pairs. Planned date, description, amount, Account
   --  similarity, and accounting role never create completion evidence.
   function Observe_Plans
     (Plan_Ledger        : ALedger.Ledger.Ledger;
      Plan_Source_Text   : String;
      Actual_Ledger      : ALedger.Ledger.Ledger;
      Actual_Source_Text : String;
      As_Of_Date         : String;
      Open_Result        : out Open_Plan_Vectors.Vector;
      Completed_Result   : out Completed_Plan_Vectors.Vector;
      Diag               : out Admission_Diagnostic) return Boolean;

   --  Compatibility projection for callers that only need open Plans. This is
   --  a view of Observe_Plans, not a second lifecycle parser.
   function Observe_Open_Plans
     (Plan_Ledger        : ALedger.Ledger.Ledger;
      Plan_Source_Text   : String;
      Actual_Ledger      : ALedger.Ledger.Ledger;
      Actual_Source_Text : String;
      As_Of_Date         : String;
      Result             : out Open_Plan_Vectors.Vector;
      Diag               : out Admission_Diagnostic) return Boolean;

end ALedger.Plan_Observation;
