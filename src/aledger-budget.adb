with Ada.Strings.Fixed;            use Ada.Strings.Fixed;
with Ada.Containers.Indefinite_Ordered_Maps;

package body ALedger.Budget is

   function Remaining (Env : Budget_Envelope) return Balance is
   begin
      return Subtract_Balance (Env.Entitlement, Env.Consumption);
   end Remaining;

   package Account_Balance_Maps is new Ada.Containers.Indefinite_Ordered_Maps
     (Key_Type     => String,
      Element_Type => Balance);

   function Extract_Category_Subname (Full_Name, Prefix : String) return String is
   begin
      if Index (Full_Name, Prefix) = Full_Name'First then
         return Full_Name (Full_Name'First + Prefix'Length .. Full_Name'Last);
      else
         return Full_Name;
      end if;
   end Extract_Category_Subname;

   function Matches_Envelope_Expense (Env_Name, Exp_Name : String) return Boolean is
      Env_Sub : constant String := Extract_Category_Subname (Env_Name, "budget:");
      Exp_Sub : constant String := Extract_Category_Subname (Exp_Name, "expenses:");
   begin
      if Env_Sub'Length = 0 or else Exp_Sub'Length = 0 then
         return False;
      end if;

      --  Exact match
      if Env_Sub = Exp_Sub then
         return True;
      --  Sub-account or category prefix match (e.g. 食費 matches 食費 and 食費:ストック)
      elsif Index (Exp_Sub, Env_Sub) = Exp_Sub'First then
         return True;
      elsif Index (Env_Sub, Exp_Sub) = Env_Sub'First then
         return True;
      else
         return False;
      end if;
   end Matches_Envelope_Expense;

   function Generate_Budget_Status (L : Ledger.Ledger) return Budget_Status_Report is
      Rep : Budget_Status_Report;
      Map_Ent : Account_Balance_Maps.Map;
      Map_Exp : Account_Balance_Maps.Map;
      Tx_Cursor : Transaction_Vectors.Cursor := L.Transactions.First;
      Tot_Ent : Balance := Empty_Balance;
      Tot_Con : Balance := Empty_Balance;
   begin
      --  Collect balances for all accounts across transactions
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
                  Amt_Bal : constant Balance := Singleton_Balance (P.Amt);
               begin
                  if Account_Type_For (L.Registry, P.Acc, Cat) then
                     if Cat = ALedger.Account.Budget then
                        if Map_Ent.Contains (Acc_Key) then
                           Map_Ent.Replace (Acc_Key, Add_Balance (Map_Ent.Element (Acc_Key), Amt_Bal));
                        else
                           Map_Ent.Insert (Acc_Key, Amt_Bal);
                        end if;
                     elsif Cat = Expense then
                        if Map_Exp.Contains (Acc_Key) then
                           Map_Exp.Replace (Acc_Key, Add_Balance (Map_Exp.Element (Acc_Key), Amt_Bal));
                        else
                           Map_Exp.Insert (Acc_Key, Amt_Bal);
                        end if;
                     end if;
                  end if;
               end;
               Posting_Vectors.Next (P_Cursor);
            end loop;
         end;
         Transaction_Vectors.Next (Tx_Cursor);
      end loop;

      declare
         Cursor : Account_Balance_Maps.Cursor := Map_Ent.First;
      begin
         while Account_Balance_Maps.Has_Element (Cursor) loop
            declare
               Acc_Key : constant String := Account_Balance_Maps.Key (Cursor);
               Ent_Bal : constant Balance := Account_Balance_Maps.Element (Cursor);
               Acc     : constant Account.Account := Make_Account (Acc_Key);
               Con_Bal : Balance := Empty_Balance;
               Exp_Cur : Account_Balance_Maps.Cursor := Map_Exp.First;
            begin
               --  Sum matching expenses for this envelope
               while Account_Balance_Maps.Has_Element (Exp_Cur) loop
                  declare
                     Exp_Key : constant String := Account_Balance_Maps.Key (Exp_Cur);
                     Exp_Val : constant Balance := Account_Balance_Maps.Element (Exp_Cur);
                  begin
                     if Matches_Envelope_Expense (Acc_Key, Exp_Key) then
                        Con_Bal := Add_Balance (Con_Bal, Exp_Val);
                     end if;
                  end;
                  Account_Balance_Maps.Next (Exp_Cur);
               end loop;

               declare
                  Env : constant Budget_Envelope :=
                    (Acc         => Acc,
                     Entitlement => Ent_Bal,
                     Consumption => Con_Bal);
               begin
                  Rep.Envelopes.Append (Env);
                  Tot_Ent := Add_Balance (Tot_Ent, Ent_Bal);
                  Tot_Con := Add_Balance (Tot_Con, Con_Bal);
               end;
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
