with Ada.Characters.Handling; use Ada.Characters.Handling;
with Ada.Strings.Fixed;            use Ada.Strings.Fixed;
with ALedger.Money;                use ALedger.Money;
with ALedger.Account;              use ALedger.Account;
with ALedger.Ledger;               use ALedger.Ledger;

package body ALedger.Journal is

   function Lower_String (S : String) return String is
      Result : String (S'Range);
   begin
      for I in S'Range loop
         Result (I) := To_Lower (S (I));
      end loop;
      return Result;
   end Lower_String;

   function Is_Indented (Line : String) return Boolean is
   begin
      return Line'Length > 0 and then (Line (Line'First) = ' ' or Line (Line'First) = ASCII.HT);
   end Is_Indented;

   function Is_Comment (Line : String) return Boolean is
      Trimmed : constant String := Trim (Line, Ada.Strings.Both);
   begin
      return Trimmed'Length > 0 and then Trimmed (Trimmed'First) = ';';
   end Is_Comment;

   function Split_Account_And_Amount (Line : String; Account_Part, Amount_Part : out Unbounded_String) return Boolean is
      Trimmed : constant String := Trim (Line, Ada.Strings.Both);
      Sep_Idx : Natural := 0;
   begin
      for I in Trimmed'First .. Trimmed'Last - 1 loop
         if Trimmed (I) = ASCII.HT or else (Trimmed (I) = ' ' and then Trimmed (I + 1) = ' ') then
            Sep_Idx := I;
            exit;
         end if;
      end loop;

      if Sep_Idx = 0 then
         Account_Part := To_Unbounded_String (Trimmed);
         Amount_Part  := Null_Unbounded_String;
         return False;
      else
         Account_Part := To_Unbounded_String (Trim (Trimmed (Trimmed'First .. Sep_Idx), Ada.Strings.Both));
         Amount_Part  := To_Unbounded_String (Trim (Trimmed (Sep_Idx + 1 .. Trimmed'Last), Ada.Strings.Both));
         return True;
      end if;
   end Split_Account_And_Amount;

   function Parse_Journal_Text
     (Input     : String;
      L         : out Ledger.Ledger;
      Error_Msg : out Unbounded_String) return Boolean
   is
      Result_Ledger : Ledger.Ledger := Empty_Ledger;

      --  State for transaction parsing
      In_Tx         : Boolean := False;
      Tx_Date       : Unbounded_String;
      Tx_Payee      : Unbounded_String;
      Current_Posts : Posting_Vectors.Vector;

      --  State for account directive parsing
      In_Account_Decl : Boolean := False;
      Current_Acc_Decl : Account_Declaration;

      Line_Start : Positive := Input'First;
      Line_Num   : Natural := 0;

      Has_Error  : Boolean := False;

      procedure Flush_Current_Transaction is
      begin
         if not In_Tx or Has_Error then
            return;
         end if;

         if Current_Posts.Is_Empty then
            In_Tx := False;
            return;
         end if;

         --  Check if any posting has an elided amount
         declare
            Elided_Count  : Natural := 0;
            Elided_Index  : Natural := 0;
            Explicit_Sum  : Balance := Empty_Balance;
            Final_Posts   : Posting_Vectors.Vector;
         begin
            for I in 1 .. Natural (Current_Posts.Length) loop
               declare
                  P : constant Posting := Current_Posts.Element (I);
               begin
                  if Is_Zero (P.Amt.Val) and then Code (P.Amt.Comm) = "" then
                     Elided_Count := Elided_Count + 1;
                     Elided_Index := I;
                  else
                     Explicit_Sum := Add_Balance (Explicit_Sum, Singleton_Balance (P.Amt));
                  end if;
               end;
            end loop;

            if Elided_Count > 1 then
               Error_Msg := To_Unbounded_String ("Multiple postings with omitted amounts in transaction: " & To_String (Tx_Payee));
               Has_Error := True;
               return;
            elsif Elided_Count = 1 then
               --  Infer balancing amount
               declare
                  Entries_Arr : constant Balance_Entry_Array := Entries (Explicit_Sum);
                  Inferred_Amt : Amount;
               begin
                  if Entries_Arr'Length = 1 then
                     Inferred_Amt := Make_Amount (Entries_Arr (1).Comm, -Entries_Arr (1).Val);
                  else
                     Error_Msg := To_Unbounded_String ("Cannot infer omitted amount for multi-commodity balance in transaction: " & To_String (Tx_Payee));
                     Has_Error := True;
                     return;
                  end if;

                  for I in 1 .. Natural (Current_Posts.Length) loop
                     if I = Elided_Index then
                        declare
                           Old_P : constant Posting := Current_Posts.Element (I);
                           New_P : Posting := Old_P;
                        begin
                           New_P.Amt := Inferred_Amt;
                           Final_Posts.Append (New_P);
                        end;
                     else
                        Final_Posts.Append (Current_Posts.Element (I));
                     end if;
                  end loop;
               end;
            else
               Final_Posts := Current_Posts;
            end if;

            declare
               Tx       : Transaction;
               T_Status : Transaction_Error;
            begin
               if not Create_Transaction (To_String (Tx_Date), To_String (Tx_Payee), Final_Posts, Tx, T_Status) then
                  Error_Msg := To_Unbounded_String ("Unbalanced or invalid transaction: " & To_String (Tx_Payee));
                  Has_Error := True;
                  return;
               end if;

               if not Add_Transaction (Result_Ledger, Tx, T_Status) then
                  Error_Msg := To_Unbounded_String ("Failed to add transaction to ledger: " & To_String (Tx_Payee));
                  Has_Error := True;
                  return;
               end if;
            end;
         end;

         In_Tx := False;
         Current_Posts.Clear;
      end Flush_Current_Transaction;

   begin
      while Line_Start <= Input'Last and then not Has_Error loop
         Line_Num := Line_Num + 1;
         declare
            Line_End : Natural := Line_Start;
         begin
            while Line_End <= Input'Last and then Input (Line_End) /= ASCII.LF loop
               Line_End := Line_End + 1;
            end loop;

            declare
               Raw_Line : constant String := Input (Line_Start .. Line_End - 1);
               Trimmed  : constant String := Trim (Raw_Line, Ada.Strings.Both);
            begin
               if Trimmed'Length = 0 then
                  --  Blank line flushes transaction block
                  if not In_Account_Decl then
                     Flush_Current_Transaction;
                  end if;
               elsif not Is_Indented (Raw_Line) then
                  --  Header Line (Transaction or Directive or Full-line Comment)
                  if Is_Comment (Raw_Line) then
                     Flush_Current_Transaction;
                  else
                     Flush_Current_Transaction;
                     In_Account_Decl := False;

                     if Trimmed'Length >= 7 and then Trimmed (Trimmed'First .. Trimmed'First + 6) = "account" then
                        --  account directive
                        declare
                           Acc_Name : constant String := Trim (Trimmed (Trimmed'First + 7 .. Trimmed'Last), Ada.Strings.Both);
                           Acc      : Account.Account;
                           A_Stat   : Account_Status;
                        begin
                           if Create_Account (Acc_Name, Acc, A_Stat) then
                              Current_Acc_Decl := Declare_Account (Acc, Asset);
                              In_Account_Decl  := True;
                              Register_Or_Update_Account (Result_Ledger.Registry, Current_Acc_Decl);
                           end if;
                        end;
                     elsif Trimmed'Length >= 10 and then Is_Digit (Trimmed (Trimmed'First)) then
                        --  Transaction Header: YYYY-MM-DD Description
                        declare
                           Space_Idx : constant Natural := Index (Trimmed, " ");
                        begin
                           if Space_Idx > 0 then
                              Tx_Date  := To_Unbounded_String (Trimmed (Trimmed'First .. Space_Idx - 1));
                              Tx_Payee := To_Unbounded_String (Trim (Trimmed (Space_Idx + 1 .. Trimmed'Last), Ada.Strings.Both));
                           else
                              Tx_Date  := To_Unbounded_String (Trimmed);
                              Tx_Payee := To_Unbounded_String ("");
                           end if;
                           In_Tx := True;
                        end;
                     end if;
                  end if;

               else
                  --  Indented Line (Posting or Account Metadata)
                  if In_Account_Decl and then Is_Comment (Raw_Line) then
                     --  Check metadata for account (e.g.   ; type: Expense)
                     declare
                        S_Idx : Natural := Raw_Line'First;
                     begin
                        while S_Idx <= Raw_Line'Last and then (Raw_Line (S_Idx) = ' ' or else Raw_Line (S_Idx) = ASCII.HT or else Raw_Line (S_Idx) = ';') loop
                           S_Idx := S_Idx + 1;
                        end loop;

                        if S_Idx <= Raw_Line'Last then
                           declare
                              Clean     : constant String := Trim (Raw_Line (S_Idx .. Raw_Line'Last), Ada.Strings.Both);
                              Colon_Idx : constant Natural := Index (Clean, ":");
                           begin
                              if Colon_Idx > 0 then
                                 declare
                                    Key : constant String := Lower_String (Trim (Clean (Clean'First .. Colon_Idx - 1), Ada.Strings.Both));
                                    Val : constant String := Lower_String (Trim (Clean (Colon_Idx + 1 .. Clean'Last), Ada.Strings.Both));
                                 begin
                                    if Key = "type" or Key = "role" then
                                       if Val = "expense" then
                                          Current_Acc_Decl.Acc_Type := Expense;
                                       elsif Val = "income" then
                                          Current_Acc_Decl.Acc_Type := Income;
                                       elsif Val = "liability" then
                                          Current_Acc_Decl.Acc_Type := Liability;
                                       elsif Val = "equity" then
                                          Current_Acc_Decl.Acc_Type := Equity;
                                       elsif Val = "budget" then
                                          Current_Acc_Decl.Acc_Type := Budget;
                                       elsif Val = "asset" then
                                          Current_Acc_Decl.Acc_Type := Asset;
                                       end if;

                                       Register_Or_Update_Account (Result_Ledger.Registry, Current_Acc_Decl);
                                    end if;
                                 end;
                              end if;
                           end;
                        end if;
                     end;
                  elsif In_Tx then
                     --  Posting line
                     if not Is_Comment (Raw_Line) then
                        declare
                           Acc_Part, Amt_Part : Unbounded_String;
                           Has_Amt : constant Boolean := Split_Account_And_Amount (Raw_Line, Acc_Part, Amt_Part);
                           Acc     : Account.Account;
                           A_Stat  : Account_Status;
                        begin
                           if Create_Account (To_String (Acc_Part), Acc, A_Stat) then
                              if Has_Amt and then Length (Amt_Part) > 0 then
                                 declare
                                    Amt_Str   : constant String := To_String (Amt_Part);
                                    Space_Idx : constant Natural := Index (Amt_Str, " ");
                                 begin
                                    if Space_Idx > 0 then
                                       declare
                                          Q_Str : constant String := Amt_Str (Amt_Str'First .. Space_Idx - 1);
                                          C_Str : constant String := Trim (Amt_Str (Space_Idx + 1 .. Amt_Str'Last), Ada.Strings.Both);
                                          Q     : Quantity;
                                          Comm  : Commodity;
                                          C_Stat: Commodity_Status;
                                       begin
                                          if Parse_Quantity (Q_Str, Q) and then Create_Commodity (C_Str, Comm, C_Stat) then
                                             Current_Posts.Append (Make_Posting (Acc, Make_Amount (Comm, Q)));
                                          end if;
                                       end;
                                    end if;
                                 end;
                              else
                                 --  Elided amount (empty amount to be inferred)
                                 declare
                                    Dummy_Comm : Commodity;
                                 begin
                                    Current_Posts.Append (Make_Posting (Acc, Make_Amount (Dummy_Comm, Zero_Quantity)));
                                 end;
                              end if;
                           end if;
                        end;
                     end if;
                  end if;
               end if;
            end;

            Line_Start := Line_End + 1;
         end;
      end loop;

      Flush_Current_Transaction;

      if Has_Error then
         return False;
      end if;

      L := Result_Ledger;
      Error_Msg := Null_Unbounded_String;
      return True;
   end Parse_Journal_Text;

end ALedger.Journal;
