with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with ALedger.Plan_Observation;

package body ALedger.Planned_Payments is

   use type ALedger.Money.Quantity;
   use type ALedger.Account.Account_Type;

   function Map_Status
     (Status : ALedger.Plan_Observation.Admission_Status) return Admission_Status
   is
   begin
      case Status is
         when ALedger.Plan_Observation.Success => return Success;
         when ALedger.Plan_Observation.Plan_Source_Evidence_Error => return Plan_Source_Evidence_Error;
         when ALedger.Plan_Observation.Actual_Source_Evidence_Error => return Actual_Source_Evidence_Error;
         when ALedger.Plan_Observation.Invalid_Observation_Date => return Invalid_Observation_Date;
         when ALedger.Plan_Observation.Missing_Plan_Id => return Missing_Plan_Id;
         when ALedger.Plan_Observation.Duplicate_Plan_Metadata => return Duplicate_Plan_Metadata;
         when ALedger.Plan_Observation.Invalid_Plan_Id => return Invalid_Plan_Id;
         when ALedger.Plan_Observation.Duplicate_Plan_Id => return Duplicate_Plan_Id;
         when ALedger.Plan_Observation.Invalid_Lifecycle_Metadata => return Invalid_Lifecycle_Metadata;
         when ALedger.Plan_Observation.Invalid_Lifecycle_Date => return Invalid_Lifecycle_Date;
         when ALedger.Plan_Observation.Invalid_Supersession_Target => return Invalid_Supersession_Target;
         when ALedger.Plan_Observation.Unknown_Supersession_Target => return Unknown_Supersession_Target;
         when ALedger.Plan_Observation.Supersession_Cycle => return Supersession_Cycle;
         when ALedger.Plan_Observation.Invalid_Actual_Plan_Id => return Invalid_Actual_Plan_Id;
         when ALedger.Plan_Observation.Unknown_Completion_Plan => return Unknown_Completion_Plan;
         when ALedger.Plan_Observation.Multiple_Completion_Actuals => return Multiple_Completion_Actuals;
      end case;
   end Map_Status;

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
      Open_Plans : ALedger.Plan_Observation.Open_Plan_Vectors.Vector;
      Plan_Diag  : ALedger.Plan_Observation.Admission_Diagnostic;
      Output     : Observation;

      procedure Fail
        (Status  : Admission_Status;
         Plan_ID : String;
         Message : String)
      is
      begin
         Diag :=
           (Status      => Status,
            Line_Number => 0,
            Plan_Id     => To_Unbounded_String (Plan_ID),
            Message     => To_Unbounded_String (Message));
      end Fail;

      function Project_Open_Plan
        (P : ALedger.Plan_Observation.Open_Plan) return Boolean
      is
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
            return True;
         elsif not (All_Outgoing and then Has_Asset_Source and then Has_Payment_Target) then
            Fail
              (Unsupported_Plan_Role_Flow,
               ALedger.Plan.Text (P.ID),
               "Plan Posting roles do not form a supported incoming, asset-target, or outgoing flow");
            return False;
         end if;

         if Natural (P.Tx.Postings.Length) /= 2 then
            Fail
              (Plan_Report_Requires_Binary_Outgoing,
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
                     Fail
                       (Undeclared_Plan_Account,
                        ALedger.Plan.Text (P.ID),
                        "Plan Posting references an undeclared Account");
                     return False;
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

      if not ALedger.Plan_Observation.Observe_Open_Plans
        (Plan_Ledger,
         Plan_Source_Text,
         Actual_Ledger,
         Actual_Source_Text,
         As_Of_Date,
         Open_Plans,
         Plan_Diag)
      then
         Diag :=
           (Status      => Map_Status (Plan_Diag.Status),
            Line_Number => Plan_Diag.Line_Number,
            Plan_Id     => Plan_Diag.Plan_Id,
            Message     => Plan_Diag.Message);
         return False;
      end if;

      for P of Open_Plans loop
         if not Project_Open_Plan (P) then
            return False;
         end if;
      end loop;

      Result := Output;
      return True;
   end Observe;

end ALedger.Planned_Payments;
