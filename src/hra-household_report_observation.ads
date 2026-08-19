with Ada.Containers.Vectors;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA.Backing_Policy;
with HRA.Cycle_Observation;
with HRA.Dates;
with HRA.Envelope;
with HRA.Envelope_Commitment;
with HRA.Envelope_Consumption;
with HRA.Envelope_Entitlement;
with HRA.Envelope_Fulfillment;
with HRA.Envelope_Position;
with HRA.Household;
with HRA.Issues;
with HRA.Money; use HRA.Money;
with HRA.Plan_Observation;
with HRA.Planned_Payments;
with HRA.Recent_Journal;
with HRA.Report;
with HRA.Report_Plan;

--  Complete semantic observation for the current Household report book.
--  This package is the only owner that interprets a resolved report plan and
--  composes the current report portfolio. Renderers consume the values below;
--  they do not receive Household_State or execute Ledger queries.
package HRA.Household_Report_Observation is

   type Report_Section_Key is
     (Envelope_And_Backing_Section,
      Account_Balances_Section,
      Balance_Sheet_Section,
      Profit_And_Loss_Section,
      Recent_Journal_Section,
      Planned_Payments_Section,
      Open_Issues_Section);

   type Report_Section_Order is
     array (Positive range <>) of Report_Section_Key;

   subtype Current_Report_Section_Order is Report_Section_Order (1 .. 7);

   type Envelope_Report_Line is record
      Env_Id                 : HRA.Envelope.Envelope_Id;
      Entitlement            : Balance;
      Consumption_Charges    : Balance;
      Consumption_Refunds    : Balance;
      Net_Consumption        : Balance;
      Fulfillment_Applied    : Balance;
      Fulfillment_Reversed   : Balance;
      Net_Fulfillment        : Balance;
      Remaining              : Balance;
      Plan_Commitment        : Balance;
      Headroom               : Balance;
   end record;

   package Envelope_Report_Line_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Envelope_Report_Line);

   type Account_Consumption_Line is record
      Account_Name : Unbounded_String;
      Charges       : Balance;
      Refunds       : Balance;
      Net           : Balance;
   end record;

   package Account_Consumption_Line_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Account_Consumption_Line);

   type Account_Commitment_Line is record
      Account_Name : Unbounded_String;
      Commitment   : Balance;
   end record;

   package Account_Commitment_Line_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Account_Commitment_Line);

   type Backing_Report_Line is record
      Pool_Id                     : Unbounded_String;
      Funding_Balance             : Balance;
      Funding_Commitment          : Balance;
      Available_Funding           : Balance;
      Gross_Envelope_Required     : Balance;
      Available_Envelope_Required : Balance;
      Gross_Surplus               : Balance;
      Available_Surplus           : Balance;
   end record;

   package Backing_Report_Line_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Backing_Report_Line);

   type Backing_Condition is (Fully_Backed, Under_Backed);

   type Envelope_Report_Observation is record
      Observed_Through       : HRA.Dates.Date;
      Current_Cycle          : HRA.Cycle_Observation.Cycle_Window;
      Lines                  : Envelope_Report_Line_Vectors.Vector;
      Unmanaged_Consumption  : Account_Consumption_Line_Vectors.Vector;
      Unrouted_Consumption   : Account_Consumption_Line_Vectors.Vector;
      Unmanaged_Commitment   : Account_Commitment_Line_Vectors.Vector;
      Unrouted_Commitment    : Account_Commitment_Line_Vectors.Vector;
      Backing_Lines          : Backing_Report_Line_Vectors.Vector;
      Signed_Envelope_Total  : Balance;
      Unallocated            : Balance;
      Total_Funding_Assets   : Balance;
      Backing_Status         : Backing_Condition := Fully_Backed;
   end record;

   type Account_Balances_Report_Observation is record
      As_Of         : HRA.Dates.Date;
      Value         : HRA.Report.Trial_Balance;
      Display_Lines : HRA.Report.Line_Vectors.Vector;
      Is_Balanced   : Boolean := False;
   end record;

   type Balance_Sheet_Report_Observation is record
      As_Of                : HRA.Dates.Date;
      Value                : HRA.Report.Balance_Sheet;
      Equation_Is_Balanced : Boolean := False;
   end record;

   type Profit_And_Loss_Report_Observation is record
      Period : HRA.Dates.Closed_Period;
      Value  : HRA.Report.Profit_And_Loss;
   end record;

   type Issues_Report_Observation is record
      Open_Items     : HRA.Issues.Issue_Vectors.Vector;
      Total_Count    : Natural := 0;
      Resolved_Count : Natural := 0;
   end record;

   type Report_Observation is record
      Observed_Through   : HRA.Dates.Date;
      Section_Order      : Current_Report_Section_Order;
      Query_Plan         : HRA.Report_Plan.Resolved_Report_Plan;
      Envelope_Report    : Envelope_Report_Observation;
      Account_Balances   : Account_Balances_Report_Observation;
      Balance_Sheet      : Balance_Sheet_Report_Observation;
      Profit_And_Loss    : Profit_And_Loss_Report_Observation;
      Recent_Journal     : HRA.Recent_Journal.Observation;
      Planned_Payments   : HRA.Planned_Payments.Observation;
      Open_Issues        : Issues_Report_Observation;

      --  Retain the constituent typed observations for non-rendering
      --  application consumers. The ordered report projections above remain
      --  the sole input to the current renderers.
      Open_Plans         : HRA.Plan_Observation.Open_Plan_Vectors.Vector;
      Completed_Plans    : HRA.Plan_Observation.Completed_Plan_Vectors.Vector;
      Current_Cycle      : HRA.Cycle_Observation.Cycle_Window;
      Entitlement        : HRA.Envelope_Entitlement.Entitlement_Observation;
      Consumption        : HRA.Envelope_Consumption.Envelope_Consumption;
      Fulfillment        : HRA.Envelope_Fulfillment.Envelope_Fulfillment;
      Commitment         : HRA.Envelope_Commitment.Commitment_Observation;
      Envelope_Positions : HRA.Envelope_Position.Observation;
      Funding_Commitment : HRA.Backing_Policy.Funding_Commitment_Observation;
      Backing            : HRA.Backing_Policy.Backing_Observation;
   end record;

   function Observe
     (Observed_Through : HRA.Dates.Date;
      State            : HRA.Household.Household_State;
      Result           : out Report_Observation;
      Error_Msg        : out Unbounded_String) return Boolean;

end HRA.Household_Report_Observation;
