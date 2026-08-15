with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Containers.Indefinite_Vectors;
with ALedger.Money;          use ALedger.Money;
with ALedger.Account;        use ALedger.Account;
with ALedger.Ledger;         use ALedger.Ledger;

package ALedger.Plan is

   --  ========================================================================
   --  Plan Id: Durable identity connecting planned commitments to actuals
   --  ========================================================================

   type Plan_Id is private;

   function "=" (Left, Right : Plan_Id) return Boolean;

   type Plan_Id_Universe is private;

   type Plan_Id_Status is
     (Success,
      Empty_Plan_Id,
      Plan_Id_Contains_Whitespace,
      Plan_Id_Contains_Control_Character);

   function Create_Plan_Id
     (Value  : String;
      PID    : out Plan_Id;
      Status : out Plan_Id_Status) return Boolean;

   function Make_Plan_Id (Value : String) return Plan_Id;
   function Null_Plan_Id return Plan_Id;
   function Is_Null (PID : Plan_Id) return Boolean;
   function Text (PID : Plan_Id) return String;

   function Empty_Plan_Id_Universe return Plan_Id_Universe;

   procedure Include
     (Universe : in out Plan_Id_Universe;
      PID      : Plan_Id);

   function Contains
     (Universe : Plan_Id_Universe;
      PID      : Plan_Id) return Boolean;

   function Length (Universe : Plan_Id_Universe) return Natural;

   --  ========================================================================
   --  Plan Lifecycle Status & Retirement
   --  ========================================================================

   type Plan_Status is
     (Pending,
      Completed,
      Canceled,
      Superseded);

   type Plan_Entry is record
      ID         : Plan_Id;
      Date_Text  : Unbounded_String;
      Memo       : Unbounded_String;
      Amt        : Amount;
      From_Acc   : Account.Account;  --  Asset Account
      To_Acc     : Account.Account;  --  Expense or Liability Account
      Status     : Plan_Status := Pending;
      Successor  : Plan_Id;
   end record;

   function Create_Plan_Entry
     (ID_Str    : String;
      Date_Str  : String;
      Memo_Str  : String;
      Amt       : Amount;
      From_Acc  : Account.Account;
      To_Acc    : Account.Account;
      PE        : out Plan_Entry) return Boolean;

   function Complete_Plan
     (P              : in out Plan_Entry;
      Execution_Date : String;
      Tx             : out Transaction) return Boolean;

   procedure Cancel_Plan
     (P        : in out Plan_Entry;
      Date_Str : String);

   procedure Supersede_Plan
     (P            : in out Plan_Entry;
      Date_Str     : String;
      Successor_ID : Plan_Id);

private

   type Plan_Id is record
      ID_Text : Unbounded_String;
   end record;

   package Plan_Id_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Plan_Id,
      "="          => "=");

   type Plan_Id_Universe is record
      Items : Plan_Id_Vectors.Vector;
   end record;

end ALedger.Plan;
