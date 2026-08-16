with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

package body ALedger.Recent_Journal is

   function Observe
     (Actual_Ledger   : ALedger.Ledger.Ledger;
      Actual_Evidence : ALedger.Journal_Evidence.Journal_Evidence;
      Through_Date    : String;
      Count           : Positive;
      Result          : out Observation;
      Status          : out Observe_Status) return Boolean
   is
      Ledger_Count   : constant Natural :=
        Natural (Actual_Ledger.Transactions.Length);
      Evidence_Count : constant Natural :=
        Natural (Actual_Evidence.Transactions.Length);
      Selected       : Natural := 0;
      Index          : Natural := Ledger_Count;
   begin
      Result.Through_Date := To_Unbounded_String (Through_Date);
      Result.Requested := Count;
      Result.Entries.Clear;

      if Ledger_Count /= Evidence_Count then
         Status := Evidence_Count_Mismatch;
         return False;
      end if;

      for I in 1 .. Ledger_Count loop
         declare
            Tx     : constant ALedger.Ledger.Transaction :=
              Actual_Ledger.Transactions.Element (I);
            Source : constant ALedger.Journal_Evidence.Transaction_Source :=
              Actual_Evidence.Transactions.Element (I);
         begin
            if To_String (Tx.Date_Text) /= To_String (Source.Date_Text)
              or else To_String (Tx.Code_Or_Payee) /= To_String (Source.Description)
            then
               Status := Evidence_Alignment_Mismatch;
               return False;
            end if;
         end;
      end loop;

      --  The admitted Ledger vector is the resolved physical source order.
      --  Walk backwards so the semantic result is newest first without sorting
      --  by display fields or reconstructing identity from text.
      while Index > 0 and then Selected < Count loop
         declare
            Tx : constant ALedger.Ledger.Transaction :=
              Actual_Ledger.Transactions.Element (Index);
         begin
            if To_String (Tx.Date_Text) <= Through_Date then
               Result.Entries.Append
                 (Recent_Entry'
                    (Value  => Tx,
                     Source => Actual_Evidence.Transactions.Element (Index)));
               Selected := Selected + 1;
            end if;
         end;
         Index := Index - 1;
      end loop;

      Status := Success;
      return True;
   end Observe;

end ALedger.Recent_Journal;
