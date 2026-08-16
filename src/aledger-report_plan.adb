package body ALedger.Report_Plan is

   use type ALedger.Dates.Date;
   use type ALedger.Report_Config.Range_Kind;

   type Range_Resolve_Status is
     (Range_Success,
      Range_Invalid,
      Range_Current_Cycle_Context_Required,
      Range_Observation_Outside_Current_Cycle);

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
     (Spec              : ALedger.Report_Config.Range_Spec;
      Latest_Date       : ALedger.Dates.Date;
      L                 : Ledger.Ledger;
      Has_Current_Cycle : Boolean;
      Current_Cycle     : ALedger.Dates.Half_Open_Period;
      Result            : out ALedger.Dates.Closed_Period;
      Status            : out Range_Resolve_Status) return Boolean
   is
      use ALedger.Report_Config;
      Through : ALedger.Dates.Date;
      Start   : ALedger.Dates.Date;
   begin
      case Spec.Kind is
         when Current_Cycle_To_Date =>
            if not Has_Current_Cycle then
               Status := Range_Current_Cycle_Context_Required;
               return False;
            elsif not ALedger.Dates.Contains (Current_Cycle, Latest_Date) then
               Status := Range_Observation_Outside_Current_Cycle;
               return False;
            end if;

            if ALedger.Dates.Make_Closed_Period
              (ALedger.Dates.First (Current_Cycle), Latest_Date, Result)
            then
               Status := Range_Success;
               return True;
            end if;

            Status := Range_Invalid;
            return False;

         when Explicit_Range =>
            if not Resolve_Closed_Boundary
              (Spec.Through, Latest_Date, Through)
            then
               Status := Range_Invalid;
               return False;
            end if;

            if Spec.From.Kind = Beginning then
               Start := Journal_Beginning_Through (L, Through);
            elsif not Resolve_Closed_Boundary
              (Spec.From, Latest_Date, Start)
            then
               Status := Range_Invalid;
               return False;
            end if;

            if ALedger.Dates.Make_Closed_Period (Start, Through, Result) then
               Status := Range_Success;
               return True;
            end if;

            Status := Range_Invalid;
            return False;
      end case;
   end Resolve_Range;

   function Needs_Current_Cycle
     (Plan : ALedger.Report_Config.Report_Plan) return Boolean is
   begin
      return
        Plan.Profit_And_Loss.Kind = ALedger.Report_Config.Current_Cycle_To_Date
        or else Plan.Daily_Flow.Kind = ALedger.Report_Config.Current_Cycle_To_Date;
   end Needs_Current_Cycle;

   function Resolve_Internal
     (Latest_Date       : ALedger.Dates.Date;
      L                 : Ledger.Ledger;
      Has_Current_Cycle : Boolean;
      Current_Cycle     : ALedger.Dates.Half_Open_Period;
      Plan              : ALedger.Report_Config.Report_Plan;
      Result            : out Resolved_Report_Plan;
      Status            : out Resolve_Status) return Boolean
   is
      Resolved     : Resolved_Report_Plan;
      Range_Status : Range_Resolve_Status;
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
         Has_Current_Cycle,
         Current_Cycle,
         Resolved.Profit_And_Loss,
         Range_Status)
      then
         case Range_Status is
            when Range_Current_Cycle_Context_Required =>
               Status := Current_Cycle_Context_Required;
            when Range_Observation_Outside_Current_Cycle =>
               Status := Current_Cycle_Observation_Outside_Period;
            when Range_Invalid | Range_Success =>
               Status := Invalid_Profit_And_Loss_Range;
         end case;
         return False;
      end if;

      if not Resolve_Range
        (Plan.Daily_Flow,
         Latest_Date,
         L,
         Has_Current_Cycle,
         Current_Cycle,
         Resolved.Daily_Flow,
         Range_Status)
      then
         case Range_Status is
            when Range_Current_Cycle_Context_Required =>
               Status := Current_Cycle_Context_Required;
            when Range_Observation_Outside_Current_Cycle =>
               Status := Current_Cycle_Observation_Outside_Period;
            when Range_Invalid | Range_Success =>
               Status := Invalid_Daily_Flow_Range;
         end case;
         return False;
      end if;

      if Plan.Monthly_Accounts.Kind /= ALedger.Report_Config.Explicit_Range
        or else not Resolve_Range
          (Plan.Monthly_Accounts,
           Latest_Date,
           L,
           False,
           Current_Cycle,
           Resolved.Monthly_Accounts,
           Range_Status)
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
   end Resolve_Internal;

   function Resolve
     (Latest_Date : ALedger.Dates.Date;
      L           : Ledger.Ledger;
      Plan        : ALedger.Report_Config.Report_Plan;
      Result      : out Resolved_Report_Plan;
      Status      : out Resolve_Status) return Boolean
   is
      No_Cycle : ALedger.Dates.Half_Open_Period;
   begin
      if Needs_Current_Cycle (Plan) then
         Status := Current_Cycle_Context_Required;
         return False;
      end if;

      return Resolve_Internal
        (Latest_Date,
         L,
         False,
         No_Cycle,
         Plan,
         Result,
         Status);
   end Resolve;

   function Resolve_With_Current_Cycle
     (Latest_Date   : ALedger.Dates.Date;
      L             : Ledger.Ledger;
      Current_Cycle : ALedger.Dates.Half_Open_Period;
      Plan          : ALedger.Report_Config.Report_Plan;
      Result        : out Resolved_Report_Plan;
      Status        : out Resolve_Status) return Boolean is
   begin
      return Resolve_Internal
        (Latest_Date,
         L,
         True,
         Current_Cycle,
         Plan,
         Result,
         Status);
   end Resolve_With_Current_Cycle;

end ALedger.Report_Plan;
