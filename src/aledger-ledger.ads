with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Containers.Indefinite_Vectors;
with ALedger.Money;          use ALedger.Money;
with ALedger.Account;        use ALedger.Account;

package ALedger.Ledger is

   --  ========================================================================
   --  Posting: Single Account Posting with Amount and Optional Memo
   --  ========================================================================
   type Posting is record
      Acc      : Account.Account;
      Amt      : Amount;
      Has_Memo : Boolean := False;
      Memo     : Unbounded_String;
   end record;

   function Make_Posting
     (Acc : Account.Account;
      Amt : Amount) return Posting;

   function Make_Posting_With_Memo
     (Acc  : Account.Account;
      Amt  : Amount;
      Memo : String) return Posting;

   package Posting_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Posting);

   --  ========================================================================
   --  Transaction: Multi-Posting Entry with Balance Validation
   --  ========================================================================
   type Transaction is record
      Date_Text     : Unbounded_String;  --  Format: YYYY-MM-DD
      Code_Or_Payee : Unbounded_String;
      Postings      : Posting_Vectors.Vector;
   end record;

   type Transaction_Error is
     (Success,
      Empty_Postings,
      Unbalanced_Transaction);

   function Create_Transaction
     (Date_Str : String;
      Payee    : String;
      Postings : Posting_Vectors.Vector;
      Tx       : out Transaction;
      Status   : out Transaction_Error) return Boolean;

   function Calculate_Balance (Tx : Transaction) return Balance;
   function Is_Balanced (Tx : Transaction) return Boolean;

   package Transaction_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Transaction);

   --  ========================================================================
   --  Ledger: Collection of Validated Transactions & Registry
   --  ========================================================================
   type Ledger is record
      Registry     : Account_Registry;
      Transactions : Transaction_Vectors.Vector;
   end record;

   function Empty_Ledger return Ledger;

   function Add_Transaction
     (L      : in out Ledger;
      Tx     : Transaction;
      Status : out Transaction_Error) return Boolean;

   function Compute_Account_Balance
     (L   : Ledger;
      Acc : Account.Account) return Balance;

   function Compute_Total_Balance (L : Ledger) return Balance;

end ALedger.Ledger;
