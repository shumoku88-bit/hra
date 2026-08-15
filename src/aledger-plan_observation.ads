with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Containers.Indefinite_Vectors;
with ALedger.Ledger;
with ALedger.Plan;

package ALedger.Plan_Observation is

   type Open_Plan is record
      ID : ALedger.Plan.Plan_Id;
      Tx : ALedger.Ledger.Transaction;
   end record;

   package Open_Plan_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Open_Plan);

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
      Result           : out ALedger.Plan.Plan_Id_Vectors.Vector;
      Diag             : out Admission_Diagnostic) return Boolean;

   --  Observe whole admitted Plan transactions that remain open at one
   --  inclusive application day. Lifecycle meaning is explicit only:
   --  Plan cancellation/supersession metadata and Actual plan-id completion.
   --  Planned date, description, amount, and posting similarity never close a
   --  Plan. Output preserves source order and the complete accounting shape.
   function Observe_Open_Plans
     (Plan_Ledger        : ALedger.Ledger.Ledger;
      Plan_Source_Text   : String;
      Actual_Ledger      : ALedger.Ledger.Ledger;
      Actual_Source_Text : String;
      As_Of_Date         : String;
      Result             : out Open_Plan_Vectors.Vector;
      Diag               : out Admission_Diagnostic) return Boolean;

end ALedger.Plan_Observation;
