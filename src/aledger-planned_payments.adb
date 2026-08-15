with Ada.Containers.Indefinite_Vectors;
with Ada.Strings;             use Ada.Strings;
with Ada.Strings.Fixed;       use Ada.Strings.Fixed;
with ALedger.Journal_Evidence; use ALedger.Journal_Evidence;

package body ALedger.Planned_Payments is

   use type ALedger.Plan.Plan_Id;
   use type ALedger.Money.Quantity;
   use type ALedger.Account.Account_Type;

   type Admitted_Plan is record
      ID               : ALedger.Plan.Plan_Id;
      Tx               : ALedger.Ledger.Transaction;
      Has_Cancellation : Boolean := False;
      Cancelled_On     : Unbounded_String;
      Has_Supersession : Boolean := False;
      Superseded_On    : Unbounded_String;
      Superseded_By    : ALedger.Plan.Plan_Id;
   end record;

   package Admitted_Plan_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Admitted_Plan);

   type Completion is record
      ID   : ALedger.Plan.Plan_Id;
      Date : Unbounded_String;
   end record;

   package Completion_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Completion);

   function Is_Leap (Year : Positive) return Boolean is
     (Year mod 400 = 0 or else (Year mod 4 = 0 and then Year mod 100 /= 0));

   function Valid_Date (Text : String) return Boolean is
      Year, Month, Day, Max_Day : Natural;
   begin
      if Text'Length /= 10
        or else Text (Text'First + 4) /= '-'
        or else Text (Text'First + 7) /= '-'
      then
         return False;
      end if;

      for Offset in 0 .. 9 loop
         if Offset /= 4 and then Offset /= 7
           and then Text (Text'First + Offset) not in '0' .. '9'
         then
            return False;
         end if;
      end loop;

      Year  := Natural'Value (Text (Text'First .. Text'First + 3));
      Month := Natural'Value (Text (Text'First + 5 .. Text'First + 6));
      Day   := Natural'Value (Text (Text'First + 8 .. Text'First + 9));
      if Year = 0 or else Month not in 1 .. 12 then
         return False;
      end if;

      Max_Day :=
        (case Month is
            when 2 => (if Is_Leap (Year) then 29 else 28),
            when 4 | 6 | 9 | 11 => 30,
            when others => 31);
      return Day in 1 .. Max_Day;
   exception
      when Constraint_Error =>
         return False;
   end Valid_Date;

   procedure Find_Metadata
     (Source : Transaction_Source;
      Key    : String;
      Count  : out Natural;
      Entry  : out Metadata_Entry)
   is
   begin
      Count := 0;
      Entry :=
        (Key         => Null_Unbounded_String,
         Value       => Null_Unbounded_String,
         Line_Number => Source.Header_Line);
      for Candidate of Source.Metadata loop
         if To_String (Candidate.Key) = Key then
            Count := Count + 1;
            if Count = 1 then
               Entry := Candidate;
            end if;
         end if;
      end loop;
   end Find_Metadata;

   function Observe
     (Plan_Ledger        : ALedger.Ledger.Ledger;
      Plan_Source_Text   : String;
      Actual_Ledger      : ALedger.Ledger.Ledger;
      Actual_Source_Text : String;
      Registry           : ALedger.Account.Account_Registry;
      As_Of_Date         : String;
      Result             : out Observation;
      Diag               : out Admission_Diagnostic) return Boolean
   is
      Plan_Evidence   : Journal_Evidence;
      Actual_Evidence : Journal_Evidence;
      Evidence_Diag   : Evidence_Diagnostic;
      Plans           : Admitted_Plan_Vectors.Vector;
      Completions     : Completion_Vectors.Vector;
      Output          : Observation;

      procedure Fail
        (Status  : Admission_Status;
         Line    : Natural;
         Plan_ID : String;
         Message : String)
      is
      begin
         Diag :=
           (Status      => Status,
            Line_Number => Line,
            Plan_Id     => To_Unbounded_String (Plan_ID),
            Message     => To_Unbounded_String (Message));
      end Fail;

      function Find_Plan_Index (ID : ALedger.Plan.Plan_Id) return Natural is
      begin
         for I in 1 .. Natural (Plans.Length) loop
            if Plans.Element (I).ID = ID then
               return I;
            end if;
         end loop;
         return 0;
      end Find_Plan_Index;

      function Completion_Exists (ID : ALedger.Plan.Plan_Id) return Boolean is
      begin
         for Item of Completions loop
            if Item.ID = ID then
               return True;
            end if;
         end loop;
         return False;
      end Completion_Exists;

      function Completed_As_Of (ID : ALedger.Plan.Plan_Id) return Boolean is
      begin
         for Item of Completions loop
            if Item.ID = ID and then To_String (Item.Date) <= As_Of_Date then
               return True;
            end if;
         end loop;
         return False;
      end Completed_As_Of;

      function Retired_As_Of (P : Admitted_Plan) return Boolean is
      begin
         return
           (P.Has_Cancellation and then To_String (P.Cancelled_On) <= As_Of_Date)
           or else
           (P.Has_Supersession and then To_String (P.Superseded_On) <= As_Of_Date);
      end Retired_As_Of;

      function Supersession_Cycle_From (Start : Positive) return Boolean is
         Current : ALedger.Plan.Plan_Id := Plans.Element (Start).ID;
      begin
         for Step in 1 .. Natural (Plans.Length) + 1 loop
            declare
               Index : constant Natural := Find_Plan_Index (Current);
            begin
               if Index = 0 or else not Plans.Element (Index).Has_Supersession then
                  return False;
               end if;

               Current := Plans.Element (Index).Superseded_By;
               if Current = Plans.Element (Start).ID then
                  return True;
               end if;
            end;
         end loop;
         return True;
      end Supersession_Cycle_From;

      function Project_Open_Plan (P : Admitted_Plan) return Boolean is
         All_Outgoing       : Boolean := True;
         All_Incoming       : Boolean := True;
         All_Asset_Target   : Boolean := True;
         Has_Asset_Source   : Boolean := False;
         Has_Payment_Target : Boolean := False;
         Has_Income_Source  : Boolean := False;
         Has_Asset_Income   : Boolean := False;
         Has_Asset_Negative : Boolean := False;
         Has_Asset_Positive : Boolean := False;
      begin
         for Posting of P.Tx.Postings loop
            declare
               Category : ALedger.Account.Account_Type;
               Known    : constant Boolean :=
                 ALedger.Account.Account_Type_For
                   (Registry, Posting.Acc, Category);
               Q : constant ALedger.Money.Quantity := Posting.Amt.Val;
            begin
               if not Known then
                  Fail
                    (Undeclared_Plan_Account,
                     0,
                     ALedger.Plan.Text (P.ID),
                     "Plan Posting references an undeclared Account: " &
                       ALedger.Account.Name (Posting.Acc));
                  return False;
               end if;

               if Category = ALedger.Account.Asset and then Q < 0.0 then
                  Has_Asset_Source := True;
                  Has_Asset_Negative := True;
               elsif (Category = ALedger.Account.Expense
                      or else Category = ALedger.Account.Liability)
                 and then Q > 0.0
               then
                  Has_Payment_Target := True;
               else
                  All_Outgoing := False;
               end if;

               if Category = ALedger.Account.Income and then Q < 0.0 then
                  Has_Income_Source := True;
               elsif Category = ALedger.Account.Asset and then Q > 0.0 then
                  Has_Asset_Income := True;
                  Has_Asset_Positive := True;
               else
                  All_Incoming := False;
               end if;

               if Category = ALedger.Account.Asset and then Q < 0.0 then
                  Has_Asset_Negative := True;
               elsif Category = ALedger.Account.Asset and then Q > 0.0 then
                  Has_Asset_Positive := True;
               else
                  All_Asset_Target := False;
               end if;
            end;
         end loop;

         if All_Incoming and then Has_Income_Source and then Has_Asset_Income then
            return True;
         elsif All_Asset_Target and then Has_Asset_Negative and then Has_Asset_Positive then
            --  Explicit savings/investment target. It is a valid open Plan but
            --  not an outgoing payment, so this report does not project it.
            return True;
         elsif not (All_Outgoing and then Has_Asset_Source and then Has_Payment_Target) then
            Fail
              (Unsupported_Plan_Role_Flow,
               0,
               ALedger.Plan.Text (P.ID),
               "Plan Posting roles do not form a supported incoming, asset-target, or outgoing flow");
            return False;
         end if;

         if Natural (P.Tx.Postings.Length) /= 2 then
            Fail
              (Plan_Report_Requires_Binary_Outgoing,
               0,
               ALedger.Plan.Text (P.ID),
               "Planned Payments currently requires one Asset source and one Expense/Liability destination");
            return False;
         end if;

         declare
            Source_Acc      : ALedger.Account.Account;
            Destination_Acc : ALedger.Account.Account;
            Payment_Amount  : ALedger.Money.Amount;
            Source_Found    : Boolean := False;
            Target_Found    : Boolean := False;
         begin
            for Posting of P.Tx.Postings loop
               declare
                  Category : ALedger.Account.Account_Type;
                  Known    : constant Boolean :=
                    ALedger.Account.Account_Type_For
                      (Registry, Posting.Acc, Category);
               begin
                  if not Known then
                     raise Program_Error with "registry changed during planned payment projection";
                  elsif Category = ALedger.Account.Asset and then Posting.Amt.Val < 0.0 then
                     Source_Acc := Posting.Acc;
                     Source_Found := True;
                  elsif (Category = ALedger.Account.Expense
                         or else Category = ALedger.Account.Liability)
                    and then Posting.Amt.Val > 0.0
                  then
                     Destination_Acc := Posting.Acc;
                     Payment_Amount := Posting.Amt;
                     Target_Found := True;
                  end if;
               end;
            end loop;

            if not Source_Found or else not Target_Found then
               Fail
                 (Unsupported_Plan_Role_Flow,
                  0,
                  ALedger.Plan.Text (P.ID),
                  "binary outgoing Plan is missing its source or destination");
               return False;
            end if;

            Output.Payments.Append
              (Planned_Payment'
                 (ID          => P.ID,
                  Due_Date    => P.Tx.Date_Text,
                  Memo        => P.Tx.Code_Or_Payee,
                  Amt         => Payment_Amount,
                  Source      => Source_Acc,
                  Destination => Destination_Acc,
                  Timing      =>
                    (if To_String (P.Tx.Date_Text) < As_Of_Date then Overdue
                     elsif To_String (P.Tx.Date_Text) = As_Of_Date then Due_Today
                     else Upcoming)));
         end;

         return True;
      end Project_Open_Plan;

   begin
      Result := Output;
      Diag :=
        (Status      => Success,
         Line_Number => 0,
         Plan_Id     => Null_Unbounded_String,
         Message     => Null_Unbounded_String);

      if not Extract (Plan_Source_Text, Plan_Ledger, Plan_Evidence, Evidence_Diag) then
         Fail
           (Plan_Source_Evidence_Error,
            Evidence_Diag.Line_Number,
            "",
            To_String (Evidence_Diag.Message));
         return False;
      end if;

      if not Extract (Actual_Source_Text, Actual_Ledger, Actual_Evidence, Evidence_Diag) then
         Fail
           (Actual_Source_Evidence_Error,
            Evidence_Diag.Line_Number,
            "",
            To_String (Evidence_Diag.Message));
         return False;
      end if;

      --  Admit durable Plan identity and narrow lifecycle metadata while
      --  retaining the whole accounting Transaction.
      for I in 1 .. Natural (Plan_Ledger.Transactions.Length) loop
         declare
            Source : constant Transaction_Source := Plan_Evidence.Transactions.Element (I);
            Tx     : constant ALedger.Ledger.Transaction := Plan_Ledger.Transactions.Element (I);
            Plan_Count, Cancel_Count, Sup_On_Count, Sup_By_Count : Natural;
            Plan_Meta, Cancel_Meta, Sup_On_Meta, Sup_By_Meta : Metadata_Entry;
            PID        : ALedger.Plan.Plan_Id;
            PID_Status : ALedger.Plan.Plan_Id_Status;
            P          : Admitted_Plan;
         begin
            Find_Metadata (Source, "plan-id", Plan_Count, Plan_Meta);
            if Plan_Count = 0 then
               Fail (Missing_Plan_Id, Source.Header_Line, "", "Plan transaction is missing plan-id metadata");
               return False;
            elsif Plan_Count > 1 then
               Fail (Duplicate_Plan_Metadata, Plan_Meta.Line_Number, To_String (Plan_Meta.Value), "Plan transaction repeats plan-id metadata");
               return False;
            elsif not ALedger.Plan.Create_Plan_Id
              (To_String (Plan_Meta.Value), PID, PID_Status)
            then
               Fail (Invalid_Plan_Id, Plan_Meta.Line_Number, To_String (Plan_Meta.Value), "invalid plan-id");
               return False;
            end if;

            for Existing of Plans loop
               if Existing.ID = PID then
                  Fail (Duplicate_Plan_Id, Plan_Meta.Line_Number, ALedger.Plan.Text (PID), "plan-id identifies more than one transaction");
                  return False;
               end if;
            end loop;

            Find_Metadata (Source, "cancelled-on", Cancel_Count, Cancel_Meta);
            Find_Metadata (Source, "superseded-on", Sup_On_Count, Sup_On_Meta);
            Find_Metadata (Source, "superseded-by", Sup_By_Count, Sup_By_Meta);
            if Cancel_Count > 1 or else Sup_On_Count > 1 or else Sup_By_Count > 1 then
               Fail (Duplicate_Plan_Metadata, Source.Header_Line, ALedger.Plan.Text (PID), "Plan transaction repeats lifecycle metadata");
               return False;
            elsif Cancel_Count > 0 and then (Sup_On_Count > 0 or else Sup_By_Count > 0) then
               Fail (Invalid_Lifecycle_Metadata, Source.Header_Line, ALedger.Plan.Text (PID), "cancellation conflicts with supersession metadata");
               return False;
            elsif (Sup_On_Count = 0) /= (Sup_By_Count = 0) then
               Fail (Invalid_Lifecycle_Metadata, Source.Header_Line, ALedger.Plan.Text (PID), "supersession requires both superseded-on and superseded-by");
               return False;
            end if;

            P :=
              (ID               => PID,
               Tx               => Tx,
               Has_Cancellation => False,
               Cancelled_On     => Null_Unbounded_String,
               Has_Supersession => False,
               Superseded_On    => Null_Unbounded_String,
               Superseded_By    => ALedger.Plan.Null_Plan_Id);

            if Cancel_Count = 1 then
               if not Valid_Date (To_String (Cancel_Meta.Value)) then
                  Fail (Invalid_Lifecycle_Date, Cancel_Meta.Line_Number, ALedger.Plan.Text (PID), "invalid cancelled-on date");
                  return False;
               end if;
               P.Has_Cancellation := True;
               P.Cancelled_On := Cancel_Meta.Value;
            elsif Sup_On_Count = 1 then
               declare
                  Successor        : ALedger.Plan.Plan_Id;
                  Successor_Status : ALedger.Plan.Plan_Id_Status;
               begin
                  if not Valid_Date (To_String (Sup_On_Meta.Value)) then
                     Fail (Invalid_Lifecycle_Date, Sup_On_Meta.Line_Number, ALedger.Plan.Text (PID), "invalid superseded-on date");
                     return False;
                  elsif not ALedger.Plan.Create_Plan_Id
                    (To_String (Sup_By_Meta.Value), Successor, Successor_Status)
                  then
                     Fail (Invalid_Supersession_Target, Sup_By_Meta.Line_Number, ALedger.Plan.Text (PID), "invalid superseded-by plan-id");
                     return False;
                  elsif Successor = PID then
                     Fail (Invalid_Supersession_Target, Sup_By_Meta.Line_Number, ALedger.Plan.Text (PID), "Plan cannot supersede itself");
                     return False;
                  end if;

                  P.Has_Supersession := True;
                  P.Superseded_On := Sup_On_Meta.Value;
                  P.Superseded_By := Successor;
               end;
            end if;

            Plans.Append (P);
         end;
      end loop;

      for P of Plans loop
         if P.Has_Supersession and then Find_Plan_Index (P.Superseded_By) = 0 then
            Fail
              (Unknown_Supersession_Target,
               0,
               ALedger.Plan.Text (P.ID),
               "superseded-by references an unknown Plan: " & ALedger.Plan.Text (P.Superseded_By));
            return False;
         end if;
      end loop;

      for I in 1 .. Natural (Plans.Length) loop
         if Plans.Element (I).Has_Supersession and then Supersession_Cycle_From (I) then
            Fail (Supersession_Cycle, 0, ALedger.Plan.Text (Plans.Element (I).ID), "Plan supersession graph contains a cycle");
            return False;
         end if;
      end loop;

      --  Admit explicit Actual completion declarations. Future-dated Actuals
      --  are valid evidence but do not close a Plan before their transaction day.
      for I in 1 .. Natural (Actual_Ledger.Transactions.Length) loop
         declare
            Source : constant Transaction_Source := Actual_Evidence.Transactions.Element (I);
            Tx     : constant ALedger.Ledger.Transaction := Actual_Ledger.Transactions.Element (I);
            Count  : Natural;
            Meta   : Metadata_Entry;
         begin
            Find_Metadata (Source, "plan-id", Count, Meta);
            if Count > 1 then
               Fail (Duplicate_Plan_Metadata, Source.Header_Line, To_String (Meta.Value), "Actual transaction repeats plan-id completion metadata");
               return False;
            elsif Count = 1 then
               declare
                  PID        : ALedger.Plan.Plan_Id;
                  PID_Status : ALedger.Plan.Plan_Id_Status;
               begin
                  if not ALedger.Plan.Create_Plan_Id
                    (To_String (Meta.Value), PID, PID_Status)
                  then
                     Fail (Invalid_Actual_Plan_Id, Meta.Line_Number, To_String (Meta.Value), "Actual transaction carries an invalid plan-id");
                     return False;
                  elsif Find_Plan_Index (PID) = 0 then
                     Fail (Unknown_Completion_Plan, Meta.Line_Number, ALedger.Plan.Text (PID), "Actual completion references an unknown Plan");
                     return False;
                  elsif Completion_Exists (PID) then
                     Fail (Multiple_Completion_Actuals, Meta.Line_Number, ALedger.Plan.Text (PID), "Plan is completed by more than one Actual transaction");
                     return False;
                  end if;

                  Completions.Append
                    (Completion'(ID => PID, Date => Tx.Date_Text));
               end;
            end if;
         end;
      end loop;

      for P of Plans loop
         if not Retired_As_Of (P) and then not Completed_As_Of (P.ID) then
            if not Project_Open_Plan (P) then
               return False;
            end if;
         end if;
      end loop;

      Result := Output;
      return True;
   end Observe;

end ALedger.Planned_Payments;
