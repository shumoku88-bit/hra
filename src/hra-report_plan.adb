package body HRA.Report_Plan is

   use type HRA.Dates.Date;
   use type HRA.Report_Config.Range_Kind;

   type Range_Resolve_Status is
     (Range_Success,
      Range_Invalid,
      Range_Current_Cycle_Context_Required,
      Range_Observation_Outside_Current_Cycle);

   type Current_Cycle_Context (Available : Boolean := False) is record
      case Available is
         when True =>
            Period : HRA.Dates.Half_Open_Period;
         when False =>
            null;
      end case;
   end record;

   function Resolve_Closed_Boundary
     (Boundary    : HRA.Report_Config.Date_Boundary;
      Latest_Date : HRA.Dates.Date;
      Result      : out HRA.Dates.Date) return Boolean
   is
      use HRA.Report_Config;
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
      Through_Date : HRA.Dates.Date) return HRA.Dates.Date
   is
      Cursor : Transaction_Vectors.Cursor := L.Transactions.First;
      Found  : Boolean := False;
      First  : HRA.Dates.Date := Through_Date;
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
     (Spec          : HRA.Report_Config.Range_Spec;
      Latest_Date   : HRA.Dates.Date;
      L             : Ledger.Ledger;
      Cycle_Context : Current_Cycle_Context;
      Result        : out HRA.Dates.Closed_Period;
      Status        : out Range_Resolve_Status) return Boolean
   is
      use HRA.Report_Config;
      Through : HRA.Dates.Date;
      Start   : HRA.Dates.Date;
   begin
      case Spec.Kind is
         when Current_Cycle_To_Date =>
            if not Cycle_Context.Available then
               Status := Range_Current_Cycle_Context_Required;
               return False;
            elsif not HRA.Dates.Contains
              (Cycle_Context.Period, Latest_Date)
            then
               Status := Range_Observation_Outside_Current_Cycle;
               return False;
            end if;

            if HRA.Dates.Make_Closed_Period
              (HRA.Dates.First (Cycle_Context.Period), Latest_Date, Result)
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

            if HRA.Dates.Make_Closed_Period (Start, Through, Result) then
               Status := Range_Success;
               return True;
            end if;

            Status := Range_Invalid;
            return False;
      end case;
   end Resolve_Range;

   function Needs_Current_Cycle
     (Plan : HRA.Report_Config.Report_Plan) return Boolean is
   begin
      return
        Plan.Profit_And_Loss.Kind = HRA.Report_Config.Current_Cycle_To_Date
        or else Plan.Daily_Flow.Kind = HRA.Report_Config.Current_Cycle_To_Date;
   end Needs_Current_Cycle;

   function Resolve_Internal
     (Latest_Date   : HRA.Dates.Date;
      L             : Ledger.Ledger;
      Cycle_Context : Current_Cycle_Context;
      Plan          : HRA.Report_Config.Report_Plan;
      Result        : out Resolved_Report_Plan;
      Status        : out Resolve_Status) return Boolean
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
         Cycle_Context,
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
         Cycle_Context,
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

      if Plan.Monthly_Accounts.Kind /= HRA.Report_Config.Explicit_Range
        or else not Resolve_Range
          (Plan.Monthly_Accounts,
           Latest_Date,
           L,
           (Available => False),
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
     (Latest_Date : HRA.Dates.Date;
      L           : Ledger.Ledger;
      Plan        : HRA.Report_Config.Report_Plan;
      Result      : out Resolved_Report_Plan;
      Status      : out Resolve_Status) return Boolean
   is
      No_Cycle : constant Current_Cycle_Context := (Available => False);
   begin
      if Needs_Current_Cycle (Plan) then
         Status := Current_Cycle_Context_Required;
         return False;
      end if;

      return Resolve_Internal
        (Latest_Date,
         L,
         No_Cycle,
         Plan,
         Result,
         Status);
   end Resolve;

   function Resolve_With_Current_Cycle
     (Latest_Date   : HRA.Dates.Date;
      L             : Ledger.Ledger;
      Current_Cycle : HRA.Dates.Half_Open_Period;
      Plan          : HRA.Report_Config.Report_Plan;
      Result        : out Resolved_Report_Plan;
      Status        : out Resolve_Status) return Boolean
   is
      Cycle : constant Current_Cycle_Context :=
        (Available => True, Period => Current_Cycle);
   begin
      return Resolve_Internal
        (Latest_Date,
         L,
         Cycle,
         Plan,
         Result,
         Status);
   end Resolve_With_Current_Cycle;

end HRA.Report_Plan;
