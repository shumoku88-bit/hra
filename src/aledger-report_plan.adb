with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

package body ALedger.Report_Plan is

   function Resolve_Closed_Boundary
     (Boundary    : ALedger.Report_Config.Date_Boundary;
      Latest_Date : String;
      Result      : out Unbounded_String) return Boolean
   is
      use ALedger.Report_Config;
   begin
      case Boundary.Kind is
         when Latest =>
            Result := To_Unbounded_String (Latest_Date);
            return True;
         when Exact_Date =>
            Result := Boundary.Date;
            return True;
         when Beginning =>
            Result := Null_Unbounded_String;
            return False;
      end case;
   end Resolve_Closed_Boundary;

   function Journal_Beginning_Through
     (L            : Ledger.Ledger;
      Through_Date : String) return String
   is
      Cursor : Transaction_Vectors.Cursor := L.Transactions.First;
      Found  : Boolean := False;
      First  : Unbounded_String := To_Unbounded_String (Through_Date);
   begin
      while Transaction_Vectors.Has_Element (Cursor) loop
         declare
            Tx      : constant Transaction := Transaction_Vectors.Element (Cursor);
            Tx_Date : constant String := To_String (Tx.Date_Text);
         begin
            if Tx_Date <= Through_Date
              and then (not Found or else Tx_Date < To_String (First))
            then
               First := To_Unbounded_String (Tx_Date);
               Found := True;
            end if;
         end;
         Transaction_Vectors.Next (Cursor);
      end loop;

      return To_String (First);
   end Journal_Beginning_Through;

   function Resolve_Range
     (Spec        : ALedger.Report_Config.Range_Spec;
      Latest_Date : String;
      L           : Ledger.Ledger;
      Result      : out Resolved_Range) return Boolean
   is
      use ALedger.Report_Config;
      Through : Unbounded_String;
      Start   : Unbounded_String;
   begin
      if not Resolve_Closed_Boundary (Spec.Through, Latest_Date, Through) then
         return False;
      end if;

      if Spec.From.Kind = Beginning then
         Start := To_Unbounded_String
           (Journal_Beginning_Through (L, To_String (Through)));
      elsif not Resolve_Closed_Boundary (Spec.From, Latest_Date, Start) then
         return False;
      end if;

      if To_String (Start) > To_String (Through) then
         return False;
      end if;

      Result :=
        (From_Date    => Start,
         Through_Date => Through);
      return True;
   end Resolve_Range;

   function Resolve
     (Latest_Date : String;
      L           : Ledger.Ledger;
      Plan        : ALedger.Report_Config.Report_Plan;
      Result      : out Resolved_Report_Plan;
      Status      : out Resolve_Status) return Boolean
   is
      Resolved : Resolved_Report_Plan;
   begin
      if not Resolve_Closed_Boundary
        (Plan.Trial_Balance.Value,
         Latest_Date,
         Resolved.Trial_Balance_As_Of)
      then
         Status := Invalid_Trial_Balance_Boundary;
         return False;
      end if;

      if not Resolve_Closed_Boundary
        (Plan.Balance_Sheet.Value,
         Latest_Date,
         Resolved.Balance_Sheet_As_Of)
      then
         Status := Invalid_Balance_Sheet_Boundary;
         return False;
      end if;

      if not Resolve_Range
        (Plan.Profit_And_Loss,
         Latest_Date,
         L,
         Resolved.Profit_And_Loss)
      then
         Status := Invalid_Profit_And_Loss_Range;
         return False;
      end if;

      if not Resolve_Range
        (Plan.Daily_Flow,
         Latest_Date,
         L,
         Resolved.Daily_Flow)
      then
         Status := Invalid_Daily_Flow_Range;
         return False;
      end if;

      if not Resolve_Range
        (Plan.Monthly_Accounts,
         Latest_Date,
         L,
         Resolved.Monthly_Accounts)
      then
         Status := Invalid_Monthly_Accounts_Range;
         return False;
      end if;

      if not Resolve_Closed_Boundary
        (Plan.Recent_Transactions.Through,
         Latest_Date,
         Resolved.Recent_Transactions_Through)
      then
         Status := Invalid_Recent_Transactions_Boundary;
         return False;
      end if;

      Resolved.Recent_Transactions_Count := Plan.Recent_Transactions.Count;
      Result := Resolved;
      Status := Success;
      return True;
   end Resolve;

end ALedger.Report_Plan;
