with HRA.Journal_Evidence; use HRA.Journal_Evidence;

package body HRA.Plan_Completion is

   use type HRA.Plan.Plan_Id;

   function Empty_Relations return Completion_Relations is
      Result : Completion_Relations;
   begin
      Result.In_Order.Clear;
      return Result;
   end Empty_Relations;

   function Has_Completion
     (Relations : Completion_Relations;
      Plan_ID   : HRA.Plan.Plan_Id) return Boolean
   is
   begin
      for Item of Relations.In_Order loop
         if Item.Plan_ID = Plan_ID then
            return True;
         end if;
      end loop;
      return False;
   end Has_Completion;

   function Has_Visible_Completion
     (Relations        : Completion_Relations;
      Plan_ID          : HRA.Plan.Plan_Id;
      Observed_Through : HRA.Dates.Date;
      Relation         : out Completion_Relation) return Boolean
   is
      use type HRA.Dates.Date;
   begin
      for Item of Relations.In_Order loop
         if Item.Plan_ID = Plan_ID
           and then Item.Actual.Tx.Date <= Observed_Through
         then
            Relation := Item;
            return True;
         end if;
      end loop;
      return False;
   end Has_Visible_Completion;

   function Admit
     (Plans   : HRA.Plan_Admission.Plan_Journal;
      Actuals : HRA.Actual_Admission.Actual_Observation;
      Result  : out Completion_Relations;
      Diag    : out Admission_Diagnostic) return Boolean
   is
      Output : Completion_Relations := Empty_Relations;

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
         for I in 1 .. HRA.Plan_Admission.Transaction_Count (Plans) loop
            if HRA.Plan_Admission.Transaction_At (Plans, I).ID = ID then
               return I;
            end if;
         end loop;
         return 0;
      end Find_Plan_Index;

   begin
      Result := Output;
      Diag :=
        (Status      => Success,
         Line_Number => 0,
         Plan_Id     => Null_Unbounded_String,
         Message     => Null_Unbounded_String);

      for I in 1 .. HRA.Actual_Admission.Transaction_Count (Actuals) loop
         declare
            Actual : constant HRA.Actual_Admission.Actual_Transaction_Entry :=
              HRA.Actual_Admission.Transaction_At (Actuals, I);
            Count : Natural := 0;
            Meta  : Metadata_Entry :=
              (Key         => Null_Unbounded_String,
               Value       => Null_Unbounded_String,
               Line_Number => Actual.Source.Header_Line);
         begin
            --  Actual_Admission has already enforced singular, syntactically
            --  valid plan-id metadata. We inspect the retained parser structure,
            --  never raw source text. Any violation here therefore means the
            --  admitted Actual invariant itself was broken.
            for Candidate of Actual.Source.Metadata loop
               if To_String (Candidate.Key) = "plan-id" then
                  Count := Count + 1;
                  if Count = 1 then
                     Meta := Candidate;
                  end if;
               end if;
            end loop;

            if Count > 1 then
               Fail
                 (Actual_Admission_Invariant_Violation,
                  Actual.Source.Header_Line,
                  To_String (Meta.Value),
                  "admitted Actual repeats plan-id metadata");
               return False;
            elsif Count = 1 then
               declare
                  PID        : HRA.Plan.Plan_Id;
                  PID_Status : HRA.Plan.Plan_Id_Status;
                  Plan_Index : Natural;
               begin
                  if not HRA.Plan.Create_Plan_Id
                    (To_String (Meta.Value), PID, PID_Status)
                  then
                     Fail
                       (Actual_Admission_Invariant_Violation,
                        Meta.Line_Number,
                        To_String (Meta.Value),
                        "admitted Actual contains an invalid completion PlanId");
                     return False;
                  end if;

                  Plan_Index := Find_Plan_Index (PID);
                  if Plan_Index = 0 then
                     Fail
                       (Unknown_Completion_Plan,
                        Meta.Line_Number,
                        HRA.Plan.Text (PID),
                        "Actual completion references an unknown admitted Plan");
                     return False;
                  elsif Has_Completion (Output, PID) then
                     Fail
                       (Multiple_Completion_Actuals,
                        Meta.Line_Number,
                        HRA.Plan.Text (PID),
                        "one Plan is completed by more than one Actual transaction");
                     return False;
                  end if;

                  Output.In_Order.Append
                    (Completion_Relation'
                       (Plan_ID => PID,
                        Plan    => HRA.Plan_Admission.Transaction_At
                          (Plans, Positive (Plan_Index)),
                        Actual  => Actual));
               end;
            end if;
         end;
      end loop;

      Result := Output;
      return True;
   end Admit;

end HRA.Plan_Completion;
