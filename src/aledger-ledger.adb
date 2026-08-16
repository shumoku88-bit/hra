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
     (Date_Value : ALedger.Dates.Date;
      Payee      : String;
      Postings   : Posting_Vectors.Vector;
      Tx         : out Transaction;
      Status     : out Transaction_Error) return Boolean
   is
      Candidate : Transaction;
   begin
      if Postings.Is_Empty then
         Status := Empty_Postings;
         return False;
      end if;

      Candidate := (Date          => Date_Value,
                    Code_Or_Payee => To_Unbounded_String (Payee),
                    Event_ID      => Null_Unbounded_String,
                    Reverses_ID   => Null_Unbounded_String,
                    Postings      => Postings);

      if not Is_Balanced (Candidate) then
         Status := Unbalanced_Transaction;
         return False;
      end if;

      Tx := Candidate;
      Status := Success;
      return True;
   end Create_Transaction;

   function Create_Transaction
     (Date_Str : String;
      Payee    : String;
      Postings : Posting_Vectors.Vector;
      Tx       : out Transaction;
      Status   : out Transaction_Error) return Boolean
   is
      Date_Value  : ALedger.Dates.Date;
      Date_Status : ALedger.Dates.Date_Status;
   begin
      if not ALedger.Dates.Parse (Date_Str, Date_Value, Date_Status) then
         Status := Invalid_Date;
         return False;
      end if;

      return Create_Transaction (Date_Value, Payee, Postings, Tx, Status);
   end Create_Transaction;

   function Create_Reversal_Transaction
     (Target_Tx       : Transaction;
      Reversal_ID     : String;
      Reversal_Date   : ALedger.Dates.Date;
      Reversal_Reason : String;
      Rev_Tx          : out Transaction;
      Status          : out Transaction_Error) return Boolean
   is
      Rev_Postings : Posting_Vectors.Vector;
      Cursor       : Posting_Vectors.Cursor := Target_Tx.Postings.First;
      Target_ID    : constant String := (if Length (Target_Tx.Event_ID) > 0 then To_String (Target_Tx.Event_ID) else To_String (Target_Tx.Code_Or_Payee));
      Payee_Text   : constant String := "Reversal: " & Reversal_Reason & " [reverses: " & Target_ID & "]";
   begin
      while Posting_Vectors.Has_Element (Cursor) loop
         declare
            P     : constant Posting := Posting_Vectors.Element (Cursor);
            Rev_P : Posting := P;
         begin
            Rev_P.Amt := Negate_Amount (P.Amt);
            Rev_Postings.Append (Rev_P);
         end;
         Posting_Vectors.Next (Cursor);
      end loop;

      if not Create_Transaction (Reversal_Date, Payee_Text, Rev_Postings, Rev_Tx, Status) then
         return False;
      end if;

      Rev_Tx.Event_ID    := To_Unbounded_String (Reversal_ID);
      Rev_Tx.Reverses_ID := To_Unbounded_String (Target_ID);
      return True;
   end Create_Reversal_Transaction;

   function Create_Reversal_Transaction
     (Target_Tx       : Transaction;
      Reversal_ID     : String;
      Reversal_Date   : String;
      Reversal_Reason : String;
      Rev_Tx          : out Transaction;
      Status          : out Transaction_Error) return Boolean
   is
      Date_Value  : ALedger.Dates.Date;
      Date_Status : ALedger.Dates.Date_Status;
   begin
      if not ALedger.Dates.Parse
        (Reversal_Date, Date_Value, Date_Status)
      then
         Status := Invalid_Date;
         return False;
      end if;

      return Create_Reversal_Transaction
        (Target_Tx,
         Reversal_ID,
         Date_Value,
         Reversal_Reason,
         Rev_Tx,
         Status);
   end Create_Reversal_Transaction;

   function Is_Reversal_Of (Candidate_Rev, Target_Tx : Transaction) return Boolean is
      Expected_Target_ID : constant Unbounded_String :=
        (if Length (Target_Tx.Event_ID) > 0
         then Target_Tx.Event_ID
         else Target_Tx.Code_Or_Payee);
   begin
      if Length (Expected_Target_ID) = 0
        or else Candidate_Rev.Reverses_ID /= Expected_Target_ID
        or else Natural (Candidate_Rev.Postings.Length) /= Natural (Target_Tx.Postings.Length)
        or else Target_Tx.Postings.Is_Empty
      then
         return False;
      end if;

      --  Compare postings as a multiset: order is not part of the reversal law,
      --  but every account/commodity/quantity must have an exact inverse.
      declare
         type Match_Array is array (Positive range <>) of Boolean;
         Matched : Match_Array (1 .. Natural (Candidate_Rev.Postings.Length)) :=
           [others => False];
      begin
         for Target_Posting of Target_Tx.Postings loop
            declare
               Found : Boolean := False;
            begin
               for I in 1 .. Natural (Candidate_Rev.Postings.Length) loop
                  declare
                     Rev_Posting : constant Posting := Candidate_Rev.Postings.Element (I);
                  begin
                     if not Matched (I)
                       and then Rev_Posting.Acc = Target_Posting.Acc
                       and then Rev_Posting.Amt.Comm = Target_Posting.Amt.Comm
                       and then Rev_Posting.Amt.Val = -Target_Posting.Amt.Val
                     then
                        Matched (I) := True;
                        Found := True;
                        exit;
                     end if;
                  end;
               end loop;

               if not Found then
                  return False;
               end if;
            end;
         end loop;
      end;

      return True;
   end Is_Reversal_Of;

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
