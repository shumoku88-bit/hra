package body HRA.Planned_Payments is

   use type HRA.Dates.Date;
   use type HRA.Money.Quantity;
   use type HRA.Account.Account_Type;

   function Project
     (Open_Plans : HRA.Plan_Temporal_Observation.Open_Plan_Vectors.Vector;
      Registry   : HRA.Account.Account_Registry;
      As_Of_Date : HRA.Dates.Date;
      Result     : out Observation;
      Diag       : out Projection_Diagnostic) return Boolean
   is
      Output : Observation;

      procedure Fail
        (Status  : Projection_Status;
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
        (P : HRA.Plan_Temporal_Observation.Open_Plan) return Boolean
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
               Category : HRA.Account.Account_Type;
               Known    : constant Boolean :=
                 HRA.Account.Account_Type_For
                   (Registry, Posting.Acc, Category);
               Q : constant HRA.Money.Quantity := Posting.Amt.Val;
            begin
               if not Known then
                  Fail
                    (Undeclared_Plan_Account,
                     HRA.Plan.Text (P.ID),
                     "Plan Posting references an undeclared Account: " &
                       HRA.Account.Name (Posting.Acc));
                  return False;
               end if;

               if Category = HRA.Account.Asset and then Q < 0.0 then
                  Has_Asset_Source := True;
                  Has_Asset_Negative := True;
               elsif (Category = HRA.Account.Expense
                      or else Category = HRA.Account.Liability)
                 and then Q > 0.0
               then
                  Has_Payment_Target := True;
               else
                  All_Outgoing := False;
               end if;

               if Category = HRA.Account.Income and then Q < 0.0 then
                  Has_Income_Source := True;
               elsif Category = HRA.Account.Asset and then Q > 0.0 then
                  Has_Asset_Income := True;
                  Has_Asset_Positive := True;
               else
                  All_Incoming := False;
               end if;

               if Category = HRA.Account.Asset and then Q < 0.0 then
                  Has_Asset_Negative := True;
               elsif Category = HRA.Account.Asset and then Q > 0.0 then
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
               HRA.Plan.Text (P.ID),
               "Plan Posting roles do not form a supported incoming, asset-target, or outgoing flow");
            return False;
         end if;

         if Natural (P.Tx.Postings.Length) /= 2 then
            Fail
              (Plan_Report_Requires_Binary_Outgoing,
               HRA.Plan.Text (P.ID),
               "Planned Payments currently requires one Asset source and one Expense/Liability destination");
            return False;
         end if;

         declare
            Source_Acc      : HRA.Account.Account;
            Destination_Acc : HRA.Account.Account;
            Payment_Amount  : HRA.Money.Amount;
            Source_Found    : Boolean := False;
            Target_Found    : Boolean := False;
         begin
            for Posting of P.Tx.Postings loop
               declare
                  Category : HRA.Account.Account_Type;
                  Known    : constant Boolean :=
                    HRA.Account.Account_Type_For
                      (Registry, Posting.Acc, Category);
               begin
                  if not Known then
                     Fail
                       (Undeclared_Plan_Account,
                        HRA.Plan.Text (P.ID),
                        "Plan Posting references an undeclared Account");
                     return False;
                  elsif Category = HRA.Account.Asset and then Posting.Amt.Val < 0.0 then
                     Source_Acc := Posting.Acc;
                     Source_Found := True;
                  elsif (Category = HRA.Account.Expense
                         or else Category = HRA.Account.Liability)
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
                  HRA.Plan.Text (P.ID),
                  "binary outgoing Plan is missing its source or destination");
               return False;
            end if;

            Output.Payments.Append
              (Planned_Payment'
                 (ID          => P.ID,
                  Due_Date    => P.Tx.Date,
                  Memo        => P.Tx.Code_Or_Payee,
                  Amt         => Payment_Amount,
                  Source      => Source_Acc,
                  Destination => Destination_Acc,
                  Timing      =>
                    (if P.Tx.Date < As_Of_Date then Overdue
                     elsif P.Tx.Date = As_Of_Date then Due_Today
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

      for P of Open_Plans loop
         if not Project_Open_Plan (P) then
            return False;
         end if;
      end loop;

      Result := Output;
      return True;
   end Project;

end HRA.Planned_Payments;
