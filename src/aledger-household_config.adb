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
        or else not Check_Keys (Root, "cycle|money|budget|daily-target|account-policy", Source_Name, "", Diag)
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

      Config := Result;
      return True;
   end Parse_Household_Configuration;

end ALedger.Household_Config;
