with Ada.Containers.Indefinite_Vectors;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA.Dates;
with HRA.Journal_Evidence;
with HRA.Ledger;
with HRA.Plan;

--  One admitted Plan Journal authority.
--
--  In this owner Tx.Date is the intention coordinate: the day toward which the
--  admitted commitment points. It is not a visibility gate and does not become
--  an Actual event merely because that day arrives.
--
--  Journal syntax owns transactions and parser-produced source coordinates.
--  This package adds Plan identity and lifecycle evidence exactly once, while
--  retaining the whole Transaction and its physical provenance together.
package HRA.Plan_Admission is

   --  These constructors describe source-admitted retirement evidence, not an
   --  as-of lifecycle state. A future Cancellation or Supersession remains
   --  visible evidence even when a temporal observer still sees the Plan open.
   type Retirement_Kind is (No_Retirement, Cancellation, Supersession);

   type Plan_Retirement (Kind : Retirement_Kind := No_Retirement) is record
      case Kind is
         when No_Retirement =>
            null;
         when Cancellation =>
            Canceled_On : HRA.Dates.Date;
         when Supersession =>
            Superseded_On : HRA.Dates.Date;
            Successor     : HRA.Plan.Plan_Id;
      end case;
   end record;

   type Plan_Transaction_Entry is record
      ID         : HRA.Plan.Plan_Id;
      Tx         : HRA.Ledger.Transaction;
      Source     : HRA.Journal_Evidence.Transaction_Source;
      Retirement : Plan_Retirement;
   end record;

   --  The admitted aggregate is opaque. Clients observe source-order entries or
   --  read projections, but cannot pair unrelated Ledger/provenance/lifecycle
   --  values and call the result an admitted Plan Journal.
   type Plan_Journal is private;

   function Empty_Journal return Plan_Journal;

   function Ledger_Of
     (Journal : Plan_Journal) return HRA.Ledger.Ledger;

   function Evidence_Of
     (Journal : Plan_Journal)
      return HRA.Journal_Evidence.Journal_Evidence;

   function Plan_Ids_Of
     (Journal : Plan_Journal) return HRA.Plan.Plan_Id_Universe;

   function Transaction_Count (Journal : Plan_Journal) return Natural;

   function Transaction_At
     (Journal : Plan_Journal;
      Index   : Positive) return Plan_Transaction_Entry
     with Pre => Index <= Transaction_Count (Journal);

   type Admission_Status is
     (Success,
      Source_Evidence_Error,
      Missing_Plan_Id,
      Duplicate_Plan_Metadata,
      Invalid_Plan_Id,
      Duplicate_Plan_Id,
      Invalid_Lifecycle_Metadata,
      Invalid_Lifecycle_Date,
      Invalid_Supersession_Target,
      Unknown_Supersession_Target,
      Supersession_Cycle);

   type Admission_Diagnostic is record
      Status      : Admission_Status := Success;
      Line_Number : Natural := 0;
      Plan_Id     : Unbounded_String;
      Message     : Unbounded_String;
   end record;

   function Admit
     (Plan_Ledger   : HRA.Ledger.Ledger;
      Plan_Evidence : HRA.Journal_Evidence.Journal_Evidence;
      Result        : out Plan_Journal;
      Diag          : out Admission_Diagnostic) return Boolean;

private

   package Plan_Transaction_Entry_Vectors is new
     Ada.Containers.Indefinite_Vectors
       (Index_Type   => Positive,
        Element_Type => Plan_Transaction_Entry);

   type Plan_Journal is record
      Value    : HRA.Ledger.Ledger;
      In_Order : Plan_Transaction_Entry_Vectors.Vector;
      Ids      : HRA.Plan.Plan_Id_Universe;
   end record;

   function Ledger_Of
     (Journal : Plan_Journal) return HRA.Ledger.Ledger is
     (Journal.Value);

   function Plan_Ids_Of
     (Journal : Plan_Journal) return HRA.Plan.Plan_Id_Universe is
     (Journal.Ids);

   function Transaction_Count (Journal : Plan_Journal) return Natural is
     (Natural (Journal.In_Order.Length));

   function Transaction_At
     (Journal : Plan_Journal;
      Index   : Positive) return Plan_Transaction_Entry is
     (Journal.In_Order.Element (Index));

end HRA.Plan_Admission;
