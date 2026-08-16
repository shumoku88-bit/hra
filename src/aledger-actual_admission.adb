with Ada.Characters.Handling; use Ada.Characters.Handling;
with Ada.Containers.Indefinite_Vectors;
with ALedger.Dates;
with ALedger.Money; use ALedger.Money;
with ALedger.Account; use ALedger.Account;
with ALedger.Plan;
with ALedger.Journal_Evidence; use ALedger.Journal_Evidence;

package body ALedger.Actual_Admission is

   use type ALedger.Dates.Date;

   package Actual_Id_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Actual_Id,
      "="          => "=");

   function Create_Actual_Id
     (Value  : String;
      ID     : out Actual_Id;
      Status : out Actual_Id_Status) return Boolean
   is
   begin
      if Value'Length = 0 then
         Status := Empty_Actual_Id;
         return False;
      end if;

      for C of Value loop
         if Is_Space (C) then
            Status := Actual_Id_Contains_Whitespace;
            return False;
         elsif Character'Pos (C) < 32 or else Character'Pos (C) = 127 then
            Status := Actual_Id_Contains_Control_Character;
            return False;
         end if;
      end loop;

      ID := (ID_Text => To_Unbounded_String (Value));
      Status := Success;
      return True;
   end Create_Actual_Id;

   function Text (ID : Actual_Id) return String is
     (To_String (ID.ID_Text));

   function "=" (Left, Right : Actual_Id) return Boolean is
     (Left.ID_Text = Right.ID_Text);

   function Empty_Observation return Actual_Observation is
      Result : Actual_Observation;
   begin
      Result.Value := ALedger.Ledger.Empty_Ledger;
      Result.Identified.Clear;
      Result.Reversals.Clear;
      return Result;
   end Empty_Observation;

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
      Diag     : out Admission_Diagnostic) return Boolean
   is
   begin
      if Natural (Evidence.Transactions.Length) /=
         Natural (L.Transactions.Length)
      then
         Diag :=
           (Status      => Source_Evidence_Error,
            Line_Number => 0,
            Actual_Id   => Null_Unbounded_String,
            Message     => To_Unbounded_String
              ("Actual Journal evidence transaction count does not match Ledger"));
         return False;
      end if;

      for I in 1 .. Natural (L.Transactions.Length) loop
         declare
            Source : constant Transaction_Source := Evidence.Transactions.Element (I);
            Tx     : constant ALedger.Ledger.Transaction := L.Transactions.Element (I);
         begin
            if To_String (Source.Date_Text) /= ALedger.Dates.Image (Tx.Date)
              or else To_String (Source.Description) /= To_String (Tx.Code_Or_Payee)
            then
               Diag :=
                 (Status      => Source_Evidence_Error,
                  Line_Number => Source.Header_Line,
                  Actual_Id   => Null_Unbounded_String,
                  Message     => To_Unbounded_String
                    ("Actual Journal evidence does not align with Ledger"));
               return False;
            end if;
         end;
      end loop;

      return True;
   end Evidence_Aligns;

   function Safe_Add
     (Left, Right : Quantity;
      Result      : out Quantity) return Boolean
   is
   begin
      if Right > Zero_Quantity
        and then Left > Quantity'Last - Right
      then
         return False;
      elsif Right < Zero_Quantity
        and then Left < Quantity'First - Right
      then
         return False;
      end if;

      Result := Left + Right;
      return True;
   end Safe_Add;

   function Coordinate_Total
     (Tx     : ALedger.Ledger.Transaction;
      Acc    : Account;
      Comm   : Commodity;
      Result : out Quantity) return Boolean
   is
      Total : Quantity := Zero_Quantity;
   begin
      for Posting of Tx.Postings loop
         if Posting.Acc = Acc and then Posting.Amt.Comm = Comm then
            declare
               Next : Quantity;
            begin
               if not Safe_Add (Total, Posting.Amt.Val, Next) then
                  return False;
               end if;
               Total := Next;
            end;
         end if;
      end loop;

      Result := Total;
      return True;
   end Coordinate_Total;

   function Effects_Are_Inverse
     (Left, Right : ALedger.Ledger.Transaction) return Boolean
   is
      function Coordinate_Is_Inverse
        (Acc : Account; Comm : Commodity) return Boolean
      is
         L_Total : Quantity;
         R_Total : Quantity;
         Sum     : Quantity;
      begin
         return Coordinate_Total (Left, Acc, Comm, L_Total)
           and then Coordinate_Total (Right, Acc, Comm, R_Total)
           and then Safe_Add (L_Total, R_Total, Sum)
           and then Is_Zero (Sum);
      end Coordinate_Is_Inverse;
   begin
      for Posting of Left.Postings loop
         if not Coordinate_Is_Inverse (Posting.Acc, Posting.Amt.Comm) then
            return False;
         end if;
      end loop;

      for Posting of Right.Postings loop
         if not Coordinate_Is_Inverse (Posting.Acc, Posting.Amt.Comm) then
            return False;
         end if;
      end loop;

      return True;
   end Effects_Are_Inverse;

   function Admit
     (Actual_Ledger   : ALedger.Ledger.Ledger;
      Actual_Evidence : ALedger.Journal_Evidence.Journal_Evidence;
      Result          : out Actual_Observation;
      Diag            : out Admission_Diagnostic) return Boolean
   is
      Output : Actual_Observation := Empty_Observation;

      procedure Fail
        (Status  : Admission_Status;
         Line    : Natural;
         ID_Text : String;
         Message : String)
      is
      begin
         Diag :=
           (Status      => Status,
            Line_Number => Line,
            Actual_Id   => To_Unbounded_String (ID_Text),
            Message     => To_Unbounded_String (Message));
      end Fail;

      function Find_Identified_Index (ID : Actual_Id) return Natural is
      begin
         for I in 1 .. Natural (Output.Identified.Length) loop
            if Output.Identified.Element (I).ID = ID then
               return I;
            end if;
         end loop;
         return 0;
      end Find_Identified_Index;

      function Reversal_Target_Index (ID : Actual_Id) return Natural is
      begin
         for I in 1 .. Natural (Output.Reversals.Length) loop
            if Output.Reversals.Element (I).Target_ID = ID then
               return I;
            end if;
         end loop;
         return 0;
      end Reversal_Target_Index;

      function Reversal_By_Id_Index (ID : Actual_Id) return Natural is
      begin
         for I in 1 .. Natural (Output.Reversals.Length) loop
            if Output.Reversals.Element (I).Reversal_ID = ID then
               return I;
            end if;
         end loop;
         return 0;
      end Reversal_By_Id_Index;

   begin
      Result := Output;
      Diag :=
        (Status      => Success,
         Line_Number => 0,
         Actual_Id   => Null_Unbounded_String,
         Message     => Null_Unbounded_String);

      if not Evidence_Aligns (Actual_Ledger, Actual_Evidence, Diag) then
         return False;
      end if;

      --  The Journal parser owns accounting syntax, but durable Actual identity
      --  is admitted only from retained source evidence here. Start from the
      --  validated Ledger and erase parser-projected identity fields so no
      --  display-text reconstruction can remain an authority path downstream.
      Output.Value := Actual_Ledger;
      for I in 1 .. Natural (Output.Value.Transactions.Length) loop
         declare
            Tx : ALedger.Ledger.Transaction :=
              Output.Value.Transactions.Element (I);
         begin
            Tx.Event_ID    := Null_Unbounded_String;
            Tx.Reverses_ID := Null_Unbounded_String;
            Output.Value.Transactions.Replace_Element (I, Tx);
         end;
      end loop;

      for I in 1 .. Natural (Actual_Ledger.Transactions.Length) loop
         declare
            Tx     : constant ALedger.Ledger.Transaction :=
              Actual_Ledger.Transactions.Element (I);
            Source : constant Transaction_Source :=
              Actual_Evidence.Transactions.Element (I);
            Normalized_Tx : ALedger.Ledger.Transaction := Tx;
            Event_Count, Plan_Count, Reverses_Count : Natural;
            Event_Meta, Plan_Meta, Reverses_Meta : Metadata_Entry;
            Event_ID, Derived_ID, Target_ID : Actual_Id;
            Event_Status, Derived_Status, Target_Status : Actual_Id_Status;
            PID        : ALedger.Plan.Plan_Id;
            PID_Status : ALedger.Plan.Plan_Id_Status;
            Has_Event, Has_Derived, Has_Target : Boolean := False;
         begin
            Normalized_Tx.Event_ID    := Null_Unbounded_String;
            Normalized_Tx.Reverses_ID := Null_Unbounded_String;

            Find_Metadata (Source, "event-id", Event_Count, Event_Meta);
            Find_Metadata (Source, "plan-id", Plan_Count, Plan_Meta);
            Find_Metadata (Source, "reverses", Reverses_Count, Reverses_Meta);

            if Event_Count > 1 then
               Fail (Duplicate_Metadata, Event_Meta.Line_Number,
                     To_String (Event_Meta.Value),
                     "Actual transaction repeats event-id metadata");
               return False;
            elsif Plan_Count > 1 then
               Fail (Duplicate_Metadata, Plan_Meta.Line_Number,
                     To_String (Plan_Meta.Value),
                     "Actual transaction repeats plan-id metadata");
               return False;
            elsif Reverses_Count > 1 then
               Fail (Duplicate_Metadata, Reverses_Meta.Line_Number,
                     To_String (Reverses_Meta.Value),
                     "Actual transaction repeats reverses metadata");
               return False;
            end if;

            if Event_Count = 1 then
               if not Create_Actual_Id
                 (To_String (Event_Meta.Value), Event_ID, Event_Status)
               then
                  Fail (Invalid_Event_Id, Event_Meta.Line_Number,
                        To_String (Event_Meta.Value), "invalid event-id");
                  return False;
               end if;
               Has_Event := True;
            end if;

            if Plan_Count = 1 then
               if not ALedger.Plan.Create_Plan_Id
                 (To_String (Plan_Meta.Value), PID, PID_Status)
               then
                  Fail (Invalid_Plan_Id, Plan_Meta.Line_Number,
                        To_String (Plan_Meta.Value),
                        "Actual transaction carries an invalid plan-id");
                  return False;
               end if;

               if not Has_Event then
                  if not Create_Actual_Id
                    ("plan-completion-" & ALedger.Plan.Text (PID),
                     Derived_ID, Derived_Status)
                  then
                     Fail (Invalid_Event_Id, Plan_Meta.Line_Number,
                           To_String (Plan_Meta.Value),
                           "cannot derive Actual identity from plan-id");
                     return False;
                  end if;
                  Has_Derived := True;
               end if;
            end if;

            if Reverses_Count = 1 then
               if not Create_Actual_Id
                 (To_String (Reverses_Meta.Value), Target_ID, Target_Status)
               then
                  Fail (Invalid_Reverses_Id, Reverses_Meta.Line_Number,
                        To_String (Reverses_Meta.Value), "invalid reverses id");
                  return False;
               elsif not Has_Event then
                  Fail (Reversal_Missing_Event_Id, Reverses_Meta.Line_Number,
                        To_String (Reverses_Meta.Value),
                        "reversal requires its own explicit event-id");
                  return False;
               elsif Event_ID = Target_ID then
                  Fail (Reversal_Self_Reference, Reverses_Meta.Line_Number,
                        Text (Event_ID), "reversal cannot target itself");
                  return False;
               end if;
               Has_Target := True;
               Normalized_Tx.Reverses_ID :=
                 To_Unbounded_String (Text (Target_ID));
            end if;

            if Has_Event or else Has_Derived then
               declare
                  Effective_ID : constant Actual_Id :=
                    (if Has_Event then Event_ID else Derived_ID);
               begin
                  if Find_Identified_Index (Effective_ID) > 0 then
                     Fail (Duplicate_Actual_Id, Source.Header_Line,
                           Text (Effective_ID),
                           "Actual identity identifies more than one transaction");
                     return False;
                  end if;

                  Normalized_Tx.Event_ID :=
                    To_Unbounded_String (Text (Effective_ID));
                  Output.Identified.Append
                    (Identified_Actual'
                       (ID     => Effective_ID,
                        Tx     => Normalized_Tx,
                        Source => Source));
               end;
            end if;

            if Has_Target then
               if Reversal_Target_Index (Target_ID) > 0 then
                  Fail (Duplicate_Reversal_Target, Reverses_Meta.Line_Number,
                        Text (Target_ID),
                        "Actual transaction is reversed directly more than once");
                  return False;
               end if;

               Output.Reversals.Append
                 (Reversal_Declaration'
                    (Reversal_ID => Event_ID,
                     Target_ID   => Target_ID));
            end if;

            Output.Value.Transactions.Replace_Element (I, Normalized_Tx);
         end;
      end loop;

      for Reversal of Output.Reversals loop
         declare
            Reversal_Index : constant Natural :=
              Find_Identified_Index (Reversal.Reversal_ID);
            Target_Index : constant Natural :=
              Find_Identified_Index (Reversal.Target_ID);
         begin
            if Target_Index = 0 then
               Fail (Unknown_Reversal_Target, 0, Text (Reversal.Target_ID),
                     "reverses references an unknown Actual identity");
               return False;
            elsif Reversal_Index = 0 then
               Fail (Unknown_Reversal_Target, 0, Text (Reversal.Reversal_ID),
                     "reversal identity is not admitted");
               return False;
            elsif not Effects_Are_Inverse
              (Output.Identified.Element (Reversal_Index).Tx,
               Output.Identified.Element (Target_Index).Tx)
            then
               Fail (Reversal_Posting_Mismatch, 0,
                     Text (Reversal.Reversal_ID),
                     "reversal posting effect is not the exact inverse of target");
               return False;
            end if;
         end;
      end loop;

      for Reversal of Output.Reversals loop
         declare
            Seen    : Actual_Id_Vectors.Vector;
            Current : Actual_Id := Reversal.Reversal_ID;
         begin
            for Step in 1 .. Natural (Output.Reversals.Length) + 1 loop
               pragma Unreferenced (Step);
               for Existing of Seen loop
                  if Existing = Current then
                     Fail (Reversal_Cycle, 0, Text (Current),
                           "Actual reversal graph contains a cycle");
                     return False;
                  end if;
               end loop;
               Seen.Append (Current);

               declare
                  Index : constant Natural := Reversal_By_Id_Index (Current);
               begin
                  exit when Index = 0;
                  Current := Output.Reversals.Element (Index).Target_ID;
               end;
            end loop;
         end;
      end loop;

      Result := Output;
      return True;
   end Admit;

end ALedger.Actual_Admission;
