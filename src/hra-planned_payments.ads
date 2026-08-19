with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Containers.Indefinite_Vectors;
with HRA.Dates;
with HRA.Money;
with HRA.Account;
with HRA.Ledger;
with HRA.Plan;
with HRA.Plan_Observation;

package HRA.Planned_Payments is

   type Temporal_Status is (Overdue, Due_Today, Upcoming);

   type Planned_Payment is record
      ID          : HRA.Plan.Plan_Id;
      Due_Date    : HRA.Dates.Date;
      Memo        : Unbounded_String;
      Amt         : HRA.Money.Amount;
      Source      : HRA.Account.Account;
      Destination : HRA.Account.Account;
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

   function Project
     (Open_Plans : HRA.Plan_Observation.Open_Plan_Vectors.Vector;
      Registry   : HRA.Account.Account_Registry;
      As_Of_Date : HRA.Dates.Date;
      Result     : out Observation;
      Diag       : out Admission_Diagnostic) return Boolean;

   function Observe
     (Plan_Ledger        : HRA.Ledger.Ledger;
      Plan_Source_Text   : String;
      Actual_Ledger      : HRA.Ledger.Ledger;
      Actual_Source_Text : String;
      Registry           : HRA.Account.Account_Registry;
      As_Of_Date         : HRA.Dates.Date;
      Result             : out Observation;
      Diag               : out Admission_Diagnostic) return Boolean;

end HRA.Planned_Payments;
