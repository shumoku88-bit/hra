with Ada.Strings.Fixed;     use Ada.Strings.Fixed;
with ALedger.Money;          use ALedger.Money;
with ALedger.Account;        use ALedger.Account;
with ALedger.Ledger;         use ALedger.Ledger;

package body ALedger.Journal is

   function Format_Diagnostic (Diag : Parse_Diagnostic) return String is
      FName : constant String := (if Length (Diag.File_Name) > 0 then To_String (Diag.File_Name) else "<journal>");
   begin
      if Diag.Line_Number > 0 then
         if Length (Diag.Raw_Text) > 0 then
            return FName & ":" & Trim (Natural'Image (Diag.Line_Number), Ada.Strings.Both) &
                   ": " & To_String (Diag.Message) & " [Context: \"" & To_String (Diag.Raw_Text) & "\"]";
         else
            return FName & ":" & Trim (Natural'Image (Diag.Line_Number), Ada.Strings.Both) &
                   ": " & To_String (Diag.Message);
         end if;
      else
         return FName & ": " & To_String (Diag.Message);
      end if;
   end Format_Diagnostic;

   -- Helper function to convert a string to lower case
   function Lower_String (Str : String) return String is
      Result : String := Str;
   begin
      for I in Result'Range loop
         if Result (I) in 'A' .. 'Z' then
            Result (I) := Character'Val (Character'Pos (Result (I)) + 32);
         end if;
      end loop;
      return Result;
   end Lower_String;

   function Is_Whitespace (C : Character) return Boolean is
   begin
      return C = ' ' or else C = ASCII.HT;
   end Is_Whitespace;

   function Is_Digit (C : Character) return Boolean is
   begin
      return C in '0' .. '9';
   end Is_Digit;

   function Is_Valid_Date (S : String) return Boolean is
   begin
      if S'Length /= 10 then
         return False;
      end if;

      for Offset in 0 .. 9 loop
         if Offset = 4 or else Offset = 7 then
            if S (S'First + Offset) /= '-' then
               return False;
            end if;
         elsif not Is_Digit (S (S'First + Offset)) then
            return False;
         end if;
      end loop;

      return True;
   end Is_Valid_Date;

   function Is_Comment (Line : String) return Boolean is
      Trimmed : constant String := Trim (Line, Ada.Strings.Both);
   begin
      if Trimmed'Length = 0 then
         return False;
      end if;
      return Trimmed (Trimmed'First) = ';' or else Trimmed (Trimmed'First) = '#';
   end Is_Comment;

   function Is_Indented (Line : String) return Boolean is
   begin
      if Line'Length = 0 then
         return False;
      end if;
      return Line (Line'First) = ' ' or else Line (Line'First) = ASCII.HT;
   end Is_Indented;

   function Parse_Posting_Amount (Input : String; Amt : out Amount) return Boolean is
      Trimmed   : constant String := Trim (Input, Ada.Strings.Both);
      Clean     : Unbounded_String := Null_Unbounded_String;
      Comm_Code : Unbounded_String := Null_Unbounded_String;
      Comm      : Commodity;
      C_Stat    : Commodity_Status;
      Q         : Quantity;
   begin
      if Trimmed'Length = 0 then
         return False;
      end if;

      for I in Trimmed'Range loop
         declare
            C : constant Character := Trimmed (I);
         begin
            if C = ',' then
               null;  -- Skip thousands separators
            elsif Is_Digit (C) or else C = '.' or else C = '-' or else C = '+' then
               Append (Clean, C);
            elsif (C in 'A' .. 'Z') or else (C in 'a' .. 'z') then
               Append (Comm_Code, C);
            elsif C = '$' then
               Append (Comm_Code, "USD");
            end if;
         end;
      end loop;

      if Length (Comm_Code) = 0 then
         Comm_Code := To_Unbounded_String ("JPY");
      end if;

      if not Create_Commodity (To_String (Comm_Code), Comm, C_Stat) then
         return False;
      end if;

      if not Parse_Quantity (To_String (Clean), Q) then
         return False;
      end if;

      Amt := Make_Amount (Comm, Q);
      return True;
   end Parse_Posting_Amount;

   function Split_Account_And_Amount
     (Line        : String;
      Account_Str : out Unbounded_String;
      Amount_Str  : out Unbounded_String) return Boolean
   is
      Trimmed   : constant String := Trim (Line, Ada.Strings.Both);
      Split_Idx : Natural := 0;
   begin
      if Trimmed'Length = 0 then
         Account_Str := Null_Unbounded_String;
         Amount_Str  := Null_Unbounded_String;
         return False;
      end if;

      --  Look for 2+ spaces or tab separator between Account and Amount
      for I in Trimmed'First .. Trimmed'Last - 1 loop
         if (Trimmed (I) = ' ' and then Trimmed (I + 1) = ' ') or else Trimmed (I) = ASCII.HT then
            Split_Idx := I;
            exit;
         end if;
      end loop;

      if Split_Idx > 0 then
         Account_Str := To_Unbounded_String (Trimmed (Trimmed'First .. Split_Idx - 1));
         Amount_Str  := To_Unbounded_String (Trim (Trimmed (Split_Idx .. Trimmed'Last), Ada.Strings.Both));
         return True;
      end if;

      --  Fallback for single space separator: scan backwards for whitespace before digits
      for I in reverse Trimmed'Range loop
         if Is_Whitespace (Trimmed (I)) then
            declare
               Tail    : constant String := Trim (Trimmed (I + 1 .. Trimmed'Last), Ada.Strings.Both);
               Has_Dig : Boolean := False;
            begin
               for K in Tail'Range loop
                  if Is_Digit (Tail (K)) then
                     Has_Dig := True;
                     exit;
                  end if;
               end loop;

               if Has_Dig then
                  declare
                     Acc_End : Natural := I - 1;
                  begin
                     while Acc_End >= Trimmed'First and then Is_Whitespace (Trimmed (Acc_End)) loop
                        Acc_End := Acc_End - 1;
                     end loop;

                     Account_Str := To_Unbounded_String (Trimmed (Trimmed'First .. Acc_End));
                     Amount_Str  := To_Unbounded_String (Trim (Trimmed (Acc_End + 1 .. Trimmed'Last), Ada.Strings.Both));
                     return True;
                  end;
               end if;
            end;
         end if;
      end loop;

      Account_Str := To_Unbounded_String (Trimmed);
      Amount_Str  := Null_Unbounded_String;
      return False;
   end Split_Account_And_Amount;

   function Normalize_String (S : String) return String is
      Res : String (1 .. S'Length);
   begin
      Res := S;
      return Res;
   end Normalize_String;

   function Parse_Journal_Text
     (Input     : String;
      File_Name : String;
      L         : out Ledger.Ledger;
      Diag      : out Parse_Diagnostic) return Boolean
   is
      Result_Ledger    : Ledger.Ledger := Empty_Ledger;
      Line_Start       : Natural := Input'First;
      Line_Num         : Natural := 0;

      Has_Error        : Boolean := False;
      Cur_Raw_Line     : Unbounded_String := Null_Unbounded_String;

      In_Tx            : Boolean := False;
      Tx_Date          : Unbounded_String;
      Tx_Payee         : Unbounded_String;
      Current_Posts    : Posting_Vectors.Vector;

      In_Account_Decl     : Boolean := False;
      Current_Acc_Decl    : Account_Declaration;
      Current_Acc_Has_Type : Boolean := False;
      Current_Acc_Line    : Natural := 0;
      Current_Acc_Raw     : Unbounded_String := Null_Unbounded_String;

      procedure Set_Error (Msg : String) is
      begin
         Has_Error := True;
         Diag := (File_Name   => To_Unbounded_String (File_Name),
                  Line_Number => Line_Num,
                  Raw_Text    => Cur_Raw_Line,
                  Message     => To_Unbounded_String (Msg));
      end Set_Error;

      procedure Set_Account_Error (Msg : String) is
      begin
         Has_Error := True;
         Diag := (File_Name   => To_Unbounded_String (File_Name),
                  Line_Number => Current_Acc_Line,
                  Raw_Text    => Current_Acc_Raw,
                  Message     => To_Unbounded_String (Msg));
      end Set_Account_Error;

      procedure Flush_Current_Account_Declaration is
         Status : Registry_Status;
      begin
         if not In_Account_Decl or else Has_Error then
            return;
         end if;

         if not Current_Acc_Has_Type then
            Set_Account_Error
              ("Account declaration requires explicit type or role metadata: " &
               Name (Current_Acc_Decl.Acc));
            return;
         end if;

         if not Register_Account
           (Result_Ledger.Registry, Current_Acc_Decl, Status)
         then
            Set_Account_Error
              ("Duplicate account declaration: " & Name (Current_Acc_Decl.Acc));
            return;
         end if;

         In_Account_Decl      := False;
         Current_Acc_Has_Type := False;
      end Flush_Current_Account_Declaration;

      procedure Flush_Current_Transaction is
      begin
         if not In_Tx or Has_Error then
            return;
         end if;

         if Current_Posts.Is_Empty then
            In_Tx := False;
            return;
         end if;

         declare
            Elided_Count : Natural := 0;
            Elided_Index : Natural := 0;
            Explicit_Sum : Balance := Empty_Balance;
            Final_Posts  : Posting_Vectors.Vector;
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
               Set_Error ("Multiple postings with omitted amounts in transaction: " & To_String (Tx_Payee));
               return;
            elsif Elided_Count = 1 then
               declare
                  Entries_Arr  : constant Balance_Entry_Array := Entries (Explicit_Sum);
                  Inferred_Amt : Amount;
               begin
                  if Entries_Arr'Length = 1 then
                     Inferred_Amt := Make_Amount (Entries_Arr (1).Comm, -Entries_Arr (1).Val);
                  else
                     Set_Error ("Cannot infer omitted amount for multi-commodity balance in transaction: " & To_String (Tx_Payee));
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
                  Set_Error ("Unbalanced or invalid transaction balance law: " & To_String (Tx_Payee));
                  return;
               end if;

               declare
                  P_Str : constant String := To_String (Tx_Payee);
                  E_Idx : constant Natural := Index (P_Str, "event-id:");
                  R_Idx : constant Natural := Index (P_Str, "reverses:");
               begin
                  if E_Idx > 0 then
                     declare
                        Rest_E : constant String := P_Str (E_Idx + 9 .. P_Str'Last);
                        End_E  : constant Natural := Index (Rest_E, "]");
                        Val_E  : constant String := (if End_E > 0 then Trim (Rest_E (Rest_E'First .. End_E - 1), Ada.Strings.Both) else Trim (Rest_E, Ada.Strings.Both));
                     begin
                        Tx.Event_ID := To_Unbounded_String (Val_E);
                     end;
                  end if;

                  if R_Idx > 0 then
                     declare
                        Rest_R : constant String := P_Str (R_Idx + 9 .. P_Str'Last);
                        End_R  : constant Natural := Index (Rest_R, "]");
                        Val_R  : constant String := (if End_R > 0 then Trim (Rest_R (Rest_R'First .. End_R - 1), Ada.Strings.Both) else Trim (Rest_R, Ada.Strings.Both));
                     begin
                        Tx.Reverses_ID := To_Unbounded_String (Val_R);
                     end;
                  end if;
               end;

               if not Add_Transaction (Result_Ledger, Tx, T_Status) then
                  Set_Error ("Failed to add transaction to ledger: " & To_String (Tx_Payee));
                  return;
               end if;
            end;
         end;

         In_Tx := False;
         Current_Posts.Clear;
      end Flush_Current_Transaction;

   begin
      Diag := (File_Name   => To_Unbounded_String (File_Name),
               Line_Number => 0,
               Raw_Text    => Null_Unbounded_String,
               Message     => Null_Unbounded_String);

      while Line_Start <= Input'Last and then not Has_Error loop
         Line_Num := Line_Num + 1;
         declare
            Line_End : Natural := Line_Start;
         begin
            while Line_End <= Input'Last and then Input (Line_End) /= ASCII.LF loop
               Line_End := Line_End + 1;
            end loop;

            declare
               Raw_Line_Slice : constant String := Input (Line_Start .. Line_End - 1);
               Last_Idx       : constant Natural := (if Raw_Line_Slice'Length > 0 and then Raw_Line_Slice (Raw_Line_Slice'Last) = ASCII.CR then Raw_Line_Slice'Last - 1 else Raw_Line_Slice'Last);
               Raw_Line       : constant String := Normalize_String ((if Raw_Line_Slice'Length > 0 and then Last_Idx >= Raw_Line_Slice'First then Raw_Line_Slice (Raw_Line_Slice'First .. Last_Idx) else ""));
               Trimmed        : constant String := Normalize_String (Trim (Raw_Line, Ada.Strings.Both));
            begin
               Cur_Raw_Line := To_Unbounded_String (Raw_Line);

               if Trimmed'Length = 0 then
                  Flush_Current_Transaction;
                  Flush_Current_Account_Declaration;
               elsif not Is_Indented (Raw_Line) then
                  Flush_Current_Transaction;
                  Flush_Current_Account_Declaration;

                  if not Has_Error then
                     if Is_Comment (Raw_Line) then
                        null;
                     elsif Trimmed'Length >= 7 and then Lower_String (Trimmed (Trimmed'First .. Trimmed'First + 6)) = "include" then
                        null;
                     elsif Trimmed'Length >= 7 and then Lower_String (Trimmed (Trimmed'First .. Trimmed'First + 6)) = "account" then
                        declare
                           Acc_Name : constant String := Trim (Trimmed (Trimmed'First + 7 .. Trimmed'Last), Ada.Strings.Both);
                           Acc      : Account.Account;
                           A_Stat   : Account_Status;
                        begin
                           if Create_Account (Acc_Name, Acc, A_Stat) then
                              --  Asset is only a temporary record value. A declaration
                              --  is never admitted until explicit type/role metadata
                              --  replaces it and the complete declaration is flushed.
                              Current_Acc_Decl := Declare_Account (Acc, Asset);
                              Current_Acc_Has_Type := False;
                              Current_Acc_Line := Line_Num;
                              Current_Acc_Raw := Cur_Raw_Line;
                              In_Account_Decl := True;
                           else
                              Set_Error ("Invalid account declaration: " & Acc_Name);
                           end if;
                        end;
                     elsif Is_Digit (Trimmed (Trimmed'First)) then
                        declare
                           Space_Idx : constant Natural := Index (Trimmed, " ");
                           Date_End  : constant Natural :=
                             (if Space_Idx > 0 then Space_Idx - 1 else Trimmed'Last);
                           Date_Str  : constant String :=
                             Trimmed (Trimmed'First .. Date_End);
                        begin
                           if not Is_Valid_Date (Date_Str) then
                              Set_Error ("Invalid transaction date: " & Date_Str);
                           else
                              Tx_Date := To_Unbounded_String (Date_Str);
                              if Space_Idx > 0 then
                                 declare
                                    Rest : constant String := Trim (Trimmed (Space_Idx + 1 .. Trimmed'Last), Ada.Strings.Both);
                                 begin
                                    if Rest'Length > 0 and then (Rest (Rest'First) = '*' or else Rest (Rest'First) = '!') then
                                       Tx_Payee := To_Unbounded_String (Trim (Rest (Rest'First + 1 .. Rest'Last), Ada.Strings.Both));
                                    else
                                       Tx_Payee := To_Unbounded_String (Rest);
                                    end if;
                                 end;
                              else
                                 Tx_Payee := Null_Unbounded_String;
                              end if;
                              In_Tx := True;
                           end if;
                        end;
                     else
                        Set_Error ("Unsupported journal directive or transaction header");
                     end if;
                  end if;

               else
                  if In_Account_Decl then
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
                                       else
                                          Set_Error ("Unsupported account type or role: " & Val);
                                       end if;

                                       if not Has_Error then
                                          Current_Acc_Has_Type := True;
                                       end if;
                                    end if;
                                 end;
                              end if;
                           end;
                        end if;
                     end;
                  elsif In_Tx then
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
                                    Parsed_Amt : Amount;
                                 begin
                                    if Parse_Posting_Amount (To_String (Amt_Part), Parsed_Amt) then
                                       Current_Posts.Append (Make_Posting (Acc, Parsed_Amt));
                                    else
                                       Set_Error ("Invalid posting amount format: " & To_String (Amt_Part));
                                    end if;
                                 end;
                              else
                                 declare
                                    Dummy_Comm : Commodity;
                                 begin
                                    Current_Posts.Append (Make_Posting (Acc, Make_Amount (Dummy_Comm, Zero_Quantity)));
                                 end;
                              end if;
                           else
                              Set_Error ("Invalid posting account: " & To_String (Acc_Part));
                           end if;
                        end;
                     end if;
                  elsif not Is_Comment (Raw_Line) then
                     Set_Error ("Indented journal content outside an account or transaction");
                  end if;
               end if;
            end;

            Line_Start := Line_End + 1;
         end;
      end loop;

      Flush_Current_Transaction;
      Flush_Current_Account_Declaration;

      if Has_Error then
         return False;
      end if;

      L := Result_Ledger;
      return True;
   end Parse_Journal_Text;

   function Parse_Journal_Text
     (Input     : String;
      L         : out Ledger.Ledger;
      Error_Msg : out Unbounded_String) return Boolean
   is
      Diag : Parse_Diagnostic;
      Res  : constant Boolean := Parse_Journal_Text (Input, "", L, Diag);
   begin
      if not Res then
         Error_Msg := To_Unbounded_String (Format_Diagnostic (Diag));
      else
         Error_Msg := Null_Unbounded_String;
      end if;
      return Res;
   end Parse_Journal_Text;

end ALedger.Journal;
