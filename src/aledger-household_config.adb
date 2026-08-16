with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with TOML;
with ALedger.Account;
with ALedger.Money; use ALedger.Money;

package body ALedger.Household_Config is

   use type TOML.Any_Value_Kind;

   Source_Name : constant String := "household.toml";

   function Image (I : Positive) return String is
     (Trim (Positive'Image (I), Ada.Strings.Both));

   function Contains (Items : String_Vectors.Vector; Value : String) return Boolean is
   begin
      for Item of Items loop
         if Item = Value then return True; end if;
      end loop;
      return False;
   end Contains;

   function Valid_Account (Name : String) return Boolean is
      Acc : ALedger.Account.Account;
      Status : ALedger.Account.Account_Status;
   begin
      return ALedger.Account.Create_Account (Name, Acc, Status);
   end Valid_Account;

   function Read_Accounts
     (Value : TOML.TOML_Value; Path : String;
      Items : out String_Vectors.Vector; Diag : out Config_Diagnostic)
      return Boolean
   is
   begin
      if not Read_String_Array (Value, Source_Name, Path, Items, Diag) then
         return False;
      end if;
      for Item of Items loop
         if not Valid_Account (Item) then
            Set_Error (Diag, Source_Name, Path, "invalid Account identity", Value);
            return False;
         end if;
      end loop;
      return True;
   end Read_Accounts;

   function Require_Account_Array
     (Table : TOML.TOML_Value; Key, Path : String;
      Items : out String_Vectors.Vector; Diag : out Config_Diagnostic)
      return Boolean
   is
      Value : TOML.TOML_Value;
   begin
      return Require (Table, Key, TOML.TOML_Array, Source_Name, Path, Value, Diag)
        and then Read_Accounts (Value, Path & "." & Key, Items, Diag);
   end Require_Account_Array;

   function Check_Disjoint
     (First, Second, Third, Fourth : String_Vectors.Vector;
      Path : String; Diag : out Config_Diagnostic) return Boolean
   is
      Seen : String_Vectors.Vector;
      Valid : Boolean := True;
      procedure Add_Group (Group : String_Vectors.Vector) is
      begin
         for Item of Group loop
            if Contains (Seen, Item) then
               Set_Error (Diag, Source_Name, Path, "Account appears in more than one classification");
               Valid := False;
               return;
            end if;
            Seen.Append (Item);
         end loop;
      end Add_Group;
   begin
      Add_Group (First);
      if Valid then Add_Group (Second); end if;
      if Valid then Add_Group (Third); end if;
      if Valid then Add_Group (Fourth); end if;
      return Valid;
   end Check_Disjoint;

   function Parse_Account_Policy
     (Value : TOML.TOML_Value; Policy : out Account_Policy;
      Diag : out Config_Diagnostic) return Boolean
   is
      Assets, Budget, Expenses, Kinds, Roles, Groups : TOML.TOML_Value;
      Result : Account_Policy;
      Empty : String_Vectors.Vector;
   begin
      if not Check_Keys (Value, "assets|budget|expenses", Source_Name, "account-policy", Diag)
        or else not Require (Value, "assets", TOML.TOML_Table, Source_Name, "account-policy", Assets, Diag)
        or else not Require (Value, "budget", TOML.TOML_Table, Source_Name, "account-policy", Budget, Diag)
        or else not Require (Value, "expenses", TOML.TOML_Table, Source_Name, "account-policy", Expenses, Diag)
        or else not Check_Keys (Assets, "liquid|savings|investment", Source_Name, "account-policy.assets", Diag)
        or else not Require_Account_Array (Assets, "liquid", "account-policy.assets", Result.Liquid_Assets, Diag)
        or else not Require_Account_Array (Assets, "savings", "account-policy.assets", Result.Savings_Assets, Diag)
        or else not Require_Account_Array (Assets, "investment", "account-policy.assets", Result.Investment_Assets, Diag)
        or else not Check_Keys (Budget, "kind|envelope-role|group", Source_Name, "account-policy.budget", Diag)
        or else not Require (Budget, "kind", TOML.TOML_Table, Source_Name, "account-policy.budget", Kinds, Diag)
        or else not Require (Budget, "envelope-role", TOML.TOML_Table, Source_Name, "account-policy.budget", Roles, Diag)
        or else not Require (Budget, "group", TOML.TOML_Table, Source_Name, "account-policy.budget", Groups, Diag)
        or else not Check_Keys (Kinds, "opening|unassigned|spent|envelope", Source_Name, "account-policy.budget.kind", Diag)
        or else not Require_Account_Array (Kinds, "opening", "account-policy.budget.kind", Result.Opening_Budget, Diag)
        or else not Require_Account_Array (Kinds, "unassigned", "account-policy.budget.kind", Result.Unassigned_Budget, Diag)
        or else not Require_Account_Array (Kinds, "spent", "account-policy.budget.kind", Result.Spent_Budget, Diag)
        or else not Require_Account_Array (Kinds, "envelope", "account-policy.budget.kind", Result.Envelope_Budget, Diag)
        or else not Check_Keys (Roles, "unassigned|dynamic|execution", Source_Name, "account-policy.budget.envelope-role", Diag)
        or else not Require_Account_Array (Roles, "unassigned", "account-policy.budget.envelope-role", Result.Unassigned_Role, Diag)
        or else not Require_Account_Array (Roles, "dynamic", "account-policy.budget.envelope-role", Result.Dynamic_Role, Diag)
        or else not Require_Account_Array (Roles, "execution", "account-policy.budget.envelope-role", Result.Execution_Role, Diag)
        or else not Check_Keys (Groups, "daily|flex|reserve", Source_Name, "account-policy.budget.group", Diag)
        or else not Require_Account_Array (Groups, "daily", "account-policy.budget.group", Result.Daily_Group, Diag)
        or else not Require_Account_Array (Groups, "flex", "account-policy.budget.group", Result.Flex_Group, Diag)
        or else not Require_Account_Array (Groups, "reserve", "account-policy.budget.group", Result.Reserve_Group, Diag)
        or else not Check_Keys (Expenses, "fixed|variable", Source_Name, "account-policy.expenses", Diag)
        or else not Require_Account_Array (Expenses, "fixed", "account-policy.expenses", Result.Fixed_Expenses, Diag)
        or else not Require_Account_Array (Expenses, "variable", "account-policy.expenses", Result.Variable_Expenses, Diag)
        or else not Check_Disjoint (Result.Liquid_Assets, Result.Savings_Assets, Result.Investment_Assets, Empty, "account-policy.assets", Diag)
        or else not Check_Disjoint (Result.Opening_Budget, Result.Unassigned_Budget, Result.Spent_Budget, Result.Envelope_Budget, "account-policy.budget.kind", Diag)
        or else not Check_Disjoint (Result.Unassigned_Role, Result.Dynamic_Role, Result.Execution_Role, Empty, "account-policy.budget.envelope-role", Diag)
        or else not Check_Disjoint (Result.Daily_Group, Result.Flex_Group, Result.Reserve_Group, Empty, "account-policy.budget.group", Diag)
        or else not Check_Disjoint (Result.Fixed_Expenses, Result.Variable_Expenses, Empty, Empty, "account-policy.expenses", Diag)
      then
         return False;
      end if;
      Policy := Result;
      return True;
   end Parse_Account_Policy;

   function Parse_Household_Configuration
     (Text          : String;
      Budget_Policy : ALedger.Budget_Config.Budget_Policy;
      Config        : out Household_Configuration;
      Diag          : out Config_Diagnostic) return Boolean
   is
      Root, Cycle, Budget, Money, Daily_Target, Account_Policy_Value : TOML.TOML_Value;
      Mode_Value, Income_Value, Unassigned_Value, Envelopes_Value : TOML.TOML_Value;
      Commodity_Value, Assets_Value : TOML.TOML_Value;
      Has_Money, Has_Daily_Target, Has_Account_Policy : Boolean;
      Result : Household_Configuration;
      Known_Envelopes, Seen_Envelopes, Allocations, Destinations, Daily_IDs, Daily_Accounts : String_Vectors.Vector;
   begin
      for Envelope of Budget_Policy.Envelopes loop
         Known_Envelopes.Append (To_String (Envelope.ID));
      end loop;

      if not Parse_Root (Text, Source_Name, Root, Diag)
        or else not Check_Keys (Root, "cycle|money|budget|daily-target|account-policy|envelope-history", Source_Name, "", Diag)
        or else not Require (Root, "cycle", TOML.TOML_Table, Source_Name, "", Cycle, Diag)
        or else not Require (Root, "budget", TOML.TOML_Table, Source_Name, "", Budget, Diag)
        or else not Optional (Root, "money", TOML.TOML_Table, Source_Name, "", Money, Has_Money, Diag)
        or else not Optional (Root, "daily-target", TOML.TOML_Table, Source_Name, "", Daily_Target, Has_Daily_Target, Diag)
        or else not Optional (Root, "account-policy", TOML.TOML_Table, Source_Name, "", Account_Policy_Value, Has_Account_Policy, Diag)
        or else not Check_Keys (Cycle, "mode|income-account", Source_Name, "cycle", Diag)
        or else not Require (Cycle, "mode", TOML.TOML_String, Source_Name, "cycle", Mode_Value, Diag)
        or else not Require (Cycle, "income-account", TOML.TOML_String, Source_Name, "cycle", Income_Value, Diag)
      then
         return False;
      end if;

      if Mode_Value.As_String /= "income-anchor" then
         Set_Error (Diag, Source_Name, "cycle.mode", "expected income-anchor", Mode_Value);
         return False;
      elsif not Valid_Account (Income_Value.As_String) then
         Set_Error (Diag, Source_Name, "cycle.income-account", "invalid Account identity", Income_Value);
         return False;
      end if;
      Result.Cycle := Income_Anchor;
      Result.Cycle_Income_Account := Income_Value.As_Unbounded_String;

      if Has_Money then
         if not Check_Keys (Money, "primary-commodity", Source_Name, "money", Diag)
           or else not Require (Money, "primary-commodity", TOML.TOML_String, Source_Name, "money", Commodity_Value, Diag)
         then return False; end if;
         declare
            Status : Commodity_Status;
         begin
            if not Create_Commodity (Commodity_Value.As_String, Result.Primary_Commodity, Status) then
               Set_Error (Diag, Source_Name, "money.primary-commodity", "invalid Commodity", Commodity_Value);
               return False;
            end if;
         end;
         Result.Has_Primary_Commodity := True;
      end if;

      if not Check_Keys (Budget, "unassigned-accounts|envelopes", Source_Name, "budget", Diag)
        or else not Require (Budget, "unassigned-accounts", TOML.TOML_Array, Source_Name, "budget", Unassigned_Value, Diag)
        or else not Read_Accounts (Unassigned_Value, "budget.unassigned-accounts", Result.Unassigned_Accounts, Diag)
        or else not Require (Budget, "envelopes", TOML.TOML_Array, Source_Name, "budget", Envelopes_Value, Diag)
      then return False; end if;
      if Result.Unassigned_Accounts.Is_Empty then
         Set_Error (Diag, Source_Name, "budget.unassigned-accounts", "expected at least one unassigned Budget account", Unassigned_Value);
         return False;
      end if;

      for I in 1 .. Envelopes_Value.Length loop
         declare
            Item, ID_Value, Allocation_Value, Plan_Value : TOML.TOML_Value;
            Has_Plan : Boolean;
            Plans : String_Vectors.Vector;
            Path : constant String := "budget.envelopes[" & Image (I) & "]";
         begin
            Item := Envelopes_Value.Item (I);
            if Item.Kind /= TOML.TOML_Table then
               Set_Error (Diag, Source_Name, Path, "expected table", Item); return False;
            elsif not Check_Keys (Item, "id|allocation-account|plan-destination-accounts", Source_Name, Path, Diag)
              or else not Require (Item, "id", TOML.TOML_String, Source_Name, Path, ID_Value, Diag)
              or else not Require (Item, "allocation-account", TOML.TOML_String, Source_Name, Path, Allocation_Value, Diag)
              or else not Optional (Item, "plan-destination-accounts", TOML.TOML_Array, Source_Name, Path, Plan_Value, Has_Plan, Diag)
            then return False; end if;
            if Has_Plan and then not Read_Accounts (Plan_Value, Path & ".plan-destination-accounts", Plans, Diag) then return False; end if;
            if not Contains (Known_Envelopes, ID_Value.As_String) then
               Set_Error (Diag, Source_Name, Path & ".id", "unknown envelope", ID_Value); return False;
            elsif Contains (Seen_Envelopes, ID_Value.As_String) then
               Set_Error (Diag, Source_Name, Path & ".id", "duplicate envelope coordinates", ID_Value); return False;
            elsif not Valid_Account (Allocation_Value.As_String) then
               Set_Error (Diag, Source_Name, Path & ".allocation-account", "invalid Account identity", Allocation_Value); return False;
            elsif Contains (Allocations, Allocation_Value.As_String) or else Contains (Result.Unassigned_Accounts, Allocation_Value.As_String) then
               Set_Error (Diag, Source_Name, Path & ".allocation-account", "allocation Account is duplicated or unassigned", Allocation_Value); return False;
            end if;
            for Account_Name of Plans loop
               if Contains (Destinations, Account_Name) then
                  Set_Error (Diag, Source_Name, Path & ".plan-destination-accounts", "Plan destination belongs to multiple envelopes", Plan_Value); return False;
               end if;
               Destinations.Append (Account_Name);
            end loop;
            Seen_Envelopes.Append (ID_Value.As_String);
            Allocations.Append (Allocation_Value.As_String);
            Result.Envelopes.Append
              (Envelope_Coordinates'
                 (ID => ID_Value.As_Unbounded_String,
                  Allocation_Account => Allocation_Value.As_Unbounded_String,
                  Plan_Destination_Accounts => Plans));
         end;
      end loop;
      if Natural (Seen_Envelopes.Length) /= Natural (Known_Envelopes.Length) then
         Set_Error (Diag, Source_Name, "budget.envelopes", "every budget.toml envelope requires household coordinates", Envelopes_Value);
         return False;
      end if;

      if Has_Daily_Target then
         if not Check_Keys (Daily_Target, "assets", Source_Name, "daily-target", Diag)
           or else not Require (Daily_Target, "assets", TOML.TOML_Array, Source_Name, "daily-target", Assets_Value, Diag)
         then return False; end if;
         for I in 1 .. Assets_Value.Length loop
            declare
               Item, ID_Value, Account_Value : TOML.TOML_Value;
               Path : constant String := "daily-target.assets[" & Image (I) & "]";
            begin
               Item := Assets_Value.Item (I);
               if Item.Kind /= TOML.TOML_Table then Set_Error (Diag, Source_Name, Path, "expected table", Item); return False;
               elsif not Check_Keys (Item, "id|account", Source_Name, Path, Diag)
                 or else not Require (Item, "id", TOML.TOML_String, Source_Name, Path, ID_Value, Diag)
                 or else not Require (Item, "account", TOML.TOML_String, Source_Name, Path, Account_Value, Diag)
               then return False; end if;
               if ID_Value.As_String'Length = 0 or else Contains (Daily_IDs, ID_Value.As_String) then
                  Set_Error (Diag, Source_Name, Path & ".id", "empty or duplicate Daily Target identity", ID_Value); return False;
               elsif not Valid_Account (Account_Value.As_String) or else Contains (Daily_Accounts, Account_Value.As_String) then
                  Set_Error (Diag, Source_Name, Path & ".account", "invalid or duplicate Daily Target Account", Account_Value); return False;
               end if;
               Daily_IDs.Append (ID_Value.As_String); Daily_Accounts.Append (Account_Value.As_String);
               Result.Daily_Target_Assets.Append
                 (Daily_Target_Asset'
                    (ID => ID_Value.As_Unbounded_String,
                     Account => Account_Value.As_Unbounded_String));
            end;
         end loop;
      end if;

      if Has_Account_Policy then
         if not Parse_Account_Policy (Account_Policy_Value, Result.Accounts, Diag) then return False; end if;
         Result.Has_Account_Policy := True;
      end if;

      --  ========================================================================
      --  Parse [envelope-history] section (optional)
      --  ========================================================================
      declare
         History_Section : TOML.TOML_Value;
         Has_History     : Boolean;
      begin
         if not Optional (Root, "envelope-history", TOML.TOML_Table,
                          Source_Name, "", History_Section, Has_History, Diag)
         then
            return False;
         end if;

         if Has_History then
            if not Check_Keys
              (History_Section,
               "identities|expense-routing|fulfillment-routing",
               Source_Name, "envelope-history", Diag)
            then
               return False;
            end if;

            declare
               Identities_Value : TOML.TOML_Value;
               Has_Identities   : Boolean;
            begin
               if not Optional (History_Section, "identities", TOML.TOML_Array,
                                Source_Name, "envelope-history",
                                Identities_Value, Has_Identities, Diag)
               then
                  return False;
               end if;

               if Has_Identities then
                  for I in 1 .. Identities_Value.Length loop
                     declare
                        Item : constant TOML.TOML_Value := Identities_Value.Item (I);
                        Path : constant String :=
                          "envelope-history.identities[" & Image (I) & "]";
                     begin
                        if Item.Kind /= TOML.TOML_String then
                           Set_Error (Diag, Source_Name, Path,
                                      "expected string", Item);
                           return False;
                        end if;
                        Result.Envelope_History.Identities.Append
                          (Item.As_String);
                     end;
                  end loop;
               end if;
            end;

            declare
               Routing_Value : TOML.TOML_Value;
               Has_Routing   : Boolean;
            begin
               if not Optional (History_Section, "expense-routing",
                                TOML.TOML_Array,
                                Source_Name, "envelope-history",
                                Routing_Value, Has_Routing, Diag)
               then
                  return False;
               end if;

               if Has_Routing then
                  for I in 1 .. Routing_Value.Length loop
                     declare
                        Item : constant TOML.TOML_Value :=
                          Routing_Value.Item (I);
                        Path : constant String :=
                          "envelope-history.expense-routing["
                          & Image (I) & "]";
                        Effective_Value : TOML.TOML_Value;
                        Expense_Value   : TOML.TOML_Value;
                        Route_Value     : TOML.TOML_Value;
                        Target_Value    : TOML.TOML_Value;
                        Note_Value      : TOML.TOML_Value;
                        Has_Tgt, Has_Note : Boolean;
                        Entry_Data : Expense_Routing_Entry_Data;
                     begin
                        if Item.Kind /= TOML.TOML_Table then
                           Set_Error (Diag, Source_Name, Path,
                                      "expected table", Item);
                           return False;
                        end if;

                        if not Check_Keys
                          (Item,
                           "effective-from|expense-account|route|target|note",
                           Source_Name, Path, Diag)
                        then
                           return False;
                        end if;

                        if not Require (Item, "effective-from",
                                        TOML.TOML_String,
                                        Source_Name, Path,
                                        Effective_Value, Diag)
                        then return False; end if;

                        if not Require (Item, "expense-account",
                                        TOML.TOML_String,
                                        Source_Name, Path,
                                        Expense_Value, Diag)
                        then return False; end if;

                        if not Require (Item, "route", TOML.TOML_String,
                                        Source_Name, Path,
                                        Route_Value, Diag)
                        then return False; end if;

                        if not Optional (Item, "target",
                                         TOML.TOML_String,
                                         Source_Name, Path,
                                         Target_Value, Has_Tgt, Diag)
                        then return False; end if;

                        if not Optional (Item, "note", TOML.TOML_String,
                                         Source_Name, Path,
                                         Note_Value, Has_Note, Diag)
                        then return False; end if;

                        if Effective_Value.As_String = "initial" then
                           Entry_Data.Effective := (Kind => Initial);
                        else
                           declare
                              Parsed_Date : ALedger.Dates.Date;
                              D_Status    : ALedger.Dates.Date_Status;
                           begin
                              if not ALedger.Dates.Parse (Effective_Value.As_String, Parsed_Date, D_Status) then
                                 Set_Error
                                   (Diag, Source_Name, Path & ".effective-from",
                                    "invalid Gregorian date: " & Effective_Value.As_String,
                                    Effective_Value);
                                 return False;
                              end if;
                              Entry_Data.Effective :=
                                (Kind => From_Date,
                                 Date => Parsed_Date);
                           end;
                        end if;

                        Entry_Data.Expense_Account :=
                          Expense_Value.As_Unbounded_String;

                        if Route_Value.As_String = "managed" then
                           if not Has_Tgt then
                              Set_Error (Diag, Source_Name,
                                         Path & ".target",
                                         "required when route is 'managed'",
                                         Item);
                              return False;
                           end if;
                           Entry_Data.Route :=
                             (Kind   => Managed,
                              Target => Target_Value.As_Unbounded_String);
                        elsif Route_Value.As_String = "not-managed" then
                           Entry_Data.Route := (Kind => Not_Managed);
                        else
                           Set_Error (Diag, Source_Name,
                                      Path & ".route",
                                      "expected 'managed' or 'not-managed'",
                                      Route_Value);
                           return False;
                        end if;

                        if Has_Note then
                           Entry_Data.Note := Note_Value.As_Unbounded_String;
                        else
                           Entry_Data.Note := Null_Unbounded_String;
                        end if;

                        Result.Envelope_History.Expense_Routing.Append
                          (Entry_Data);
                     end;
                  end loop;
               end if;
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
                        Item : constant TOML.TOML_Value :=
                          Routing_Value.Item (I);
                        Path : constant String :=
                          "envelope-history.fulfillment-routing["
                          & Image (I) & "]";
                        Effective_Value : TOML.TOML_Value;
                        Plan_Value      : TOML.TOML_Value;
                        Route_Value     : TOML.TOML_Value;
                        Target_Value    : TOML.TOML_Value;
                        Note_Value      : TOML.TOML_Value;
                        Has_Target      : Boolean;
                        Entry_Data      : Fulfillment_Routing_Entry_Data;
                     begin
                        if Item.Kind /= TOML.TOML_Table then
                           Set_Error
                             (Diag, Source_Name, Path, "expected table", Item);
                           return False;
                        end if;

                        if not Check_Keys
                          (Item,
                           "effective-from|plan-id|route|target|note",
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
                           if not ALedger.Dates.Parse (Effective_Value.As_String, Parsed_Date, D_Status) then
                              Set_Error
                                (Diag, Source_Name, Path & ".effective-from",
                                 "invalid Gregorian date: " & Effective_Value.As_String,
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
                              "expected 'fulfills' or 'not-target'",
                              Route_Value);
                           return False;
                        end if;

                        Result.Envelope_History.Fulfillment_Routing.Append
                          (Entry_Data);
                     end;
                  end loop;
               end if;
            end;
         end if;
      end;

      Config := Result;
      return True;
   end Parse_Household_Configuration;

end ALedger.Household_Config;
