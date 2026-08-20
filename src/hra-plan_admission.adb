with HRA.Journal_Evidence; use HRA.Journal_Evidence;

package body HRA.Plan_Admission is

   use type HRA.Plan.Plan_Id;

   function Empty_Observation return Plan_Observation is
      Result : Plan_Observation;
   begin
      Result.Value := HRA.Ledger.Empty_Ledger;
      Result.In_Order.Clear;
      Result.Ids := HRA.Plan.Empty_Plan_Id_Universe;
      return Result;
   end Empty_Observation;

   function Evidence_Of
     (Observation : Plan_Observation)
      return HRA.Journal_Evidence.Journal_Evidence
   is
      Result : HRA.Journal_Evidence.Journal_Evidence;
   begin
      Result.Transactions.Clear;
      for Item of Observation.In_Order loop
         Result.Transactions.Append (Item.Source);
      end loop;
      return Result;
   end Evidence_Of;

   procedure Find_Metadata
     (Source      : Transaction_Source;
      Key         : String;
      Count       : out Natural;
      Found_Value : out Metadata_Entry)
   is
   begin
      Count := 0;
      Found_Value :=
        (Key         => Null_Unbounded_String,
         Value       => Null_Unbounded_String,
         Line_Number => Source.Header_Line);

      for Candidate of Source.Metadata loop
         if To_String (Candidate.Key) = Key then
            Count := Count + 1;
            if Count = 1 then
               Found_Value := Candidate;
            end if;
         end if;
      end loop;
   end Find_Metadata;

   function Evidence_Aligns
     (L        : HRA.Ledger.Ledger;
      Evidence : HRA.Journal_Evidence.Journal_Evidence;
      Diag     : out Admission_Diagnostic) return Boolean
   is
   begin
      if Natural (Evidence.Transactions.Length) /=
         Natural (L.Transactions.Length)
      then
         Diag :=
           (Status      => Source_Evidence_Error,
            Line_Number => 0,
            Plan_Id     => Null_Unbounded_String,
            Message     => To_Unbounded_String
              ("Plan Journal evidence transaction count does not match Ledger"));
         return False;
      end if;

      for I in 1 .. Natural (L.Transactions.Length) loop
         declare
            Source : constant Transaction_Source := Evidence.Transactions.Element (I);
            Tx     : constant HRA.Ledger.Transaction := L.Transactions.Element (I);
         begin
            if To_String (Source.Date_Text) /= HRA.Dates.Image (Tx.Date)
              or else To_String (Source.Description) /= To_String (Tx.Code_Or_Payee)
            then
               Diag :=
                 (Status      => Source_Evidence_Error,
                  Line_Number => Source.Header_Line,
                  Plan_Id     => Null_Unbounded_String,
                  Message     => To_Unbounded_String
                    ("Plan Journal evidence does not align with Ledger"));
               return False;
            end if;
         end;
      end loop;

      return True;
   end Evidence_Aligns;

   function Admit
     (Plan_Ledger   : HRA.Ledger.Ledger;
      Plan_Evidence : HRA.Journal_Evidence.Journal_Evidence;
      Result        : out Plan_Observation;
      Diag          : out Admission_Diagnostic) return Boolean
   is
      Output : Plan_Observation := Empty_Observation;

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

      function Find_Plan_Index (ID : HRA.Plan.Plan_Id) return Natural is
      begin
         for I in 1 .. Natural (Output.In_Order.Length) loop
            if Output.In_Order.Element (I).ID = ID then
               return I;
            end if;
         end loop;
         return 0;
      end Find_Plan_Index;

      function Supersession_Cycle_From (Start : Positive) return Boolean is
         Start_Id : constant HRA.Plan.Plan_Id := Output.In_Order.Element (Start).ID;
         Current  : HRA.Plan.Plan_Id := Start_Id;
      begin
         for Step in 1 .. Natural (Output.In_Order.Length) + 1 loop
            pragma Unreferenced (Step);
            declare
               Index : constant Natural := Find_Plan_Index (Current);
            begin
               if Index = 0 then
                  return False;
               end if;

               declare
                  Item : constant Plan_Transaction_Entry :=
                    Output.In_Order.Element (Index);
               begin
                  if Item.Retirement.Kind /= Superseded then
                     return False;
                  end if;
                  Current := Item.Retirement.Successor;
                  if Current = Start_Id then
                     return True;
                  end if;
               end;
            end;
         end loop;
         return True;
      end Supersession_Cycle_From;

   begin
      Result := Output;
      Diag :=
        (Status      => Success,
         Line_Number => 0,
         Plan_Id     => Null_Unbounded_String,
         Message     => Null_Unbounded_String);

      if not Evidence_Aligns (Plan_Ledger, Plan_Evidence, Diag) then
         return False;
      end if;

      Output.Value := Plan_Ledger;

      for I in 1 .. Natural (Plan_Ledger.Transactions.Length) loop
         declare
            Source : constant Transaction_Source :=
              Plan_Evidence.Transactions.Element (I);
            Tx : constant HRA.Ledger.Transaction :=
              Plan_Ledger.Transactions.Element (I);
            Plan_Count, Cancel_Count, Sup_On_Count, Sup_By_Count : Natural;
            Plan_Meta, Cancel_Meta, Sup_On_Meta, Sup_By_Meta : Metadata_Entry;
            PID        : HRA.Plan.Plan_Id;
            PID_Status : HRA.Plan.Plan_Id_Status;
            Kind       : Retirement_Kind := Active;
            Retired_On : HRA.Dates.Date := Tx.Date;
            Successor  : HRA.Plan.Plan_Id;
         begin
            Find_Metadata (Source, "plan-id", Plan_Count, Plan_Meta);
            if Plan_Count = 0 then
               Fail
                 (Missing_Plan_Id,
                  Source.Header_Line,
                  "",
                  "Plan transaction is missing plan-id metadata");
               return False;
            elsif Plan_Count > 1 then
               Fail
                 (Duplicate_Plan_Metadata,
                  Plan_Meta.Line_Number,
                  To_String (Plan_Meta.Value),
                  "Plan transaction repeats plan-id metadata");
               return False;
            elsif not HRA.Plan.Create_Plan_Id
              (To_String (Plan_Meta.Value), PID, PID_Status)
            then
               Fail
                 (Invalid_Plan_Id,
                  Plan_Meta.Line_Number,
                  To_String (Plan_Meta.Value),
                  "invalid plan-id");
               return False;
            elsif HRA.Plan.Contains (Output.Ids, PID) then
               Fail
                 (Duplicate_Plan_Id,
                  Plan_Meta.Line_Number,
                  HRA.Plan.Text (PID),
                  "plan-id identifies more than one transaction");
               return False;
            end if;

            Successor := PID;
            Find_Metadata (Source, "cancelled-on", Cancel_Count, Cancel_Meta);
            Find_Metadata (Source, "superseded-on", Sup_On_Count, Sup_On_Meta);
            Find_Metadata (Source, "superseded-by", Sup_By_Count, Sup_By_Meta);

            if Cancel_Count > 1 or else Sup_On_Count > 1 or else Sup_By_Count > 1 then
               Fail
                 (Duplicate_Plan_Metadata,
                  Source.Header_Line,
                  HRA.Plan.Text (PID),
                  "Plan transaction repeats lifecycle metadata");
               return False;
            elsif Cancel_Count > 0 and then (Sup_On_Count > 0 or else Sup_By_Count > 0) then
               Fail
                 (Invalid_Lifecycle_Metadata,
                  Source.Header_Line,
                  HRA.Plan.Text (PID),
                  "cancellation conflicts with supersession metadata");
               return False;
            elsif (Sup_On_Count = 0) /= (Sup_By_Count = 0) then
               Fail
                 (Invalid_Lifecycle_Metadata,
                  Source.Header_Line,
                  HRA.Plan.Text (PID),
                  "supersession requires both superseded-on and superseded-by");
               return False;
            end if;

            if Cancel_Count = 1 then
               declare
                  Date_Status : HRA.Dates.Date_Status;
               begin
                  if not HRA.Dates.Parse
                    (To_String (Cancel_Meta.Value), Retired_On, Date_Status)
                  then
                     Fail
                       (Invalid_Lifecycle_Date,
                        Cancel_Meta.Line_Number,
                        HRA.Plan.Text (PID),
                        "invalid cancelled-on date");
                     return False;
                  end if;
                  Kind := Canceled;
               end;
            elsif Sup_On_Count = 1 then
               declare
                  Date_Status      : HRA.Dates.Date_Status;
                  Successor_Status : HRA.Plan.Plan_Id_Status;
               begin
                  if not HRA.Dates.Parse
                    (To_String (Sup_On_Meta.Value), Retired_On, Date_Status)
                  then
                     Fail
                       (Invalid_Lifecycle_Date,
                        Sup_On_Meta.Line_Number,
                        HRA.Plan.Text (PID),
                        "invalid superseded-on date");
                     return False;
                  elsif not HRA.Plan.Create_Plan_Id
                    (To_String (Sup_By_Meta.Value), Successor, Successor_Status)
                  then
                     Fail
                       (Invalid_Supersession_Target,
                        Sup_By_Meta.Line_Number,
                        HRA.Plan.Text (PID),
                        "invalid superseded-by plan-id");
                     return False;
                  elsif Successor = PID then
                     Fail
                       (Invalid_Supersession_Target,
                        Sup_By_Meta.Line_Number,
                        HRA.Plan.Text (PID),
                        "Plan cannot supersede itself");
                     return False;
                  end if;
                  Kind := Superseded;
               end;
            end if;

            HRA.Plan.Include (Output.Ids, PID);
            case Kind is
               when Active =>
                  Output.In_Order.Append
                    (Plan_Transaction_Entry'
                       (ID         => PID,
                        Tx         => Tx,
                        Source     => Source,
                        Retirement => (Kind => Active)));
               when Canceled =>
                  Output.In_Order.Append
                    (Plan_Transaction_Entry'
                       (ID         => PID,
                        Tx         => Tx,
                        Source     => Source,
                        Retirement =>
                          (Kind        => Canceled,
                           Canceled_On => Retired_On)));
               when Superseded =>
                  Output.In_Order.Append
                    (Plan_Transaction_Entry'
                       (ID         => PID,
                        Tx         => Tx,
                        Source     => Source,
                        Retirement =>
                          (Kind          => Superseded,
                           Superseded_On => Retired_On,
                           Successor     => Successor)));
            end case;
         end;
      end loop;

      for Item of Output.In_Order loop
         if Item.Retirement.Kind = Superseded
           and then Find_Plan_Index (Item.Retirement.Successor) = 0
         then
            Fail
              (Unknown_Supersession_Target,
               0,
               HRA.Plan.Text (Item.ID),
               "superseded-by references an unknown Plan: " &
               HRA.Plan.Text (Item.Retirement.Successor));
            return False;
         end if;
      end loop;

      for I in 1 .. Natural (Output.In_Order.Length) loop
         if Output.In_Order.Element (I).Retirement.Kind = Superseded
           and then Supersession_Cycle_From (I)
         then
            Fail
              (Supersession_Cycle,
               0,
               HRA.Plan.Text (Output.In_Order.Element (I).ID),
               "Plan supersession graph contains a cycle");
            return False;
         end if;
      end loop;

      Result := Output;
      return True;
   end Admit;

end HRA.Plan_Admission;
