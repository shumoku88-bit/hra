with Ada.Strings.Fixed;      use Ada.Strings.Fixed;
with Ada.Strings.Unbounded;  use Ada.Strings.Unbounded;
with ALedger.Money;          use ALedger.Money;
with ALedger.Account;        use ALedger.Account;
with ALedger.Report;         use ALedger.Report;
with ALedger.Household;
with ALedger.Envelope;
with ALedger.Envelope_Entitlement;
with ALedger.Envelope_Consumption;
with ALedger.Envelope_Position;
with ALedger.Backing_Policy;

package body ALedger.Render is

   function Render_Amount_Or_Paren (Q : Quantity; Comm_Code : String) return String is
   begin
      if Is_Zero (Q) then
         return "0";
      elsif Q < Zero_Quantity then
         return "(" & Render_Quantity (-Q) & " " & Comm_Code & ")";
      else
         return Render_Quantity (Q) & " " & Comm_Code;
      end if;
   end Render_Amount_Or_Paren;

   function Render_Multi_Balance (B : Balance) return String is
      Ents : constant Balance_Entry_Array := Entries (B);
      Buf  : Unbounded_String;
   begin
      if Ents'Length = 0 then
         return "0";
      end if;

      for I in Ents'Range loop
         if I > Ents'First then
            Append (Buf, ", ");
         end if;
         Append (Buf, Render_Amount_Or_Paren (Ents (I).Val, Code (Ents (I).Comm)));
      end loop;

      return To_String (Buf);
   end Render_Multi_Balance;

   function Render_Account_Balances
     (L          : Ledger.Ledger;
      As_Of_Date : ALedger.Dates.Date) return String
   is
      Buf : Unbounded_String;
      TB  : constant Trial_Balance := Generate_Trial_Balance_As_Of (L, As_Of_Date);
   begin
      Append (Buf, "== Account Balances (aledger Engine) ==" & ASCII.LF);
      Append (Buf, "As of: " & ALedger.Dates.Image (As_Of_Date) & ASCII.LF);
      Append (Buf, ASCII.LF);
      Append (Buf, "Account         |      Balance" & ASCII.LF);
      Append (Buf, "------------------------------" & ASCII.LF);

      for Line of TB.Lines loop
         if not Is_Zero_Balance (Line.Bal) then
            Append (Buf, Name (Line.Acc) & " | ");
            Append (Buf, Render_Multi_Balance (Line.Bal) & ASCII.LF);
         end if;
      end loop;

      Append (Buf, ASCII.LF);
      if Is_Zero_Balance (TB.Total) then
         Append (Buf, "Balanced: YES" & ASCII.LF);
      else
         Append (Buf, "Balanced: NO" & ASCII.LF);
      end if;

      return To_String (Buf);
   end Render_Account_Balances;

   function Render_Account_Balances
     (L : Ledger.Ledger) return String
   is
      Buf : Unbounded_String;
      TB  : constant Trial_Balance := Generate_Trial_Balance (L);
   begin
      Append (Buf, "== Account Balances (aledger Engine) ==" & ASCII.LF);
      Append (Buf, "As of: all transactions" & ASCII.LF);
      Append (Buf, ASCII.LF);
      Append (Buf, "Account         |      Balance" & ASCII.LF);
      Append (Buf, "------------------------------" & ASCII.LF);

      for Line of TB.Lines loop
         if not Is_Zero_Balance (Line.Bal) then
            Append (Buf, Name (Line.Acc) & " | ");
            Append (Buf, Render_Multi_Balance (Line.Bal) & ASCII.LF);
         end if;
      end loop;

      Append (Buf, ASCII.LF);
      if Is_Zero_Balance (TB.Total) then
         Append (Buf, "Balanced: YES" & ASCII.LF);
      else
         Append (Buf, "Balanced: NO" & ASCII.LF);
      end if;

      return To_String (Buf);
   end Render_Account_Balances;

   function Render_Balance_Sheet
     (L          : Ledger.Ledger;
      As_Of_Date : ALedger.Dates.Date) return String
   is
      Buf : Unbounded_String;
      BS  : constant Balance_Sheet := Generate_Balance_Sheet_As_Of (L, As_Of_Date);
   begin
      Append (Buf, "== Balance Sheet (aledger Engine) ==" & ASCII.LF);
      Append (Buf, "As of: " & ALedger.Dates.Image (As_Of_Date) & ASCII.LF);
      Append (Buf, ASCII.LF);
      Append (Buf, "Assets" & ASCII.LF);
      Append (Buf, "Account      |    Balance" & ASCII.LF);
      Append (Buf, "-------------------------" & ASCII.LF);

      for Line of BS.Asset_Lines loop
         Append (Buf, Name (Line.Acc) & " | " & Render_Multi_Balance (Line.Bal) & ASCII.LF);
      end loop;
      Append (Buf, "Total assets | " & Render_Multi_Balance (BS.Total_Assets) & ASCII.LF);
      Append (Buf, ASCII.LF);

      Append (Buf, "Liabilities" & ASCII.LF);
      Append (Buf, "Account           | Balance" & ASCII.LF);
      Append (Buf, "---------------------------" & ASCII.LF);
      for Line of BS.Liability_Lines loop
         Append (Buf, Name (Line.Acc) & " | " & Render_Multi_Balance (Line.Bal) & ASCII.LF);
      end loop;
      Append (Buf, "Total liabilities | " & Render_Multi_Balance (BS.Total_Liabilities) & ASCII.LF);
      Append (Buf, ASCII.LF);

      Append (Buf, "Equity" & ASCII.LF);
      Append (Buf, "Account          |    Balance" & ASCII.LF);
      Append (Buf, "-----------------------------" & ASCII.LF);
      for Line of BS.Equity_Lines loop
         Append (Buf, Name (Line.Acc) & " | " & Render_Multi_Balance (Line.Bal) & ASCII.LF);
      end loop;
      Append (Buf, "Total equity     | " & Render_Multi_Balance (BS.Total_Equity) & ASCII.LF);
      Append (Buf, ASCII.LF);

      Append (Buf, "Current earnings | " & Render_Multi_Balance (BS.Current_Earnings) & ASCII.LF);
      Append (Buf, "Accounting Equation (Assets = Liabilities + Equity): ");
      if Is_Zero_Balance (BS.Accounting_Equation_Delta) then
         Append (Buf, "BALANCED (delta is strictly ZERO)" & ASCII.LF);
      else
         Append (Buf, "UNBALANCED" & ASCII.LF);
      end if;

      return To_String (Buf);
   end Render_Balance_Sheet;

   function Render_Balance_Sheet
     (L : Ledger.Ledger) return String
   is
      Buf : Unbounded_String;
      BS  : constant Balance_Sheet := Generate_Balance_Sheet (L);
   begin
      Append (Buf, "== Balance Sheet (aledger Engine) ==" & ASCII.LF);
      Append (Buf, "As of: all transactions" & ASCII.LF);
      Append (Buf, ASCII.LF);
      Append (Buf, "Assets" & ASCII.LF);
      Append (Buf, "Account      |    Balance" & ASCII.LF);
      Append (Buf, "-------------------------" & ASCII.LF);

      for Line of BS.Asset_Lines loop
         Append (Buf, Name (Line.Acc) & " | " & Render_Multi_Balance (Line.Bal) & ASCII.LF);
      end loop;
      Append (Buf, "Total assets | " & Render_Multi_Balance (BS.Total_Assets) & ASCII.LF);
      Append (Buf, ASCII.LF);

      Append (Buf, "Liabilities" & ASCII.LF);
      Append (Buf, "Account           | Balance" & ASCII.LF);
      Append (Buf, "---------------------------" & ASCII.LF);
      for Line of BS.Liability_Lines loop
         Append (Buf, Name (Line.Acc) & " | " & Render_Multi_Balance (Line.Bal) & ASCII.LF);
      end loop;
      Append (Buf, "Total liabilities | " & Render_Multi_Balance (BS.Total_Liabilities) & ASCII.LF);
      Append (Buf, ASCII.LF);

      Append (Buf, "Equity" & ASCII.LF);
      Append (Buf, "Account          |    Balance" & ASCII.LF);
      Append (Buf, "-----------------------------" & ASCII.LF);
      for Line of BS.Equity_Lines loop
         Append (Buf, Name (Line.Acc) & " | " & Render_Multi_Balance (Line.Bal) & ASCII.LF);
      end loop;
      Append (Buf, "Total equity     | " & Render_Multi_Balance (BS.Total_Equity) & ASCII.LF);
      Append (Buf, ASCII.LF);

      Append (Buf, "Current earnings | " & Render_Multi_Balance (BS.Current_Earnings) & ASCII.LF);
      Append (Buf, "Accounting Equation (Assets = Liabilities + Equity): ");
      if Is_Zero_Balance (BS.Accounting_Equation_Delta) then
         Append (Buf, "BALANCED (delta is strictly ZERO)" & ASCII.LF);
      else
         Append (Buf, "UNBALANCED" & ASCII.LF);
      end if;

      return To_String (Buf);
   end Render_Balance_Sheet;

   function Render_Profit_And_Loss
     (L      : Ledger.Ledger;
      Period : ALedger.Dates.Closed_Period) return String
   is
      Buf : Unbounded_String;
      PL  : constant Profit_And_Loss := Generate_Profit_And_Loss_Period (L, Period);
   begin
      Append (Buf, "== Profit & Loss Statement (aledger Engine) ==" & ASCII.LF);
      Append (Buf, "Period: " &
              ALedger.Dates.Image (ALedger.Dates.First (Period)) & ".." &
              ALedger.Dates.Image (ALedger.Dates.Last (Period)) & ASCII.LF);
      Append (Buf, ASCII.LF);

      Append (Buf, "Income" & ASCII.LF);
      Append (Buf, "Account       |    Amount" & ASCII.LF);
      Append (Buf, "-------------------------" & ASCII.LF);
      for Line of PL.Income_Lines loop
         Append (Buf, Name (Line.Acc) & " | " & Render_Multi_Balance (Line.Bal) & ASCII.LF);
      end loop;
      Append (Buf, "Total Income  | " & Render_Multi_Balance (PL.Total_Income) & ASCII.LF);
      Append (Buf, ASCII.LF);

      Append (Buf, "Expenses" & ASCII.LF);
      Append (Buf, "Account                        |    Amount" & ASCII.LF);
      Append (Buf, "------------------------------------------" & ASCII.LF);
      for Line of PL.Expense_Lines loop
         Append (Buf, Name (Line.Acc) & " | " & Render_Multi_Balance (Line.Bal) & ASCII.LF);
      end loop;
      Append (Buf, "Total Expenses                 | " & Render_Multi_Balance (PL.Total_Expenses) & ASCII.LF);
      Append (Buf, "------------------------------------------" & ASCII.LF);
      Append (Buf, "Net Profit (Income - Expenses) | " & Render_Multi_Balance (PL.Net_Income) & ASCII.LF);

      return To_String (Buf);
   end Render_Profit_And_Loss;

   function Render_Profit_And_Loss
     (L : Ledger.Ledger) return String
   is
      Buf : Unbounded_String;
      PL  : constant Profit_And_Loss := Generate_Profit_And_Loss (L);
   begin
      Append (Buf, "== Profit & Loss Statement (aledger Engine) ==" & ASCII.LF);
      Append (Buf, "Period: all transactions" & ASCII.LF);
      Append (Buf, ASCII.LF);

      Append (Buf, "Income" & ASCII.LF);
      Append (Buf, "Account       |    Amount" & ASCII.LF);
      Append (Buf, "-------------------------" & ASCII.LF);
      for Line of PL.Income_Lines loop
         Append (Buf, Name (Line.Acc) & " | " & Render_Multi_Balance (Line.Bal) & ASCII.LF);
      end loop;
      Append (Buf, "Total Income  | " & Render_Multi_Balance (PL.Total_Income) & ASCII.LF);
      Append (Buf, ASCII.LF);

      Append (Buf, "Expenses" & ASCII.LF);
      Append (Buf, "Account                        |    Amount" & ASCII.LF);
      Append (Buf, "------------------------------------------" & ASCII.LF);
      for Line of PL.Expense_Lines loop
         Append (Buf, Name (Line.Acc) & " | " & Render_Multi_Balance (Line.Bal) & ASCII.LF);
      end loop;
      Append (Buf, "Total Expenses                 | " & Render_Multi_Balance (PL.Total_Expenses) & ASCII.LF);
      Append (Buf, "------------------------------------------" & ASCII.LF);
      Append (Buf, "Net Profit (Income - Expenses) | " & Render_Multi_Balance (PL.Net_Income) & ASCII.LF);

      return To_String (Buf);
   end Render_Profit_And_Loss;

   function Render_Budget_Status
     (State : ALedger.Household.Household_State) return String
   is
      use ALedger.Envelope;
      use ALedger.Envelope_Entitlement;
      use ALedger.Envelope_Consumption;
      use ALedger.Envelope_Position;
      use ALedger.Backing_Policy;

      Buf : Unbounded_String;
      JPY : constant Commodity := Make_Commodity ("JPY");

      Total_Entitlement : Balance := Empty_Balance;
      Total_Consumption : Balance := Empty_Balance;
      Total_Refunds     : Balance := Empty_Balance;
      Total_Remaining   : Balance := Empty_Balance;

      All_Fully_Backed : Boolean := True;
   begin
      Append (Buf, "== Envelope & Backing ==" & ASCII.LF);
      if State.Consumption.Scope.Kind = Through_Date then
         Append (Buf, "Observed through: " & ALedger.Dates.Image (State.Consumption.Scope.Through) & ASCII.LF);
      end if;
      Append (Buf, ASCII.LF);
      Append (Buf, "Envelope      | Entitlement | Consumption |   Refunds |   Remaining | Plan reserve |    Headroom" & ASCII.LF);
      Append (Buf, "------------------------------------------------------------------------------------------------" & ASCII.LF);

      for Env_Def of State.Budget_Policy.Envelopes loop
         declare
            Env_Name : constant String := To_String (Env_Def.ID);
            Env_Id   : constant Envelope_Id := Make_Envelope_Id (Env_Name);
            Ent_Bal  : constant Balance := Entitlement_For (State.Entitlement, Env_Id);
            Amts     : constant Consumption_Amounts := Consumption_For (State.Consumption, Env_Id);
            Pos      : constant ALedger.Envelope_Position.Position :=
              Position_For (State.Envelope_Positions, Env_Id);
            Res_Bal  : constant Balance := Empty_Balance;

            Ent_Q : constant Quantity := Lookup_Balance (Ent_Bal, JPY);
            Con_Q : constant Quantity := Lookup_Balance (Amts.Charges, JPY);
            Ref_Q : constant Quantity := Lookup_Balance (Amts.Refunds, JPY);
            Rem_Q : constant Quantity := Lookup_Balance (Pos.Remaining, JPY);
            Res_Q : constant Quantity := Lookup_Balance (Res_Bal, JPY);
            Hdr_Q : constant Quantity := Lookup_Balance (Pos.Headroom, JPY);
         begin
            Total_Entitlement := Add_Balance (Total_Entitlement, Ent_Bal);
            Total_Consumption := Add_Balance (Total_Consumption, Amts.Charges);
            Total_Refunds     := Add_Balance (Total_Refunds, Amts.Refunds);
            Total_Remaining   := Add_Balance (Total_Remaining, Pos.Remaining);

            Append (Buf, Env_Name & " | ");
            Append (Buf, Render_Amount_Or_Paren (Ent_Q, "JPY") & " | ");
            Append (Buf, Render_Amount_Or_Paren (Con_Q, "JPY") & " | ");
            Append (Buf, Render_Amount_Or_Paren (Ref_Q, "JPY") & " | ");
            Append (Buf, Render_Amount_Or_Paren (Rem_Q, "JPY") & " | ");
            Append (Buf, Render_Amount_Or_Paren (Res_Q, "JPY") & " | ");
            Append (Buf, Render_Amount_Or_Paren (Hdr_Q, "JPY") & ASCII.LF);
         end;
      end loop;

      --  Unmanaged / Unrouted expenses
      if not State.Consumption.Unmanaged.Is_Empty or else not State.Consumption.Unrouted.Is_Empty then
         Append (Buf, ASCII.LF);
         Append (Buf, "Expense activity outside an envelope" & ASCII.LF);
         Append (Buf, "Account             |   Movement" & ASCII.LF);
         Append (Buf, "--------------------------------" & ASCII.LF);

         for Cursor in State.Consumption.Unmanaged.Iterate loop
            declare
               Acc_Name : constant String :=
                 Account_Amounts_Maps.Key (Cursor);
               Amts     : constant Consumption_Amounts :=
                 Account_Amounts_Maps.Element (Cursor);
               Net_Q    : constant Quantity := Lookup_Balance (Net_Consumption (Amts), JPY);
            begin
               if not Is_Zero (Net_Q) then
                  Append (Buf, Acc_Name & " | " & Render_Amount_Or_Paren (Net_Q, "JPY") & ASCII.LF);
               end if;
            end;
         end loop;

         for Cursor in State.Consumption.Unrouted.Iterate loop
            declare
               Acc_Name : constant String :=
                 Account_Amounts_Maps.Key (Cursor);
               Amts     : constant Consumption_Amounts :=
                 Account_Amounts_Maps.Element (Cursor);
               Net_Q    : constant Quantity := Lookup_Balance (Net_Consumption (Amts), JPY);
            begin
               if not Is_Zero (Net_Q) then
                  Append (Buf, Acc_Name & " (unrouted) | " & Render_Amount_Or_Paren (Net_Q, "JPY") & ASCII.LF);
               end if;
            end;
         end loop;
      end if;

      --  Backing Evidence
      Append (Buf, ASCII.LF);
      Append (Buf, "Backing evidence" & ASCII.LF);
      Append (Buf, "Coordinate                |       Amount" & ASCII.LF);
      Append (Buf, "----------------------------------------" & ASCII.LF);

      for Cursor in State.Backing.Positions.Iterate loop
         declare
            Pool_Name : constant String := Pool_Position_Maps.Key (Cursor);
            Pos       : constant Backing_Pool_Position := Pool_Position_Maps.Element (Cursor);
            Surplus   : constant Balance := Gross_Surplus (Pos);
            Surplus_Q : constant Quantity := Lookup_Balance (Surplus, JPY);
         begin
            if Surplus_Q < Zero_Quantity then
               All_Fully_Backed := False;
            end if;

            Append (Buf, "Funding balance (" & Pool_Name & ") | " & Render_Multi_Balance (Pos.Funding_Balance) & ASCII.LF);
            Append (Buf, "Positive backing required (" & Pool_Name & ") | " & Render_Multi_Balance (Pos.Gross_Envelope_Required) & ASCII.LF);
            Append (Buf, "Backing surplus (" & Pool_Name & ") | " & Render_Multi_Balance (Surplus) & ASCII.LF);
         end;
      end loop;

      Append (Buf, "Signed envelope total     | " & Render_Multi_Balance (Total_Entitlement) & ASCII.LF);
      Append (Buf, ASCII.LF);
      if All_Fully_Backed then
         Append (Buf, "Status: fully_backed" & ASCII.LF);
      else
         Append (Buf, "Status: under_backed" & ASCII.LF);
      end if;

      return To_String (Buf);
   end Render_Budget_Status;

   function Render_Household_Issues (Inv : Issues_Inventory) return String is
      Buf   : Unbounded_String;
      Opens : constant Issue_Vectors.Vector := Open_Issues (Inv);
      Total : constant Natural := Natural (Inv.Items.Length);
      Open_C: constant Natural := Natural (Opens.Length);
      Res_C : constant Natural := Total - Open_C;
   begin
      Append (Buf, "== Household Issues ==" & ASCII.LF);
      Append (Buf, "Source: issues.tsv | open issues only | Displayed: " &
              Trim (Natural'Image (Open_C), Ada.Strings.Both) & " | Resolved hidden: " &
              Trim (Natural'Image (Res_C), Ada.Strings.Both) & ASCII.LF);
      Append (Buf, "Issues do not change accounting or budget values" & ASCII.LF);
      Append (Buf, ASCII.LF);

      for Issue of Opens loop
         Append (Buf, "+- OPEN -------------------------------------------------------------------------------+" & ASCII.LF);
         Append (Buf, "| ID       : " & To_String (Issue.Issue_ID) & ASCII.LF);
         Append (Buf, "| Recorded : " & To_String (Issue.Date_Str) & ASCII.LF);
         Append (Buf, "| Amount   : " & Render_Quantity (Issue.Amt.Val) & " " & Code (Issue.Amt.Comm) & ASCII.LF);
         Append (Buf, "| Title    : " & To_String (Issue.Title) & ASCII.LF);
         Append (Buf, "| Details  : [" & To_String (Issue.Category) & "] " & To_String (Issue.Details) & ASCII.LF);
         Append (Buf, "+--------------------------------------------------------------------------------------+" & ASCII.LF);
         Append (Buf, ASCII.LF);
      end loop;

      return To_String (Buf);
   end Render_Household_Issues;

   function Render_Recent_Transactions
     (L     : Ledger.Ledger;
      Count : Positive := 5) return String
   is
      Buf   : Unbounded_String;
      Total : constant Natural := Natural (L.Transactions.Length);
      Start : constant Natural := (if Total > Count then Total - Count + 1 else 1);
   begin
      Append (Buf, "== Recent Transactions (Latest " & Trim (Natural'Image (Count), Ada.Strings.Both) & ") ==" & ASCII.LF);
      Append (Buf, ASCII.LF);

      for I in reverse Start .. Total loop
         declare
            Tx : constant Transaction := L.Transactions.Element (I);
         begin
            Append (Buf, ALedger.Dates.Image (Tx.Date) & " " & To_String (Tx.Code_Or_Payee) & ASCII.LF);
            for P of Tx.Postings loop
               Append (Buf, "    " & Name (P.Acc) & "    " & Render_Amount_Or_Paren (P.Amt.Val, Code (P.Amt.Comm)) & ASCII.LF);
            end loop;
            Append (Buf, ASCII.LF);
         end;
      end loop;

      return To_String (Buf);
   end Render_Recent_Transactions;

end ALedger.Render;
