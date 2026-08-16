with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Containers.Indefinite_Vectors;
with ALedger.Money;          use ALedger.Money;
with ALedger.Account;        use ALedger.Account;
with ALedger.Dates;

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
      Date          : ALedger.Dates.Date;
      Code_Or_Payee : Unbounded_String;
      Event_ID      : Unbounded_String;  --  Durable Identity
      Reverses_ID   : Unbounded_String;  --  Reversed Target Event ID (if reversal)
      Postings      : Posting_Vectors.Vector;
   end record;

   type Transaction_Error is
     (Success,
      Invalid_Date,
      Empty_Postings,
      Unbalanced_Transaction);

   function Create_Transaction
     (Date_Value : ALedger.Dates.Date;
      Payee      : String;
      Postings   : Posting_Vectors.Vector;
      Tx         : out Transaction;
      Status     : out Transaction_Error) return Boolean
     with Post => (if Create_Transaction'Result then Status = Success and then Is_Balanced (Tx));

   function Create_Reversal_Transaction
     (Target_Tx       : Transaction;
      Reversal_ID     : String;
      Reversal_Date   : ALedger.Dates.Date;
      Reversal_Reason : String;
      Rev_Tx          : out Transaction;
      Status          : out Transaction_Error) return Boolean
     with Post => (if Create_Reversal_Transaction'Result then Status = Success and then Is_Balanced (Rev_Tx));

   function Is_Reversal_Of (Candidate_Rev, Target_Tx : Transaction) return Boolean;

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
      Status : out Transaction_Error) return Boolean
     with Post => (if Add_Transaction'Result then Status = Success);

   function Compute_Account_Balance
     (L   : Ledger;
      Acc : Account.Account) return Balance;

   --  Inclusive as-of observation. Future-dated Transactions remain admitted
   --  Ledger facts but do not contribute to this projected Account balance.
   function Compute_Account_Balance_Through
     (L       : Ledger;
      Acc     : Account.Account;
      Through : ALedger.Dates.Date) return Balance;

   function Compute_Total_Balance (L : Ledger) return Balance;

end ALedger.Ledger;
