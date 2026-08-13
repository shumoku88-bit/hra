package body ALedger.Ledger is

   function Make_Posting
     (Acc : Account.Account;
      Amt : Amount) return Posting
   is
   begin
      return (Acc      => Acc,
              Amt      => Amt,
              Has_Memo => False,
              Memo     => Null_Unbounded_String);
   end Make_Posting;

   function Make_Posting_With_Memo
     (Acc  : Account.Account;
      Amt  : Amount;
      Memo : String) return Posting
   is
   begin
      return (Acc      => Acc,
              Amt      => Amt,
              Has_Memo => True,
              Memo     => To_Unbounded_String (Memo));
   end Make_Posting_With_Memo;

   function Calculate_Balance (Tx : Transaction) return Balance is
      B : Balance := Empty_Balance;
      Cursor : Posting_Vectors.Cursor := Tx.Postings.First;
   begin
      while Posting_Vectors.Has_Element (Cursor) loop
         declare
            P : constant Posting := Posting_Vectors.Element (Cursor);
         begin
            B := Add_Balance (B, Singleton_Balance (P.Amt));
         end;
         Posting_Vectors.Next (Cursor);
      end loop;
      return B;
   end Calculate_Balance;

   function Is_Balanced (Tx : Transaction) return Boolean is
   begin
      return Is_Zero_Balance (Calculate_Balance (Tx));
   end Is_Balanced;

   function Create_Transaction
     (Date_Str : String;
      Payee    : String;
      Postings : Posting_Vectors.Vector;
      Tx       : out Transaction;
      Status   : out Transaction_Error) return Boolean
   is
      Candidate : Transaction;
   begin
      if Postings.Is_Empty then
         Status := Empty_Postings;
         return False;
      end if;

      Candidate := (Date_Text     => To_Unbounded_String (Date_Str),
                    Code_Or_Payee => To_Unbounded_String (Payee),
                    Postings      => Postings);

      if not Is_Balanced (Candidate) then
         Status := Unbalanced_Transaction;
         return False;
      end if;

      Tx := Candidate;
      Status := Success;
      return True;
   end Create_Transaction;

   function Empty_Ledger return Ledger is
      L : Ledger;
   begin
      L.Registry := Empty_Registry;
      return L;
   end Empty_Ledger;

   function Add_Transaction
     (L      : in out Ledger;
      Tx     : Transaction;
      Status : out Transaction_Error) return Boolean
   is
   begin
      if not Is_Balanced (Tx) then
         Status := Unbalanced_Transaction;
         return False;
      end if;

      L.Transactions.Append (Tx);
      Status := Success;
      return True;
   end Add_Transaction;

   function Compute_Account_Balance
     (L   : Ledger;
      Acc : Account.Account) return Balance
   is
      Total : Balance := Empty_Balance;
      Tx_Cursor : Transaction_Vectors.Cursor := L.Transactions.First;
   begin
      while Transaction_Vectors.Has_Element (Tx_Cursor) loop
         declare
            Tx : constant Transaction := Transaction_Vectors.Element (Tx_Cursor);
            P_Cursor : Posting_Vectors.Cursor := Tx.Postings.First;
         begin
            while Posting_Vectors.Has_Element (P_Cursor) loop
               declare
                  P : constant Posting := Posting_Vectors.Element (P_Cursor);
               begin
                  if P.Acc = Acc then
                     Total := Add_Balance (Total, Singleton_Balance (P.Amt));
                  end if;
               end;
               Posting_Vectors.Next (P_Cursor);
            end loop;
         end;
         Transaction_Vectors.Next (Tx_Cursor);
      end loop;
      return Total;
   end Compute_Account_Balance;

   function Compute_Total_Balance (L : Ledger) return Balance is
      Total : Balance := Empty_Balance;
      Tx_Cursor : Transaction_Vectors.Cursor := L.Transactions.First;
   begin
      while Transaction_Vectors.Has_Element (Tx_Cursor) loop
         Total := Add_Balance (Total, Calculate_Balance (Transaction_Vectors.Element (Tx_Cursor)));
         Transaction_Vectors.Next (Tx_Cursor);
      end loop;
      return Total;
   end Compute_Total_Balance;

end ALedger.Ledger;
