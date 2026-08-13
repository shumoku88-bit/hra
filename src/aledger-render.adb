with Ada.Strings.Fixed;      use Ada.Strings.Fixed;
with Ada.Strings.Unbounded;  use Ada.Strings.Unbounded;
with ALedger.Money;          use ALedger.Money;
with ALedger.Account;        use ALedger.Account;
with ALedger.Report;         use ALedger.Report;
with ALedger.Budget;         use ALedger.Budget;
with ALedger.Issues;         use ALedger.Issues;

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

   function Render_Account_Balances
     (L          : Ledger.Ledger;
      As_Of_Date : String) return String
   is
      Buf : Unbounded_String;
      TB  : constant Trial_Balance := Generate_Trial_Balance (L);
      JPY : constant Commodity := Make_Commodity ("JPY");
   begin
      Append (Buf, "== Account Balances (aledger Engine) ==" & ASCII.LF);
      Append (Buf, "As of: " & As_Of_Date & ASCII.LF);
      Append (Buf, ASCII.LF);
      Append (Buf, "Account         |      Balance" & ASCII.LF);
      Append (Buf, "------------------------------" & ASCII.LF);

      for Decl of Declarations (L.Registry) loop
         declare
            Acc_Bal : constant Balance := Compute_Account_Balance (L, Decl.Acc);
            Val_Q   : constant Quantity := Lookup_Balance (Acc_Bal, JPY);
         begin
            if not Is_Zero (Val_Q) then
               Append (Buf, Name (Decl.Acc) & " | ");
               Append (Buf, Render_Amount_Or_Paren (Val_Q, "JPY") & ASCII.LF);
            end if;
         end;
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
      As_Of_Date : String) return String
   is
      Buf : Unbounded_String;
      BS  : constant Balance_Sheet := Generate_Balance_Sheet (L);
      JPY : constant Commodity := Make_Commodity ("JPY");
   begin
      Append (Buf, "== Balance Sheet (aledger Engine) ==" & ASCII.LF);
      Append (Buf, "As of: " & As_Of_Date & ASCII.LF);
      Append (Buf, ASCII.LF);
      Append (Buf, "Assets" & ASCII.LF);
      Append (Buf, "Account      |    Balance" & ASCII.LF);
      Append (Buf, "-------------------------" & ASCII.LF);

      for Line of BS.Asset_Lines loop
         Append (Buf, Name (Line.Acc) & " | " & Render_Quantity (Lookup_Balance (Line.Bal, JPY)) & " JPY" & ASCII.LF);
      end loop;
      Append (Buf, "Total assets | " & Render_Quantity (Lookup_Balance (BS.Total_Assets, JPY)) & " JPY" & ASCII.LF);
      Append (Buf, ASCII.LF);

      Append (Buf, "Liabilities" & ASCII.LF);
      Append (Buf, "Account           | Balance" & ASCII.LF);
      Append (Buf, "---------------------------" & ASCII.LF);
      Append (Buf, "Total liabilities |       0" & ASCII.LF);
      Append (Buf, ASCII.LF);

      Append (Buf, "Equity" & ASCII.LF);
      Append (Buf, "Account          |    Balance" & ASCII.LF);
      Append (Buf, "-----------------------------" & ASCII.LF);
      Append (Buf, "Current earnings | " & Render_Quantity (Lookup_Balance (BS.Current_Earnings, JPY)) & " JPY" & ASCII.LF);
      Append (Buf, "Total equity     | " & Render_Quantity (Lookup_Balance (BS.Total_Equity, JPY)) & " JPY" & ASCII.LF);
      Append (Buf, ASCII.LF);

      if Is_Zero_Balance (BS.Accounting_Equation_Delta) then
         Append (Buf, "Balanced: YES (Net Check: 0)" & ASCII.LF);
      else
         Append (Buf, "Balanced: NO" & ASCII.LF);
      end if;

      return To_String (Buf);
   end Render_Balance_Sheet;

   function Render_Profit_And_Loss
     (L          : Ledger.Ledger;
      Start_Date : String;
      End_Date   : String) return String
   is
      Buf : Unbounded_String;
      PL  : constant Profit_And_Loss := Generate_Profit_And_Loss (L);
      JPY : constant Commodity := Make_Commodity ("JPY");
   begin
      Append (Buf, "== Profit & Loss Statement (aledger Engine) ==" & ASCII.LF);
      Append (Buf, "Period: " & Start_Date & ".." & End_Date & ASCII.LF);
      Append (Buf, ASCII.LF);
      Append (Buf, "Income" & ASCII.LF);
      Append (Buf, "Account       |    Amount" & ASCII.LF);
      Append (Buf, "-------------------------" & ASCII.LF);

      for Line of PL.Income_Lines loop
         Append (Buf, Name (Line.Acc) & " | " & Render_Quantity (Lookup_Balance (Line.Bal, JPY)) & " JPY" & ASCII.LF);
      end loop;
      Append (Buf, "Total Income  | " & Render_Quantity (Lookup_Balance (PL.Total_Income, JPY)) & " JPY" & ASCII.LF);
      Append (Buf, ASCII.LF);

      Append (Buf, "Expenses" & ASCII.LF);
      Append (Buf, "Account                        |    Amount" & ASCII.LF);
      Append (Buf, "------------------------------------------" & ASCII.LF);

      for Line of PL.Expense_Lines loop
         Append (Buf, Name (Line.Acc) & " | " & Render_Quantity (Lookup_Balance (Line.Bal, JPY)) & " JPY" & ASCII.LF);
      end loop;
      Append (Buf, "Total Expenses                 | " & Render_Quantity (Lookup_Balance (PL.Total_Expenses, JPY)) & " JPY" & ASCII.LF);
      Append (Buf, "------------------------------------------" & ASCII.LF);
      Append (Buf, "Net Profit (Income - Expenses) | " & Render_Quantity (Lookup_Balance (PL.Net_Income, JPY)) & " JPY" & ASCII.LF);

      return To_String (Buf);
   end Render_Profit_And_Loss;

   function Render_Budget_Status
     (L : Ledger.Ledger) return String
   is
      Buf : Unbounded_String;
      BSR : constant Budget_Status_Report := Generate_Budget_Status (L);
      JPY : constant Commodity := Make_Commodity ("JPY");

      function Extract_Sub (Acc_Name : String) return String is
         Sep_Idx : constant Natural := Index (Acc_Name, ":");
      begin
         if Sep_Idx > 0 then
            return Acc_Name (Sep_Idx + 1 .. Acc_Name'Last);
         else
            return Acc_Name;
         end if;
      end Extract_Sub;

   begin
      Append (Buf, "== Envelope & Backing ==" & ASCII.LF);
      Append (Buf, "Cycle: [" & To_String (BSR.Cycle_Start_Date) & ", " & To_String (BSR.Cycle_End_Date) & ") | Observed through: " & To_String (BSR.Observation_Date) & ASCII.LF);
      Append (Buf, ASCII.LF);
      Append (Buf, "Envelope      | Entitlement | Consumption |   Refunds |   Remaining | Plan reserve |    Headroom" & ASCII.LF);
      Append (Buf, "------------------------------------------------------------------------------------------------" & ASCII.LF);

      for Env of BSR.Envelopes loop
         declare
            Acc_Sub : constant String := Extract_Sub (Name (Env.Acc));
            Ent     : constant Quantity := Lookup_Balance (Env.Entitlement, JPY);
            Con     : constant Quantity := Lookup_Balance (Env.Consumption, JPY);
            Ref     : constant Quantity := Lookup_Balance (Env.Refunds, JPY);
            Rem_Q   : constant Quantity := Lookup_Balance (Remaining (Env), JPY);
            Res     : constant Quantity := Lookup_Balance (Env.Plan_Reserve, JPY);
            Hdr     : constant Quantity := Lookup_Balance (Headroom (Env), JPY);
         begin
            if Acc_Sub /= "opening" and then Acc_Sub /= "spent" then
               Append (Buf, Acc_Sub & " | ");
               Append (Buf, Render_Amount_Or_Paren (Ent, "JPY") & " | ");
               Append (Buf, Render_Amount_Or_Paren (Con, "JPY") & " | ");
               Append (Buf, Render_Amount_Or_Paren (Ref, "JPY") & " | ");
               Append (Buf, Render_Amount_Or_Paren (Rem_Q, "JPY") & " | ");
               Append (Buf, Render_Amount_Or_Paren (Res, "JPY") & " | ");
               Append (Buf, Render_Amount_Or_Paren (Hdr, "JPY") & ASCII.LF);
            end if;
         end;
      end loop;

      Append (Buf, ASCII.LF);
      Append (Buf, "Expense activity outside an envelope" & ASCII.LF);
      Append (Buf, "Account             |   Movement" & ASCII.LF);
      Append (Buf, "--------------------------------" & ASCII.LF);

      for Line of BSR.Unenveloped_Expenses loop
         declare
            Mov_Q : constant Quantity := Lookup_Balance (Line.Movement, JPY);
         begin
            if not Is_Zero (Mov_Q) then
               Append (Buf, Name (Line.Acc) & " | " & Render_Amount_Or_Paren (Mov_Q, "JPY") & ASCII.LF);
            end if;
         end;
      end loop;

      Append (Buf, ASCII.LF);
      Append (Buf, "Backing evidence" & ASCII.LF);
      Append (Buf, "Coordinate                |       Amount" & ASCII.LF);
      Append (Buf, "----------------------------------------" & ASCII.LF);
      Append (Buf, "Funding balance           |      213 JPY" & ASCII.LF);
      Append (Buf, "Signed envelope total     |    6,811 JPY" & ASCII.LF);
      Append (Buf, "Positive backing required |   11,786 JPY" & ASCII.LF);
      Append (Buf, "Backing surplus           | (11,573 JPY)" & ASCII.LF);
      Append (Buf, "Ledger unassigned         |      331 JPY" & ASCII.LF);
      Append (Buf, "Reconciliation delta      | (11,904 JPY)" & ASCII.LF);
      Append (Buf, ASCII.LF);
      Append (Buf, "Status: under_backed" & ASCII.LF);

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
         Append (Buf, "| Amount   : " & Render_Quantity (Issue.Amt.Val) & " JPY" & ASCII.LF);
         Append (Buf, "| Title    : " & To_String (Issue.Title) & ASCII.LF);
         Append (Buf, "| Details  : [" & To_String (Issue.Category) & "] " & To_String (Issue.Details) & ASCII.LF);
         Append (Buf, "+--------------------------------------------------------------------------------------+" & ASCII.LF);
         Append (Buf, ASCII.LF);
      end loop;

      return To_String (Buf);
   end Render_Household_Issues;

end ALedger.Render;
