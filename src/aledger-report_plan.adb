package body ALedger.Report_Plan is

   use type ALedger.Dates.Date;

   function Resolve_Closed_Boundary
     (Boundary    : ALedger.Report_Config.Date_Boundary;
      Latest_Date : ALedger.Dates.Date;
      Result      : out ALedger.Dates.Date) return Boolean
   is
      use ALedger.Report_Config;
   begin
      case Boundary.Kind is
         when Latest =>
            Result := Latest_Date;
            return True;
         when Exact_Date =>
            Result := Boundary.Value;
            return True;
         when Beginning =>
            return False;
      end case;
   end Resolve_Closed_Boundary;

   function Journal_Beginning_Through
     (L            : Ledger.Ledger;
      Through_Date : ALedger.Dates.Date) return ALedger.Dates.Date
   is
      Cursor : Transaction_Vectors.Cursor := L.Transactions.First;
      Found  : Boolean := False;
      First  : ALedger.Dates.Date := Through_Date;
   begin
      while Transaction_Vectors.Has_Element (Cursor) loop
         declare
            Tx : constant Transaction := Transaction_Vectors.Element (Cursor);
         begin
            if Tx.Date <= Through_Date
              and then (not Found or else Tx.Date < First)
            then
               First := Tx.Date;
               Found := True;
            end if;
         end;
         Transaction_Vectors.Next (Cursor);
      end loop;

      return First;
   end Journal_Beginning_Through;

   function Resolve_Range
     (Spec        : ALedger.Report_Config.Range_Spec;
      Latest_Date : ALedger.Dates.Date;
      L           : Ledger.Ledger;
      Result      : out ALedger.Dates.Closed_Period) return Boolean
   is
      use ALedger.Report_Config;
      Through : ALedger.Dates.Date;
      Start   : ALedger.Dates.Date;
   begin
      if not Resolve_Closed_Boundary (Spec.Through, Latest_Date, Through) then
         return False;
      end if;

      if Spec.From.Kind = Beginning then
         Start := Journal_Beginning_Through (L, Through);
      elsif not Resolve_Closed_Boundary (Spec.From, Latest_Date, Start) then
         return False;
      end if;

      return ALedger.Dates.Make_Closed_Period (Start, Through, Result);
   end Resolve_Range;

   function Resolve
     (Latest_Date : ALedger.Dates.Date;
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
