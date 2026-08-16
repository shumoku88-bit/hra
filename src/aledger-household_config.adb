with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with TOML;
with ALedger.Account;
with ALedger.Money; use ALedger.Money;

package body ALedger.Household_Config is

   use type TOML.Any_Value_Kind;

   Source_Name : constant String := "household.toml";

   function Image (I : Positive) return String is
     (Trim (Positive'Image (I), Ada.Strings.Both));

   function Contains
     (Items : String_Vectors.Vector;
      Value : String) return Boolean
   is
   begin
      for Item of Items loop
         if Item = Value then
            return True;
         end if;
      end loop;
      return False;
   end Contains;

   function Valid_Account (Name : String) return Boolean is
      Acc    : ALedger.Account.Account;
      Status : ALedger.Account.Account_Status;
   begin
      return ALedger.Account.Create_Account (Name, Acc, Status);
   end Valid_Account;

   function Read_Accounts
     (Value : TOML.TOML_Value;
      Path  : String;
      Items : out String_Vectors.Vector;
      Diag  : out Config_Diagnostic) return Boolean
   is
   begin
      if not Read_String_Array (Value, Source_Name, Path, Items, Diag) then
         return False;
      end if;
      for Item of Items loop
         if not Valid_Account (Item) then
            Set_Error
              (Diag, Source_Name, Path, "invalid Account identity", Value);
            return False;
         end if;
      end loop;
      return True;
   end Read_Accounts;

   function Parse_Household_Configuration
     (Text          : String;
      Budget_Policy : ALedger.Budget_Config.Budget_Policy;
      Config        : out Household_Configuration;
      Diag          : out Config_Diagnostic) return Boolean
   is
      Root, Cycle, Budget, Money, Daily_Target, History_Section :
        TOML.TOML_Value;
      Mode_Value, Income_Value, Opening_Value, Unassigned_Value,
        Envelopes_Value : TOML.TOML_Value;
      Commodity_Value, Assets_Value : TOML.TOML_Value;
      Has_Money, Has_Daily_Target : Boolean;
      Result : Household_Configuration;
      Known_Envelopes, Seen_Envelopes, Allocations,
        Daily_IDs, Daily_Accounts : String_Vectors.Vector;
   begin
      for Envelope of Budget_Policy.Envelopes loop
         Known_Envelopes.Append (To_String (Envelope.ID));
      end loop;

      if not Parse_Root (Text, Source_Name, Root, Diag)
        or else not Check_Keys
          (Root, "cycle|money|budget|daily-target|envelope-history",
           Source_Name, "", Diag)
        or else not Require
          (Root, "cycle", TOML.TOML_Table,
           Source_Name, "", Cycle, Diag)
        or else not Require
          (Root, "budget", TOML.TOML_Table,
           Source_Name, "", Budget, Diag)
        or else not Optional
          (Root, "money", TOML.TOML_Table,
           Source_Name, "", Money, Has_Money, Diag)
        or else not Optional
          (Root, "daily-target", TOML.TOML_Table,
           Source_Name, "", Daily_Target, Has_Daily_Target, Diag)
        or else not Require
          (Root, "envelope-history", TOML.TOML_Table,
           Source_Name, "", History_Section, Diag)
        or else not Check_Keys
          (Cycle, "mode|income-account", Source_Name, "cycle", Diag)
        or else not Require
          (Cycle, "mode", TOML.TOML_String,
           Source_Name, "cycle", Mode_Value, Diag)
        or else not Require
          (Cycle, "income-account", TOML.TOML_String,
           Source_Name, "cycle", Income_Value, Diag)
      then
         return False;
      end if;

      if Mode_Value.As_String /= "income-anchor" then
         Set_Error
           (Diag, Source_Name, "cycle.mode",
            "expected income-anchor", Mode_Value);
         return False;
      elsif not Valid_Account (Income_Value.As_String) then
         Set_Error
           (Diag, Source_Name, "cycle.income-account",
            "invalid Account identity", Income_Value);
         return False;
      end if;
      Result.Cycle := Income_Anchor;
      Result.Cycle_Income_Account := Income_Value.As_Unbounded_String;

      if Has_Money then
         if not Check_Keys
           (Money, "primary-commodity", Source_Name, "money", Diag)
           or else not Require
             (Money, "primary-commodity", TOML.TOML_String,
              Source_Name, "money", Commodity_Value, Diag)
         then
            return False;
         end if;
         declare
            Status : Commodity_Status;
         begin
            if not Create_Commodity
              (Commodity_Value.As_String, Result.Primary_Commodity, Status)
            then
               Set_Error
                 (Diag, Source_Name, "money.primary-commodity",
                  "invalid Commodity", Commodity_Value);
               return False;
            end if;
         end;
         Result.Has_Primary_Commodity := True;
      end if;

      if not Check_Keys
        (Budget, "opening-accounts|unassigned-accounts|envelopes",
         Source_Name, "budget", Diag)
        or else not Require
          (Budget, "opening-accounts", TOML.TOML_Array,
           Source_Name, "budget", Opening_Value, Diag)
        or else not Read_Accounts
          (Opening_Value, "budget.opening-accounts",
           Result.Opening_Accounts, Diag)
        or else not Require
          (Budget, "unassigned-accounts", TOML.TOML_Array,
           Source_Name, "budget", Unassigned_Value, Diag)
        or else not Read_Accounts
          (Unassigned_Value, "budget.unassigned-accounts",
           Result.Unassigned_Accounts, Diag)
        or else not Require
          (Budget, "envelopes", TOML.TOML_Array,
           Source_Name, "budget", Envelopes_Value, Diag)
      then
         return False;
      end if;

      if Result.Opening_Accounts.Is_Empty then
         Set_Error
           (Diag, Source_Name, "budget.opening-accounts",
            "expected at least one opening Budget account", Opening_Value);
         return False;
      elsif Result.Unassigned_Accounts.Is_Empty then
         Set_Error
           (Diag, Source_Name, "budget.unassigned-accounts",
            "expected at least one unassigned Budget account", Unassigned_Value);
         return False;
      end if;

      for Name of Result.Opening_Accounts loop
         if Contains (Result.Unassigned_Accounts, Name) then
            Set_Error
              (Diag, Source_Name, "budget",
               "Budget Account cannot be both opening and unassigned");
            return False;
         end if;
      end loop;

      for I in 1 .. Envelopes_Value.Length loop
         declare
            Item, ID_Value, Allocation_Value : TOML.TOML_Value;
            Path : constant String :=
              "budget.envelopes[" & Image (I) & "]";
         begin
            Item := Envelopes_Value.Item (I);
            if Item.Kind /= TOML.TOML_Table then
               Set_Error (Diag, Source_Name, Path, "expected table", Item);
               return False;
            elsif not Check_Keys
              (Item, "id|allocation-account", Source_Name, Path, Diag)
              or else not Require
                (Item, "id", TOML.TOML_String,
                 Source_Name, Path, ID_Value, Diag)
              or else not Require
                (Item, "allocation-account", TOML.TOML_String,
                 Source_Name, Path, Allocation_Value, Diag)
            then
               return False;
            end if;

            if ID_Value.As_String'Length = 0 then
               Set_Error
                 (Diag, Source_Name, Path & ".id",
                  "expected non-empty Envelope identity", ID_Value);
               return False;
            elsif Contains (Seen_Envelopes, ID_Value.As_String) then
               Set_Error
                 (Diag, Source_Name, Path & ".id",
                  "duplicate envelope coordinates", ID_Value);
               return False;
            elsif not Valid_Account (Allocation_Value.As_String) then
               Set_Error
                 (Diag, Source_Name, Path & ".allocation-account",
                  "invalid Account identity", Allocation_Value);
               return False;
            elsif Contains (Allocations, Allocation_Value.As_String)
              or else Contains
                (Result.Opening_Accounts, Allocation_Value.As_String)
              or else Contains
                (Result.Unassigned_Accounts, Allocation_Value.As_String)
            then
               Set_Error
                 (Diag, Source_Name, Path & ".allocation-account",
                  "allocation Account is duplicated, opening, or unassigned",
                  Allocation_Value);
               return False;
            end if;

            Seen_Envelopes.Append (ID_Value.As_String);
            Allocations.Append (Allocation_Value.As_String);
            Result.Envelopes.Append
              (Envelope_Coordinates'
                 (ID                 => ID_Value.As_Unbounded_String,
                  Allocation_Account => Allocation_Value.As_Unbounded_String));
         end;
      end loop;

      for Current_ID of Known_Envelopes loop
         if not Contains (Seen_Envelopes, Current_ID) then
            Set_Error
              (Diag, Source_Name, "budget.envelopes",
               "every current budget.toml envelope requires household coordinates");
            return False;
         end if;
      end loop;

      if Has_Daily_Target then
         if not Check_Keys
           (Daily_Target, "assets", Source_Name, "daily-target", Diag)
           or else not Require
             (Daily_Target, "assets", TOML.TOML_Array,
              Source_Name, "daily-target", Assets_Value, Diag)
         then
            return False;
         end if;

         for I in 1 .. Assets_Value.Length loop
            declare
               Item, ID_Value, Account_Value : TOML.TOML_Value;
               Path : constant String :=
                 "daily-target.assets[" & Image (I) & "]";
            begin
               Item := Assets_Value.Item (I);
               if Item.Kind /= TOML.TOML_Table then
                  Set_Error (Diag, Source_Name, Path, "expected table", Item);
                  return False;
               elsif not Check_Keys
                 (Item, "id|account", Source_Name, Path, Diag)
                 or else not Require
                   (Item, "id", TOML.TOML_String,
                    Source_Name, Path, ID_Value, Diag)
                 or else not Require
                   (Item, "account", TOML.TOML_String,
                    Source_Name, Path, Account_Value, Diag)
               then
                  return False;
               end if;

               if ID_Value.As_String'Length = 0
                 or else Contains (Daily_IDs, ID_Value.As_String)
               then
                  Set_Error
                    (Diag, Source_Name, Path & ".id",
                     "empty or duplicate Daily Target identity", ID_Value);
                  return False;
               elsif not Valid_Account (Account_Value.As_String)
                 or else Contains (Daily_Accounts, Account_Value.As_String)
               then
                  Set_Error
                    (Diag, Source_Name, Path & ".account",
                     "invalid or duplicate Daily Target Account", Account_Value);
                  return False;
               end if;

               Daily_IDs.Append (ID_Value.As_String);
               Daily_Accounts.Append (Account_Value.As_String);
               Result.Daily_Target_Assets.Append
                 (Daily_Target_Asset'
                    (ID      => ID_Value.As_Unbounded_String,
                     Account => Account_Value.As_Unbounded_String));
            end;
         end loop;
      end if;

      if not Check_Keys
        (History_Section,
         "identities|expense-routing|fulfillment-routing",
         Source_Name, "envelope-history", Diag)
      then
         return False;
      end if;

      declare
         Identities_Value : TOML.TOML_Value;
      begin
         if not Require
           (History_Section, "identities", TOML.TOML_Array,
            Source_Name, "envelope-history", Identities_Value, Diag)
           or else not Read_String_Array
             (Identities_Value, Source_Name, "envelope-history.identities",
              Result.Envelope_History.Identities, Diag)
         then
            return False;
         end if;
      end;

      declare
         Routing_Value : TOML.TOML_Value;
      begin
         if not Require
           (History_Section, "expense-routing", TOML.TOML_Array,
            Source_Name, "envelope-history", Routing_Value, Diag)
         then
            return False;
         end if;

         for I in 1 .. Routing_Value.Length loop
            declare
               Item : constant TOML.TOML_Value := Routing_Value.Item (I);
               Path : constant String :=
                 "envelope-history.expense-routing[" & Image (I) & "]";
               Effective_Value, Expense_Value, Route_Value,
                 Target_Value, Note_Value : TOML.TOML_Value;
               Has_Target : Boolean;
               Entry_Data : Expense_Routing_Entry_Data;
            begin
               if Item.Kind /= TOML.TOML_Table then
                  Set_Error (Diag, Source_Name, Path, "expected table", Item);
                  return False;
               elsif not Check_Keys
                 (Item,
                  "effective-from|expense-account|route|target|note",
                  Source_Name, Path, Diag)
                 or else not Require
                   (Item, "effective-from", TOML.TOML_String,
                    Source_Name, Path, Effective_Value, Diag)
                 or else not Require
                   (Item, "expense-account", TOML.TOML_String,
                    Source_Name, Path, Expense_Value, Diag)
                 or else not Require
                   (Item, "route", TOML.TOML_String,
                    Source_Name, Path, Route_Value, Diag)
                 or else not Optional
                   (Item, "target", TOML.TOML_String,
                    Source_Name, Path, Target_Value, Has_Target, Diag)
                 or else not Require
                   (Item, "note", TOML.TOML_String,
                    Source_Name, Path, Note_Value, Diag)
               then
                  return False;
               end if;

               if Effective_Value.As_String = "initial" then
                  Entry_Data.Effective := (Kind => Initial);
               else
                  declare
                     Parsed_Date : ALedger.Dates.Date;
                     D_Status    : ALedger.Dates.Date_Status;
                  begin
                     if not ALedger.Dates.Parse
                       (Effective_Value.As_String, Parsed_Date, D_Status)
                     then
                        Set_Error
                          (Diag, Source_Name, Path & ".effective-from",
                           "invalid Gregorian date: " &
                             Effective_Value.As_String,
                           Effective_Value);
                        return False;
                     end if;
                     Entry_Data.Effective :=
                       (Kind => From_Date, Date => Parsed_Date);
                  end;
               end if;

               if not Valid_Account (Expense_Value.As_String) then
                  Set_Error
                    (Diag, Source_Name, Path & ".expense-account",
                     "invalid Account identity", Expense_Value);
                  return False;
               end if;
               Entry_Data.Expense_Account :=
                 Expense_Value.As_Unbounded_String;
               Entry_Data.Note := Note_Value.As_Unbounded_String;

               if Route_Value.As_String = "managed" then
                  if not Has_Target then
                     Set_Error
                       (Diag, Source_Name, Path & ".target",
                        "required when route is 'managed'", Item);
                     return False;
                  end if;
                  Entry_Data.Route :=
                    (Kind   => Managed,
                     Target => Target_Value.As_Unbounded_String);
               elsif Route_Value.As_String = "unmanaged" then
                  if Has_Target then
                     Set_Error
                       (Diag, Source_Name, Path & ".target",
                        "must be absent when route is 'unmanaged'",
                        Target_Value);
                     return False;
                  end if;
                  Entry_Data.Route := (Kind => Not_Managed);
               else
                  Set_Error
                    (Diag, Source_Name, Path & ".route",
                     "expected 'managed' or 'unmanaged'", Route_Value);
                  return False;
               end if;

               Result.Envelope_History.Expense_Routing.Append (Entry_Data);
            end;
         end loop;
      end;

      declare
         Routing_Value : TOML.TOML_Value;
         Has_Routing   : Boolean;
      begin
         if not Optional
           (History_Section, "fulfillment-routing", TOML.TOML_Array,
            Source_Name, "envelope-history",
            Routing_Value, Has_Routing, Diag)
         then
            return False;
         end if;

         if Has_Routing then
            for I in 1 .. Routing_Value.Length loop
               declare
                  Item : constant TOML.TOML_Value := Routing_Value.Item (I);
                  Path : constant String :=
                    "envelope-history.fulfillment-routing[" &
                    Image (I) & "]";
                  Effective_Value, Plan_Value, Route_Value,
                    Target_Value, Note_Value : TOML.TOML_Value;
                  Has_Target : Boolean;
                  Entry_Data : Fulfillment_Routing_Entry_Data;
               begin
                  if Item.Kind /= TOML.TOML_Table then
                     Set_Error
                       (Diag, Source_Name, Path, "expected table", Item);
                     return False;
                  elsif not Check_Keys
                    (Item, "effective-from|plan-id|route|target|note",
                     Source_Name, Path, Diag)
                    or else not Require
                      (Item, "effective-from", TOML.TOML_String,
                       Source_Name, Path, Effective_Value, Diag)
                    or else not Require
                      (Item, "plan-id", TOML.TOML_String,
                       Source_Name, Path, Plan_Value, Diag)
                    or else not Require
                      (Item, "route", TOML.TOML_String,
                       Source_Name, Path, Route_Value, Diag)
                    or else not Optional
                      (Item, "target", TOML.TOML_String,
                       Source_Name, Path,
                       Target_Value, Has_Target, Diag)
                    or else not Require
                      (Item, "note", TOML.TOML_String,
                       Source_Name, Path, Note_Value, Diag)
                  then
                     return False;
                  end if;

                  declare
                     Parsed_Date : ALedger.Dates.Date;
                     D_Status    : ALedger.Dates.Date_Status;
                  begin
                     if not ALedger.Dates.Parse
                       (Effective_Value.As_String, Parsed_Date, D_Status)
                     then
                        Set_Error
                          (Diag, Source_Name, Path & ".effective-from",
                           "invalid Gregorian date: " &
                             Effective_Value.As_String,
                           Effective_Value);
                        return False;
                     end if;
                     Entry_Data.Effective_From := Parsed_Date;
                  end;

                  Entry_Data.Plan_ID := Plan_Value.As_Unbounded_String;
                  Entry_Data.Note := Note_Value.As_Unbounded_String;

                  if Route_Value.As_String = "fulfills" then
                     if not Has_Target then
                        Set_Error
                          (Diag, Source_Name, Path & ".target",
                           "required when route is 'fulfills'", Item);
                        return False;
                     end if;
                     Entry_Data.Route :=
                       (Kind   => Fulfills,
                        Target => Target_Value.As_Unbounded_String);
                  elsif Route_Value.As_String = "not-target" then
                     if Has_Target then
                        Set_Error
                          (Diag, Source_Name, Path & ".target",
                           "must be absent when route is 'not-target'",
                           Target_Value);
                        return False;
                     end if;
                     Entry_Data.Route := (Kind => Not_Target);
                  else
                     Set_Error
                       (Diag, Source_Name, Path & ".route",
                        "expected 'fulfills' or 'not-target'", Route_Value);
                     return False;
                  end if;

                  Result.Envelope_History.Fulfillment_Routing.Append
                    (Entry_Data);
               end;
            end loop;
         end if;
      end;

      Config := Result;
      return True;
   end Parse_Household_Configuration;

end ALedger.Household_Config;
