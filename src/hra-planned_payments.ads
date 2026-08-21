with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Containers.Indefinite_Vectors;
with HRA.Dates;
with HRA.Money;
with HRA.Account;
with HRA.Plan;
with HRA.Plan_Temporal_Observation;

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
      Undeclared_Plan_Account,
      Unsupported_Plan_Role_Flow,
      Plan_Report_Requires_Binary_Outgoing);

   type Admission_Diagnostic is record
      Status      : Admission_Status := Success;
      Line_Number : Natural := 0;
      Plan_Id     : Unbounded_String;
      Message     : Unbounded_String;
   end record;

   --  Report projection over an already-admitted temporal Plan observation.
   --  Source admission and cross-source relation resolution are deliberately
   --  excluded from this package.
   function Project
     (Open_Plans : HRA.Plan_Temporal_Observation.Open_Plan_Vectors.Vector;
      Registry   : HRA.Account.Account_Registry;
      As_Of_Date : HRA.Dates.Date;
      Result     : out Observation;
      Diag       : out Admission_Diagnostic) return Boolean;

end HRA.Planned_Payments;
