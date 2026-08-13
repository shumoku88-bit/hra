with Ada.Strings.Fixed;            use Ada.Strings.Fixed;
with Ada.Containers.Indefinite_Ordered_Maps;

package body ALedger.Budget is

   function Remaining (Env : Budget_Envelope) return Balance is
   begin
      return Add_Balance (Subtract_Balance (Env.Entitlement, Env.Consumption), Env.Refunds);
   end Remaining;

   function Headroom (Env : Budget_Envelope) return Balance is
   begin
      return Subtract_Balance (Remaining (Env), Env.Plan_Reserve);
   end Headroom;

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
      --  Sub-account colon match (e.g. 食費:ストック matches 食費:ストック)
      elsif Index (Env_Sub, ":") > 0 and then Index (Exp_Sub, ":") > 0 then
         return Env_Sub = Exp_Sub;
      --  Prefix match when envelope has no sub-colon and expense does not have colon
      elsif Index (Env_Sub, ":") = 0 and then Index (Exp_Sub, ":") = 0 then
         return Index (Exp_Sub, Env_Sub) = Exp_Sub'First or else Index (Env_Sub, Exp_Sub) = Env_Sub'First;
      else
         return False;
      end if;
   end Matches_Envelope_Expense;

   function Generate_Cycle_Budget_Status
     (L                : Ledger.Ledger;
      Cycle_Start_Date : String;
      Cycle_End_Date   : String;
      Observation_Date : String) return Budget_Status_Report
   is
      Rep : Budget_Status_Report;
      Map_Ent : Account_Balance_Maps.Map;
      Map_Exp_Debit  : Account_Balance_Maps.Map;
      Map_Exp_Credit : Account_Balance_Maps.Map;
      Map_Unenveloped: Account_Balance_Maps.Map;
      Tx_Cursor : Transaction_Vectors.Cursor := L.Transactions.First;
      Tot_Ent : Balance := Empty_Balance;
      Tot_Con : Balance := Empty_Balance;
      Tot_Ref : Balance := Empty_Balance;
      Tot_Rem : Balance := Empty_Balance;
      Tot_Res : Balance := Empty_Balance;
      Tot_Hdr : Balance := Empty_Balance;
   begin
      Rep.Cycle_Start_Date := To_Unbounded_String (Cycle_Start_Date);
      Rep.Cycle_End_Date   := To_Unbounded_String (Cycle_End_Date);
      Rep.Observation_Date := To_Unbounded_String (Observation_Date);

      --  Filter transactions occurring within current cycle [Cycle_Start_Date .. Cycle_End_Date)
      while Transaction_Vectors.Has_Element (Tx_Cursor) loop
         declare
            Tx       : constant Transaction := Transaction_Vectors.Element (Tx_Cursor);
            Tx_Date  : constant String := To_String (Tx.Date_Text);
            P_Cursor : Posting_Vectors.Cursor := Tx.Postings.First;
         begin
            if Tx_Date >= Cycle_Start_Date and then Tx_Date < Cycle_End_Date then
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
                           --  Check if this expense matches any envelope account
                           declare
                              Is_Enveloped : Boolean := False;
                           begin
                              for Decl of Declarations (L.Registry) loop
                                 if Decl.Acc_Type = ALedger.Account.Budget and then Matches_Envelope_Expense (Name (Decl.Acc), Acc_Key) then
                                    Is_Enveloped := True;
                                    exit;
                                 end if;
                              end loop;

                              if not Is_Enveloped then
                                 if Map_Unenveloped.Contains (Acc_Key) then
                                    Map_Unenveloped.Replace (Acc_Key, Add_Balance (Map_Unenveloped.Element (Acc_Key), Amt_Bal));
                                 else
                                    Map_Unenveloped.Insert (Acc_Key, Amt_Bal);
                                 end if;
                              else
                                 if P.Amt.Val >= Zero_Quantity then
                                    if Map_Exp_Debit.Contains (Acc_Key) then
                                       Map_Exp_Debit.Replace (Acc_Key, Add_Balance (Map_Exp_Debit.Element (Acc_Key), Amt_Bal));
                                    else
                                       Map_Exp_Debit.Insert (Acc_Key, Amt_Bal);
                                    end if;
                                 else
                                    declare
                                       Pos_Bal : constant Balance := Negate_Balance (Amt_Bal);
                                    begin
                                       if Map_Exp_Credit.Contains (Acc_Key) then
                                          Map_Exp_Credit.Replace (Acc_Key, Add_Balance (Map_Exp_Credit.Element (Acc_Key), Pos_Bal));
                                       else
                                          Map_Exp_Credit.Insert (Acc_Key, Pos_Bal);
                                       end if;
                                    end;
                                 end if;
                              end if;
                           end;
                        end if;
                     end if;
                  end;
                  Posting_Vectors.Next (P_Cursor);
               end loop;
            end if;
         end;
         Transaction_Vectors.Next (Tx_Cursor);
      end loop;

      --  Assemble Envelope Status Lines
      declare
         Cursor : Account_Balance_Maps.Cursor := Map_Ent.First;
      begin
         while Account_Balance_Maps.Has_Element (Cursor) loop
            declare
               Acc_Key : constant String := Account_Balance_Maps.Key (Cursor);
               Ent_Bal : constant Balance := Account_Balance_Maps.Element (Cursor);
               Acc     : constant Account.Account := Make_Account (Acc_Key);
               Con_Bal : Balance := Empty_Balance;
               Ref_Bal : Balance := Empty_Balance;

               Exp_Deb_Cur : Account_Balance_Maps.Cursor := Map_Exp_Debit.First;
               Exp_Crd_Cur : Account_Balance_Maps.Cursor := Map_Exp_Credit.First;
            begin
               --  Sum matching debit expenses (Consumption)
               while Account_Balance_Maps.Has_Element (Exp_Deb_Cur) loop
                  declare
                     Exp_Key : constant String := Account_Balance_Maps.Key (Exp_Deb_Cur);
                     Exp_Val : constant Balance := Account_Balance_Maps.Element (Exp_Deb_Cur);
                  begin
                     if Matches_Envelope_Expense (Acc_Key, Exp_Key) then
                        Con_Bal := Add_Balance (Con_Bal, Exp_Val);
                     end if;
                  end;
                  Account_Balance_Maps.Next (Exp_Deb_Cur);
               end loop;

               --  Sum matching credit expenses (Refunds)
               while Account_Balance_Maps.Has_Element (Exp_Crd_Cur) loop
                  declare
                     Exp_Key : constant String := Account_Balance_Maps.Key (Exp_Crd_Cur);
                     Exp_Val : constant Balance := Account_Balance_Maps.Element (Exp_Crd_Cur);
                  begin
                     if Matches_Envelope_Expense (Acc_Key, Exp_Key) then
                        Ref_Bal := Add_Balance (Ref_Bal, Exp_Val);
                     end if;
                  end;
                  Account_Balance_Maps.Next (Exp_Crd_Cur);
               end loop;

               declare
                  Env : constant Budget_Envelope :=
                    (Acc          => Acc,
                     Entitlement  => Ent_Bal,
                     Consumption  => Con_Bal,
                     Refunds      => Ref_Bal,
                     Plan_Reserve => Empty_Balance);
               begin
                  Rep.Envelopes.Append (Env);
                  Tot_Ent := Add_Balance (Tot_Ent, Ent_Bal);
                  Tot_Con := Add_Balance (Tot_Con, Con_Bal);
                  Tot_Ref := Add_Balance (Tot_Ref, Ref_Bal);
                  Tot_Rem := Add_Balance (Tot_Rem, Remaining (Env));
                  Tot_Res := Add_Balance (Tot_Res, Env.Plan_Reserve);
                  Tot_Hdr := Add_Balance (Tot_Hdr, Headroom (Env));
               end;
            end;
            Account_Balance_Maps.Next (Cursor);
         end loop;
      end;

      --  Assemble Unenveloped Expense Lines
      declare
         Cursor : Account_Balance_Maps.Cursor := Map_Unenveloped.First;
      begin
         while Account_Balance_Maps.Has_Element (Cursor) loop
            declare
               Acc_Key : constant String := Account_Balance_Maps.Key (Cursor);
               Mov_Bal : constant Balance := Account_Balance_Maps.Element (Cursor);
               Acc     : constant Account.Account := Make_Account (Acc_Key);
            begin
               Rep.Unenveloped_Expenses.Append (Unenveloped_Expense_Line'(Acc => Acc, Movement => Mov_Bal));
            end;
            Account_Balance_Maps.Next (Cursor);
         end loop;
      end;

      --  Calculate Funding Balance (Total Assets)
      declare
         Funding : Balance := Empty_Balance;
      begin
         for Decl of Declarations (L.Registry) loop
            if Decl.Acc_Type = ALedger.Account.Asset then
               Funding := Add_Balance (Funding, Compute_Account_Balance (L, Decl.Acc));
            end if;
         end loop;
         Rep.Funding_Balance := Funding;
      end;

      Rep.Total_Entitlement  := Tot_Ent;
      Rep.Total_Consumption  := Tot_Con;
      Rep.Total_Refunds      := Tot_Ref;
      Rep.Total_Remaining    := Tot_Rem;
      Rep.Total_Plan_Reserve := Tot_Res;
      Rep.Total_Headroom     := Tot_Hdr;
      Rep.Backing_Required   := Tot_Rem;
      Rep.Backing_Surplus    := Subtract_Balance (Rep.Funding_Balance, Rep.Backing_Required);
      Rep.Reconciliation_Delta := Rep.Backing_Surplus;

      --  Is_Under_Backed is True if any commodity in Surplus is negative
      declare
         Under : Boolean := False;
         Entries_Arr : constant Balance_Entry_Array := Entries (Rep.Backing_Surplus);
      begin
         for E of Entries_Arr loop
            if E.Val < Zero_Quantity then
               Under := True;
               exit;
            end if;
         end loop;
         Rep.Is_Under_Backed := Under;
      end;

      return Rep;
   end Generate_Cycle_Budget_Status;

   function Generate_Budget_Status (L : Ledger.Ledger) return Budget_Status_Report is
      Min_Date : Unbounded_String := To_Unbounded_String ("9999-12-31");
      Max_Date : Unbounded_String := To_Unbounded_String ("0000-01-01");
      Cursor   : Transaction_Vectors.Cursor := L.Transactions.First;
   begin
      while Transaction_Vectors.Has_Element (Cursor) loop
         declare
            D : constant String := To_String (Transaction_Vectors.Element (Cursor).Date_Text);
         begin
            if D'Length > 0 then
               if D < To_String (Min_Date) then
                  Min_Date := To_Unbounded_String (D);
               end if;
               if D > To_String (Max_Date) then
                  Max_Date := To_Unbounded_String (D);
               end if;
            end if;
         end;
         Transaction_Vectors.Next (Cursor);
      end loop;

      if To_String (Min_Date) = "9999-12-31" then
         Min_Date := To_Unbounded_String ("1900-01-01");
         Max_Date := To_Unbounded_String ("2099-12-31");
      end if;

      return Generate_Cycle_Budget_Status
        (L,
         Cycle_Start_Date => To_String (Min_Date),
         --  The cycle API uses an exclusive upper bound.  A trailing lexical
         --  sentinel includes transactions dated exactly Max_Date.
         Cycle_End_Date   => To_String (Max_Date) & "Z",
         Observation_Date => To_String (Max_Date));
   end Generate_Budget_Status;

end ALedger.Budget;
