with Ada.Containers.Indefinite_Ordered_Maps;

package body ALedger.Budget is

   function Remaining (Env : Budget_Envelope) return Balance is
   begin
      return Subtract_Balance (Env.Entitlement, Env.Consumption);
   end Remaining;

   package Account_Balance_Maps is new Ada.Containers.Indefinite_Ordered_Maps
     (Key_Type     => String,
      Element_Type => Balance);

   function Generate_Budget_Status (L : Ledger.Ledger) return Budget_Status_Report is
      Rep : Budget_Status_Report;
      Map : Account_Balance_Maps.Map;
      Tx_Cursor : Transaction_Vectors.Cursor := L.Transactions.First;
      Tot_Ent : Balance := Empty_Balance;
      Tot_Con : Balance := Empty_Balance;
   begin
      --  Collect balances for accounts declared as Budget
      while Transaction_Vectors.Has_Element (Tx_Cursor) loop
         declare
            Tx : constant Transaction := Transaction_Vectors.Element (Tx_Cursor);
            P_Cursor : Posting_Vectors.Cursor := Tx.Postings.First;
         begin
            while Posting_Vectors.Has_Element (P_Cursor) loop
               declare
                  P       : constant Posting := Posting_Vectors.Element (P_Cursor);
                  Acc_Key : constant String := Name (P.Acc);
                  Cat     : Account_Type;
               begin
                  if Account_Type_For (L.Registry, P.Acc, Cat) and then Cat = ALedger.Account.Budget then
                     declare
                        Amt_Bal : constant Balance := Singleton_Balance (P.Amt);
                     begin
                        if Map.Contains (Acc_Key) then
                           Map.Replace (Acc_Key, Add_Balance (Map.Element (Acc_Key), Amt_Bal));
                        else
                           Map.Insert (Acc_Key, Amt_Bal);
                        end if;
                     end;
                  end if;
               end;
               Posting_Vectors.Next (P_Cursor);
            end loop;
         end;
         Transaction_Vectors.Next (Tx_Cursor);
      end loop;

      declare
         Cursor : Account_Balance_Maps.Cursor := Map.First;
      begin
         while Account_Balance_Maps.Has_Element (Cursor) loop
            declare
               Acc_Key : constant String := Account_Balance_Maps.Key (Cursor);
               Bal     : constant Balance := Account_Balance_Maps.Element (Cursor);
               Acc     : constant Account.Account := Make_Account (Acc_Key);
               Env     : Budget_Envelope;
            begin
               Env := (Acc         => Acc,
                       Entitlement => Bal,
                       Consumption => Empty_Balance);
               Rep.Envelopes.Append (Env);
               Tot_Ent := Add_Balance (Tot_Ent, Bal);
            end;
            Account_Balance_Maps.Next (Cursor);
         end loop;
      end;

      Rep.Total_Entitlement := Tot_Ent;
      Rep.Total_Consumption := Tot_Con;
      Rep.Total_Remaining   := Subtract_Balance (Tot_Ent, Tot_Con);
      return Rep;
   end Generate_Budget_Status;

end ALedger.Budget;
