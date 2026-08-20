with Ada.Containers.Indefinite_Vectors;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA.Dates;
with HRA.Journal_Evidence;
with HRA.Ledger;
with HRA.Plan;

--  One admitted Plan Journal authority.
--
--  Journal syntax owns transactions and parser-produced source coordinates.
--  This package adds Plan identity and lifecycle meaning exactly once, while
--  retaining the whole Transaction and its physical provenance together.
package HRA.Plan_Admission is

   type Retirement_Kind is (Active, Canceled, Superseded);

   type Plan_Retirement (Kind : Retirement_Kind := Active) is record
      case Kind is
         when Active =>
            null;
         when Canceled =>
            Canceled_On : HRA.Dates.Date;
         when Superseded =>
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
   type Plan_Observation is private;

   function Empty_Observation return Plan_Observation;

   function Ledger_Of
     (Observation : Plan_Observation) return HRA.Ledger.Ledger;

   function Evidence_Of
     (Observation : Plan_Observation)
      return HRA.Journal_Evidence.Journal_Evidence;

   function Plan_Ids_Of
     (Observation : Plan_Observation) return HRA.Plan.Plan_Id_Universe;

   function Transaction_Count (Observation : Plan_Observation) return Natural;

   function Transaction_At
     (Observation : Plan_Observation;
      Index       : Positive) return Plan_Transaction_Entry
     with Pre => Index <= Transaction_Count (Observation);

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
      Result        : out Plan_Observation;
      Diag          : out Admission_Diagnostic) return Boolean;

private

   package Plan_Transaction_Entry_Vectors is new
     Ada.Containers.Indefinite_Vectors
       (Index_Type   => Positive,
        Element_Type => Plan_Transaction_Entry);

   type Plan_Observation is record
      Value    : HRA.Ledger.Ledger;
      In_Order : Plan_Transaction_Entry_Vectors.Vector;
      Ids      : HRA.Plan.Plan_Id_Universe;
   end record;

   function Ledger_Of
     (Observation : Plan_Observation) return HRA.Ledger.Ledger is
     (Observation.Value);

   function Plan_Ids_Of
     (Observation : Plan_Observation) return HRA.Plan.Plan_Id_Universe is
     (Observation.Ids);

   function Transaction_Count (Observation : Plan_Observation) return Natural is
     (Natural (Observation.In_Order.Length));

   function Transaction_At
     (Observation : Plan_Observation;
      Index       : Positive) return Plan_Transaction_Entry is
     (Observation.In_Order.Element (Index));

end HRA.Plan_Admission;
