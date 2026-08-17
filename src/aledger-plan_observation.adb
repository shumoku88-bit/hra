with ALedger.Journal_Evidence; use ALedger.Journal_Evidence;

package body ALedger.Plan_Observation is

   use type ALedger.Dates.Date;
   use type ALedger.Plan.Plan_Id;

   type Admitted_Plan is record
      ID               : ALedger.Plan.Plan_Id;
      Tx               : ALedger.Ledger.Transaction;
      Source           : Transaction_Source;
      Has_Cancellation : Boolean := False;
      Cancelled_On     : ALedger.Dates.Date;
      Has_Supersession : Boolean := False;
      Superseded_On    : ALedger.Dates.Date;
      Superseded_By    : ALedger.Plan.Plan_Id;
   end record;

   package Admitted_Plan_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Admitted_Plan);

   type Completion is record
      ID     : ALedger.Plan.Plan_Id;
      Date   : ALedger.Dates.Date;
      Tx     : ALedger.Ledger.Transaction;
      Source : Transaction_Source;
   end record;

   package Completion_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Completion);

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
     (L        : ALedger.Ledger.Ledger;
      Evidence : ALedger.Journal_Evidence.Journal_Evidence;
      Status   : Admission_Status;
      Diag     : out Admission_Diagnostic) return Boolean
   is
   begin
      if Natural (Evidence.Transactions.Length) /=
         Natural (L.Transactions.Length)
      then
         Diag :=
           (Status      => Status,
            Line_Number => 0,
            Plan_Id     => Null_Unbounded_String,
            Message     => To_Unbounded_String
              ("Journal evidence transaction count does not match admitted Ledger"));
         return False;
      end if;

      for I in 1 .. Natural (L.Transactions.Length) loop
         declare
            Source : constant Transaction_Source := Evidence.Transactions.Element (I);
            Tx     : constant ALedger.Ledger.Transaction := L.Transactions.Element (I);
            Where  : constant String :=
              (if Length (Source.Source_Path) = 0 then
                  ""
               else
                  " at " & To_String (Source.Source_Path) & ":" &
                  Positive'Image (Source.Header_Line));
         begin
            if To_String (Source.Date_Text) /= ALedger.Dates.Image (Tx.Date)
              or else To_String (Source.Description) /= To_String (Tx.Code_Or_Payee)
            then
               Diag :=
                 (Status      => Status,
                  Line_Number => Source.Header_Line,
                  Plan_Id     => Null_Unbounded_String,
                  Message     => To_Unbounded_String
                    ("Journal evidence does not align with admitted Ledger" & Where));
               return False;
            end if;
         end;
      end loop;

      return True;
   end Evidence_Aligns;

   function Admit_Plan_Identities
     (Plan_Ledger   : ALedger.Ledger.Ledger;
      Plan_Evidence : ALedger.Journal_Evidence.Journal_Evidence;
      Result        : out ALedger.Plan.Plan_Id_Universe;
      Diag          : out Admission_Diagnostic) return Boolean
   is
      Output : ALedger.Plan.Plan_Id_Universe :=
        ALedger.Plan.Empty_Plan_Id_Universe;
   begin
      Result := Output;
      Diag :=
        (Status      => Success,
         Line_Number => 0,
         Plan_Id     => Null_Unbounded_String,
         Message     => Null_Unbounded_String);

      if not Evidence_Aligns
        (Plan_Ledger, Plan_Evidence, Plan_Source_Evidence_Error, Diag)
      then
         return False;
      end if;

      for I in 1 .. Natural (Plan_Ledger.Transactions.Length) loop
         declare
            Source     : constant Transaction_Source :=
              Plan_Evidence.Transactions.Element (I);
            Plan_Count : Natural;
            Plan_Meta  : Metadata_Entry;
            PID        : ALedger.Plan.Plan_Id;
            PID_Status : ALedger.Plan.Plan_Id_Status;
         begin
            Find_Metadata (Source, "plan-id", Plan_Count, Plan_Meta);
            if Plan_Count = 0 then
               Diag :=
                 (Status      => Missing_Plan_Id,
                  Line_Number => Source.Header_Line,
                  Plan_Id     => Null_Unbounded_String,
                  Message     => To_Unbounded_String
                    ("Plan transaction is missing plan-id metadata"));
               return False;
            elsif Plan_Count > 1 then
               Diag :=
                 (Status      => Duplicate_Plan_Metadata,
                  Line_Number => Plan_Meta.Line_Number,
                  Plan_Id     => Plan_Meta.Value,
                  Message     => To_Unbounded_String
                    ("Plan transaction repeats plan-id metadata"));
               return False;
            elsif not ALedger.Plan.Create_Plan_Id
              (To_String (Plan_Meta.Value), PID, PID_Status)
            then
               Diag :=
                 (Status      => Invalid_Plan_Id,
                  Line_Number => Plan_Meta.Line_Number,
                  Plan_Id     => Plan_Meta.Value,
                  Message     => To_Unbounded_String ("invalid plan-id"));
               return False;
            end if;

            if ALedger.Plan.Contains (Output, PID) then
               Diag :=
                 (Status      => Duplicate_Plan_Id,
                  Line_Number => Plan_Meta.Line_Number,
                  Plan_Id     => To_Unbounded_String (ALedger.Plan.Text (PID)),
                  Message     => To_Unbounded_String
                    ("plan-id identifies more than one transaction"));
               return False;
            end if;

            ALedger.Plan.Include (Output, PID);
         end;
      end loop;

      Result := Output;
      return True;
   end Admit_Plan_Identities;

   function Admit_Plan_Identities
     (Plan_Ledger      : ALedger.Ledger.Ledger;
      Plan_Source_Text : String;
      Result           : out ALedger.Plan.Plan_Id_Universe;
      Diag             : out Admission_Diagnostic) return Boolean
   is
      Evidence      : ALedger.Journal_Evidence.Journal_Evidence;
      Evidence_Diag : Evidence_Diagnostic;
   begin
      Result := ALedger.Plan.Empty_Plan_Id_Universe;
      if not Extract (Plan_Source_Text, Plan_Ledger, Evidence, Evidence_Diag) then
         Diag :=
           (Status      => Plan_Source_Evidence_Error,
            Line_Number => Evidence_Diag.Line_Number,
            Plan_Id     => Null_Unbounded_String,
            Message     => Evidence_Diag.Message);
         return False;
      end if;

      return Admit_Plan_Identities (Plan_Ledger, Evidence, Result, Diag);
   end Admit_Plan_Identities;

   function Admit_Completions
     (Known_Plans     : ALedger.Plan.Plan_Id_Universe;
      Actual_Ledger   : ALedger.Ledger.Ledger;
      Actual_Evidence : ALedger.Journal_Evidence.Journal_Evidence;
      Result          : out Completion_Vectors.Vector;
      Diag            : out Admission_Diagnostic) return Boolean
   is
      Output : Completion_Vectors.Vector;

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

      function Completion_Exists (ID : ALedger.Plan.Plan_Id) return Boolean is
      begin
         for Item of Output loop
            if Item.ID = ID then
               return True;
            end if;
         end loop;
         return False;
      end Completion_Exists;

   begin
      Result := Output;
      Diag :=
        (Status      => Success,
         Line_Number => 0,
         Plan_Id     => Null_Unbounded_String,
         Message     => Null_Unbounded_String);

      if not Evidence_Aligns
        (Actual_Ledger, Actual_Evidence, Actual_Source_Evidence_Error, Diag)
      then
         return False;
      end if;

      for I in 1 .. Natural (Actual_Ledger.Transactions.Length) loop
         declare
            Source : constant Transaction_Source :=
              Actual_Evidence.Transactions.Element (I);
            Tx     : constant ALedger.Ledger.Transaction :=
              Actual_Ledger.Transactions.Element (I);
            Count  : Natural;
            Meta   : Metadata_Entry;
         begin
            Find_Metadata (Source, "plan-id", Count, Meta);
            if Count > 1 then
               Fail
                 (Duplicate_Plan_Metadata,
                  Source.Header_Line,
                  To_String (Meta.Value),
                  "Actual transaction repeats plan-id completion metadata");
               return False;
            elsif Count = 1 then
               declare
                  PID        : ALedger.Plan.Plan_Id;
                  PID_Status : ALedger.Plan.Plan_Id_Status;
               begin
                  if not ALedger.Plan.Create_Plan_Id
                    (To_String (Meta.Value), PID, PID_Status)
                  then
                     Fail
                       (Invalid_Actual_Plan_Id,
                        Meta.Line_Number,
                        To_String (Meta.Value),
                        "Actual transaction carries an invalid plan-id");
                     return False;
                  elsif not ALedger.Plan.Contains (Known_Plans, PID) then
                     Fail
                       (Unknown_Completion_Plan,
                        Meta.Line_Number,
                        ALedger.Plan.Text (PID),
                        "Actual completion references an unknown Plan");
                     return False;
                  elsif Completion_Exists (PID) then
                     Fail
                       (Multiple_Completion_Actuals,
                        Meta.Line_Number,
                        ALedger.Plan.Text (PID),
                        "Plan is completed by more than one Actual transaction");
                     return False;
                  end if;

                  Output.Append
                    (Completion'
                       (ID     => PID,
                        Date   => Tx.Date,
                        Tx     => Tx,
                        Source => Source));
               end;
            end if;
         end;
      end loop;

      Result := Output;
      return True;
   end Admit_Completions;

   function Admit_Plan_Completions
     (Known_Plans     : ALedger.Plan.Plan_Id_Universe;
      Actual_Ledger   : ALedger.Ledger.Ledger;
      Actual_Evidence : ALedger.Journal_Evidence.Journal_Evidence;
      Diag            : out Admission_Diagnostic) return Boolean
   is
      Completions : Completion_Vectors.Vector;
   begin
      return Admit_Completions
        (Known_Plans,
         Actual_Ledger,
         Actual_Evidence,
         Completions,
         Diag);
   end Admit_Plan_Completions;

   function Observe_Plans
     (Plan_Ledger      : ALedger.Ledger.Ledger;
      Plan_Evidence    : ALedger.Journal_Evidence.Journal_Evidence;
      Actual_Ledger    : ALedger.Ledger.Ledger;
      Actual_Evidence  : ALedger.Journal_Evidence.Journal_Evidence;
      As_Of_Date       : ALedger.Dates.Date;
      Open_Result      : out Open_Plan_Vectors.Vector;
      Completed_Result : out Completed_Plan_Vectors.Vector;
      Diag             : out Admission_Diagnostic) return Boolean
   is
      Plans            : Admitted_Plan_Vectors.Vector;
      Completions      : Completion_Vectors.Vector;
      Open_Output      : Open_Plan_Vectors.Vector;
      Completed_Output : Completed_Plan_Vectors.Vector;

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

      function Visible_Completion_Index
        (ID : ALedger.Plan.Plan_Id) return Natural
      is
      begin
         for I in 1 .. Natural (Completions.Length) loop
            declare
               Item : constant Completion := Completions.Element (I);
            begin
               if Item.ID = ID and then Item.Date <= As_Of_Date then
                  return I;
               end if;
            end;
         end loop;
         return 0;
      end Visible_Completion_Index;

      function Retired_As_Of (P : Admitted_Plan) return Boolean is
      begin
         return
           (P.Has_Cancellation and then P.Cancelled_On <= As_Of_Date)
           or else
           (P.Has_Supersession and then P.Superseded_On <= As_Of_Date);
      end Retired_As_Of;

      function Supersession_Cycle_From (Start : Positive) return Boolean is
         Current : ALedger.Plan.Plan_Id := Plans.Element (Start).ID;
      begin
         for Step in 1 .. Natural (Plans.Length) + 1 loop
            pragma Unreferenced (Step);
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

   begin
      Open_Result := Open_Output;
      Completed_Result := Completed_Output;
      Diag :=
        (Status      => Success,
         Line_Number => 0,
         Plan_Id     => Null_Unbounded_String,
         Message     => Null_Unbounded_String);

      if not Evidence_Aligns
        (Plan_Ledger, Plan_Evidence, Plan_Source_Evidence_Error, Diag)
      then
         return False;
      end if;

      for I in 1 .. Natural (Plan_Ledger.Transactions.Length) loop
         declare
            Source : constant Transaction_Source :=
              Plan_Evidence.Transactions.Element (I);
            Tx     : constant ALedger.Ledger.Transaction :=
              Plan_Ledger.Transactions.Element (I);
            Plan_Count, Cancel_Count, Sup_On_Count, Sup_By_Count : Natural;
            Plan_Meta, Cancel_Meta, Sup_On_Meta, Sup_By_Meta : Metadata_Entry;
            PID        : ALedger.Plan.Plan_Id;
            PID_Status : ALedger.Plan.Plan_Id_Status;
            P          : Admitted_Plan;
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
            elsif not ALedger.Plan.Create_Plan_Id
              (To_String (Plan_Meta.Value), PID, PID_Status)
            then
               Fail
                 (Invalid_Plan_Id,
                  Plan_Meta.Line_Number,
                  To_String (Plan_Meta.Value),
                  "invalid plan-id");
               return False;
            end if;

            for Existing of Plans loop
               if Existing.ID = PID then
                  Fail
                    (Duplicate_Plan_Id,
                     Plan_Meta.Line_Number,
                     ALedger.Plan.Text (PID),
                     "plan-id identifies more than one transaction");
                  return False;
               end if;
            end loop;

            Find_Metadata (Source, "cancelled-on", Cancel_Count, Cancel_Meta);
            Find_Metadata (Source, "superseded-on", Sup_On_Count, Sup_On_Meta);
            Find_Metadata (Source, "superseded-by", Sup_By_Count, Sup_By_Meta);
            if Cancel_Count > 1 or else Sup_On_Count > 1 or else Sup_By_Count > 1 then
               Fail
                 (Duplicate_Plan_Metadata,
                  Source.Header_Line,
                  ALedger.Plan.Text (PID),
                  "Plan transaction repeats lifecycle metadata");
               return False;
            elsif Cancel_Count > 0 and then (Sup_On_Count > 0 or else Sup_By_Count > 0) then
               Fail
                 (Invalid_Lifecycle_Metadata,
                  Source.Header_Line,
                  ALedger.Plan.Text (PID),
                  "cancellation conflicts with supersession metadata");
               return False;
            elsif (Sup_On_Count = 0) /= (Sup_By_Count = 0) then
               Fail
                 (Invalid_Lifecycle_Metadata,
                  Source.Header_Line,
                  ALedger.Plan.Text (PID),
                  "supersession requires both superseded-on and superseded-by");
               return False;
            end if;

            P.ID := PID;
            P.Tx := Tx;
            P.Source := Source;
            P.Has_Cancellation := False;
            P.Has_Supersession := False;
            P.Superseded_By := ALedger.Plan.Null_Plan_Id;

            if Cancel_Count = 1 then
               declare
                  Lifecycle_Date : ALedger.Dates.Date;
                  Date_Status    : ALedger.Dates.Date_Status;
               begin
                  if not ALedger.Dates.Parse
                    (To_String (Cancel_Meta.Value), Lifecycle_Date, Date_Status)
                  then
                     Fail
                       (Invalid_Lifecycle_Date,
                        Cancel_Meta.Line_Number,
                        ALedger.Plan.Text (PID),
                        "invalid cancelled-on date");
                     return False;
                  end if;
                  P.Has_Cancellation := True;
                  P.Cancelled_On := Lifecycle_Date;
               end;
            elsif Sup_On_Count = 1 then
               declare
                  Successor        : ALedger.Plan.Plan_Id;
                  Successor_Status : ALedger.Plan.Plan_Id_Status;
                  Lifecycle_Date   : ALedger.Dates.Date;
                  Date_Status      : ALedger.Dates.Date_Status;
               begin
                  if not ALedger.Dates.Parse
                    (To_String (Sup_On_Meta.Value), Lifecycle_Date, Date_Status)
                  then
                     Fail
                       (Invalid_Lifecycle_Date,
                        Sup_On_Meta.Line_Number,
                        ALedger.Plan.Text (PID),
                        "invalid superseded-on date");
                     return False;
                  elsif not ALedger.Plan.Create_Plan_Id
                    (To_String (Sup_By_Meta.Value), Successor, Successor_Status)
                  then
                     Fail
                       (Invalid_Supersession_Target,
                        Sup_By_Meta.Line_Number,
                        ALedger.Plan.Text (PID),
                        "invalid superseded-by plan-id");
                     return False;
                  elsif Successor = PID then
                     Fail
                       (Invalid_Supersession_Target,
                        Sup_By_Meta.Line_Number,
                        ALedger.Plan.Text (PID),
                        "Plan cannot supersede itself");
                     return False;
                  end if;
                  P.Has_Supersession := True;
                  P.Superseded_On := Lifecycle_Date;
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
               "superseded-by references an unknown Plan: " &
               ALedger.Plan.Text (P.Superseded_By));
            return False;
         end if;
      end loop;

      for I in 1 .. Natural (Plans.Length) loop
         if Plans.Element (I).Has_Supersession
           and then Supersession_Cycle_From (I)
         then
            Fail
              (Supersession_Cycle,
               0,
               ALedger.Plan.Text (Plans.Element (I).ID),
               "Plan supersession graph contains a cycle");
            return False;
         end if;
      end loop;

      declare
         Known_Plans : ALedger.Plan.Plan_Id_Universe :=
           ALedger.Plan.Empty_Plan_Id_Universe;
      begin
         for P of Plans loop
            ALedger.Plan.Include (Known_Plans, P.ID);
         end loop;

         if not Admit_Completions
           (Known_Plans,
            Actual_Ledger,
            Actual_Evidence,
            Completions,
            Diag)
         then
            return False;
         end if;
      end;

      for P of Plans loop
         declare
            C_Index : constant Natural := Visible_Completion_Index (P.ID);
         begin
            if C_Index > 0 then
               declare
                  C : constant Completion := Completions.Element (C_Index);
               begin
                  Completed_Output.Append
                    (Completed_Plan'
                       (ID            => P.ID,
                        Plan_Tx       => P.Tx,
                        Actual_Tx     => C.Tx,
                        Plan_Source   => P.Source,
                        Actual_Source => C.Source));
               end;
            elsif not Retired_As_Of (P) then
               Open_Output.Append (Open_Plan'(ID => P.ID, Tx => P.Tx));
            end if;
         end;
      end loop;

      Open_Result := Open_Output;
      Completed_Result := Completed_Output;
      return True;
   end Observe_Plans;

   function Observe_Plans
     (Plan_Ledger        : ALedger.Ledger.Ledger;
      Plan_Source_Text   : String;
      Actual_Ledger      : ALedger.Ledger.Ledger;
      Actual_Source_Text : String;
      As_Of_Date         : ALedger.Dates.Date;
      Open_Result        : out Open_Plan_Vectors.Vector;
      Completed_Result   : out Completed_Plan_Vectors.Vector;
      Diag               : out Admission_Diagnostic) return Boolean
   is
      Plan_Evidence    : ALedger.Journal_Evidence.Journal_Evidence;
      Actual_Evidence  : ALedger.Journal_Evidence.Journal_Evidence;
      Evidence_Diag    : Evidence_Diagnostic;
   begin
      Open_Result.Clear;
      Completed_Result.Clear;

      if not Extract (Plan_Source_Text, Plan_Ledger, Plan_Evidence, Evidence_Diag) then
         Diag :=
           (Status      => Plan_Source_Evidence_Error,
            Line_Number => Evidence_Diag.Line_Number,
            Plan_Id     => Null_Unbounded_String,
            Message     => Evidence_Diag.Message);
         return False;
      end if;

      if not Extract
        (Actual_Source_Text, Actual_Ledger, Actual_Evidence, Evidence_Diag)
      then
         Diag :=
           (Status      => Actual_Source_Evidence_Error,
            Line_Number => Evidence_Diag.Line_Number,
            Plan_Id     => Null_Unbounded_String,
            Message     => Evidence_Diag.Message);
         return False;
      end if;

      return Observe_Plans
        (Plan_Ledger,
         Plan_Evidence,
         Actual_Ledger,
         Actual_Evidence,
         As_Of_Date,
         Open_Result,
         Completed_Result,
         Diag);
   end Observe_Plans;

   function Observe_Open_Plans
     (Plan_Ledger     : ALedger.Ledger.Ledger;
      Plan_Evidence   : ALedger.Journal_Evidence.Journal_Evidence;
      Actual_Ledger   : ALedger.Ledger.Ledger;
      Actual_Evidence : ALedger.Journal_Evidence.Journal_Evidence;
      As_Of_Date      : ALedger.Dates.Date;
      Result          : out Open_Plan_Vectors.Vector;
      Diag            : out Admission_Diagnostic) return Boolean
   is
      Completed : Completed_Plan_Vectors.Vector;
   begin
      return Observe_Plans
        (Plan_Ledger,
         Plan_Evidence,
         Actual_Ledger,
         Actual_Evidence,
         As_Of_Date,
         Result,
         Completed,
         Diag);
   end Observe_Open_Plans;

   function Observe_Open_Plans
     (Plan_Ledger        : ALedger.Ledger.Ledger;
      Plan_Source_Text   : String;
      Actual_Ledger      : ALedger.Ledger.Ledger;
      Actual_Source_Text : String;
      As_Of_Date         : ALedger.Dates.Date;
      Result             : out Open_Plan_Vectors.Vector;
      Diag               : out Admission_Diagnostic) return Boolean
   is
      Completed : Completed_Plan_Vectors.Vector;
   begin
      return Observe_Plans
        (Plan_Ledger,
         Plan_Source_Text,
         Actual_Ledger,
         Actual_Source_Text,
         As_Of_Date,
         Result,
         Completed,
         Diag);
   end Observe_Open_Plans;

end ALedger.Plan_Observation;
