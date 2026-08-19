package body HRA.Envelope_Routing is

   use type HRA.Dates.Date;

   function Managed_Route
     (Id : Envelope.Envelope_Id) return Expense_Route
   is
   begin
      return (Kind => Managed_By_Envelope, Target => Id);
   end Managed_Route;

   function Not_Managed_Route return Expense_Route is
   begin
      return (Kind => Not_Envelope_Managed);
   end Not_Managed_Route;

   function Initial_Effective_Date return Effective_Date is
   begin
      return (Kind => Initial);
   end Initial_Effective_Date;

   function Dated_Effective
     (Date : HRA.Dates.Date) return Effective_Date
   is
   begin
      return (Kind => From_Date, Date => Date);
   end Dated_Effective;

   function Empty_History return Routing_History is
   begin
      return (Entries => Routing_Entry_Vectors.Empty_Vector);
   end Empty_History;

   function Admit
     (Entries  : Routing_Entry_Vectors.Vector;
      Registry : Envelope.Envelope_Registry;
      History  : out Routing_History;
      Status   : out History_Status) return Boolean
   is
      H : Routing_History;
   begin
      for E of Entries loop
         if Account.Name (E.Expense)'Length = 0 then
            Status := Empty_Expense_Account;
            return False;
         end if;

         declare
            Dummy  : Account.Account;
            Acc_St : Account.Account_Status;
         begin
            if not Account.Create_Account
              (Account.Name (E.Expense), Dummy, Acc_St)
            then
               Status := Invalid_Expense_Account;
               return False;
            end if;
         end;

         if E.Route.Kind = Managed_By_Envelope
           and then not Envelope.Contains
             (Registry, Envelope.Image (E.Route.Target))
         then
            Status := Unknown_Envelope_In_Route;
            return False;
         end if;

         for Existing of H.Entries loop
            if Account.Name (Existing.Expense) =
               Account.Name (E.Expense)
              and then Existing.Effective = E.Effective
            then
               Status := Duplicate_Routing_Entry;
               return False;
            end if;
         end loop;

         H.Entries.Append (E);
      end loop;

      History := H;
      Status  := Success;
      return True;
   end Admit;

   function Resolve
     (H       : Routing_History;
      Expense : Account.Account;
      Date    : HRA.Dates.Date) return Expense_Route
   is
      Best         : Expense_Route := Not_Managed_Route;
      Found        : Boolean       := False;
      Best_Is_Init : Boolean       := False;
      Best_Date    : HRA.Dates.Date;
   begin
      for E of H.Entries loop
         if Account.Name (E.Expense) = Account.Name (Expense) then
            declare
               Applies   : Boolean := False;
               Is_Better : Boolean := False;
            begin
               case E.Effective.Kind is
                  when Initial =>
                     Applies := True;
                     if not Found then
                        Is_Better := True;
                     elsif not Best_Is_Init then
                        Is_Better := False;
                     end if;

                  when From_Date =>
                     declare
                        ED : constant HRA.Dates.Date := E.Effective.Date;
                     begin
                        if ED <= Date then
                           Applies := True;
                           if not Found then
                              Is_Better := True;
                           elsif Best_Is_Init then
                              Is_Better := True;
                           elsif ED > Best_Date then
                              Is_Better := True;
                           end if;
                        end if;
                     end;
               end case;

               if Applies and then Is_Better then
                  Best         := E.Route;
                  Found        := True;
                  Best_Is_Init := (E.Effective.Kind = Initial);
                  if E.Effective.Kind = From_Date then
                     Best_Date := E.Effective.Date;
                  end if;
               end if;
            end;
         end if;
      end loop;

      return Best;
   end Resolve;

   function Has_Routing_At
     (H       : Routing_History;
      Expense : Account.Account;
      Date    : HRA.Dates.Date) return Boolean
   is
   begin
      for E of H.Entries loop
         if Account.Name (E.Expense) = Account.Name (Expense) then
            case E.Effective.Kind is
               when Initial =>
                  return True;
               when From_Date =>
                  if E.Effective.Date <= Date then
                     return True;
                  end if;
            end case;
         end if;
      end loop;
      return False;
   end Has_Routing_At;

   function Has_Routing
     (H       : Routing_History;
      Expense : Account.Account) return Boolean
   is
   begin
      for E of H.Entries loop
         if Account.Name (E.Expense) = Account.Name (Expense) then
            return True;
         end if;
      end loop;
      return False;
   end Has_Routing;

   function Length (H : Routing_History) return Natural is
   begin
      return Natural (H.Entries.Length);
   end Length;

end HRA.Envelope_Routing;
