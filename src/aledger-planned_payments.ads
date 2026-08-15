with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Containers.Indefinite_Vectors;
with ALedger.Money;
with ALedger.Account;
with ALedger.Ledger;
with ALedger.Plan;

package ALedger.Planned_Payments is

   type Temporal_Status is (Overdue, Due_Today, Upcoming);

   type Planned_Payment is record
      ID          : ALedger.Plan.Plan_Id;
      Due_Date    : Unbounded_String;
      Memo        : Unbounded_String;
      Amt         : ALedger.Money.Amount;
      Source      : ALedger.Account.Account;
      Destination : ALedger.Account.Account;
      Timing      : Temporal_Status;
   end record;

   package Payment_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Planned_Payment);

   type Observation is record
      Payments : Payment_Vectors.Vector;
   end record;

   type Admission_Status is
     (Success,
      Plan_Source_Evidence_Error,
      Actual_Source_Evidence_Error,
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
      Multiple_Completion_Actuals,
      Undeclared_Plan_Account,
      Unsupported_Plan_Role_Flow,
      Plan_Report_Requires_Binary_Outgoing);

   type Admission_Diagnostic is record
      Status      : Admission_Status := Success;
      Line_Number : Natural := 0;
      Plan_Id     : Unbounded_String;
      Message     : Unbounded_String;
   end record;

   --  Observe open outgoing payment Plans as of one inclusive calendar day.
   --  Completion is explicit Actual `plan-id` evidence. Cancellation and
   --  supersession are historical Plan metadata. Date/memo/amount similarity
   --  is never used as lifecycle evidence.
   function Observe
     (Plan_Ledger        : ALedger.Ledger.Ledger;
      Plan_Source_Text   : String;
      Actual_Ledger      : ALedger.Ledger.Ledger;
      Actual_Source_Text : String;
      Registry           : ALedger.Account.Account_Registry;
      As_Of_Date         : String;
      Result             : out Observation;
      Diag               : out Admission_Diagnostic) return Boolean;

end ALedger.Planned_Payments;
