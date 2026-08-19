with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with TOML;
with HRA.Account;

package body HRA.Budget_Config is

   use type TOML.Any_Value_Kind;

   Source_Name : constant String := "budget.toml";

   function Image (I : Positive) return String is
     (Trim (Positive'Image (I), Ada.Strings.Both));

   function Contains (Items : String_Vectors.Vector; Value : String) return Boolean is
   begin
      for Item of Items loop
         if Item = Value then
            return True;
         end if;
      end loop;
      return False;
   end Contains;

   function Valid_Identity (Value : String) return Boolean is
   begin
      if Value'Length = 0 then return False; end if;
      for C of Value loop
         if C <= ' ' or else C = ASCII.DEL then return False; end if;
      end loop;
      return True;
   end Valid_Identity;

   function Valid_Label (Value : String) return Boolean is
   begin
      if Value'Length = 0
        or else Value (Value'First) = ' '
        or else Value (Value'Last) = ' '
      then return False; end if;
      for C of Value loop
         if C < ' ' or else C = ASCII.DEL then return False; end if;
      end loop;
      return True;
   end Valid_Label;

   function Valid_Account (Name : String) return Boolean is
      Acc : HRA.Account.Account;
      Status : HRA.Account.Account_Status;
   begin
      return HRA.Account.Create_Account (Name, Acc, Status);
   end Valid_Account;

   function Parse_Budget_Policy
     (Text   : String;
      Policy : out Budget_Policy;
      Diag   : out Config_Diagnostic) return Boolean
   is
      Root, Pools, Envelopes : TOML.TOML_Value;
      Result : Budget_Policy;
      Pool_IDs, Asset_Accounts, Envelope_IDs, Envelope_Labels :
        String_Vectors.Vector;
   begin
      if not Parse_Root (Text, Source_Name, Root, Diag)
        or else not Check_Keys
          (Root, "backing-pools|envelopes", Source_Name, "", Diag)
        or else not Require
          (Root, "backing-pools", TOML.TOML_Array,
           Source_Name, "", Pools, Diag)
        or else not Require
          (Root, "envelopes", TOML.TOML_Array,
           Source_Name, "", Envelopes, Diag)
      then
         return False;
      end if;

      if Pools.Length = 0 then
         Set_Error
           (Diag, Source_Name, "backing-pools",
            "expected at least one backing pool", Pools);
         return False;
      elsif Envelopes.Length = 0 then
         Set_Error
           (Diag, Source_Name, "envelopes",
            "expected at least one envelope", Envelopes);
         return False;
      end if;

      for I in 1 .. Pools.Length loop
         declare
            Item, ID_Value, Accounts_Value : TOML.TOML_Value;
            Accounts : String_Vectors.Vector;
            Path : constant String :=
              "backing-pools[" & Image (I) & "]";
         begin
            Item := Pools.Item (I);
            if Item.Kind /= TOML.TOML_Table then
               Set_Error (Diag, Source_Name, Path, "expected table", Item);
               return False;
            elsif not Check_Keys
              (Item, "id|asset-accounts", Source_Name, Path, Diag)
              or else not Require
                (Item, "id", TOML.TOML_String,
                 Source_Name, Path, ID_Value, Diag)
              or else not Require
                (Item, "asset-accounts", TOML.TOML_Array,
                 Source_Name, Path, Accounts_Value, Diag)
              or else not Read_String_Array
                (Accounts_Value, Source_Name,
                 Path & ".asset-accounts", Accounts, Diag)
            then
               return False;
            elsif not Valid_Identity (ID_Value.As_String) then
               Set_Error
                 (Diag, Source_Name, Path & ".id",
                  "expected non-empty identity without whitespace or controls",
                  ID_Value);
               return False;
            elsif Contains (Pool_IDs, ID_Value.As_String) then
               Set_Error
                 (Diag, Source_Name, Path & ".id",
                  "duplicate backing pool identity", ID_Value);
               return False;
            elsif Accounts.Is_Empty then
               Set_Error
                 (Diag, Source_Name, Path & ".asset-accounts",
                  "expected at least one Asset account", Accounts_Value);
               return False;
            end if;

            for Account_Name of Accounts loop
               if not Valid_Account (Account_Name) then
                  Set_Error
                    (Diag, Source_Name, Path & ".asset-accounts",
                     "invalid Account identity", Accounts_Value);
                  return False;
               elsif Contains (Asset_Accounts, Account_Name) then
                  Set_Error
                    (Diag, Source_Name, Path & ".asset-accounts",
                     "Asset account belongs to multiple backing pools",
                     Accounts_Value);
                  return False;
               end if;
               Asset_Accounts.Append (Account_Name);
            end loop;
            Pool_IDs.Append (ID_Value.As_String);
            Result.Backing_Pools.Append
              (Backing_Pool_Definition'
                 (ID             => ID_Value.As_Unbounded_String,
                  Asset_Accounts => Accounts));
         end;
      end loop;

      for I in 1 .. Envelopes.Length loop
         declare
            Item, ID_Value, Label_Value, Pacing_Value, Pool_Value :
              TOML.TOML_Value;
            Pacing : Pacing_Kind;
            Path : constant String :=
              "envelopes[" & Image (I) & "]";
         begin
            Item := Envelopes.Item (I);
            if Item.Kind /= TOML.TOML_Table then
               Set_Error (Diag, Source_Name, Path, "expected table", Item);
               return False;
            elsif not Check_Keys
              (Item, "id|label|pacing|backing-pool",
               Source_Name, Path, Diag)
              or else not Require
                (Item, "id", TOML.TOML_String,
                 Source_Name, Path, ID_Value, Diag)
              or else not Require
                (Item, "label", TOML.TOML_String,
                 Source_Name, Path, Label_Value, Diag)
              or else not Require
                (Item, "pacing", TOML.TOML_String,
                 Source_Name, Path, Pacing_Value, Diag)
              or else not Require
                (Item, "backing-pool", TOML.TOML_String,
                 Source_Name, Path, Pool_Value, Diag)
            then
               return False;
            elsif not Valid_Identity (ID_Value.As_String) then
               Set_Error
                 (Diag, Source_Name, Path & ".id",
                  "expected non-empty identity without whitespace or controls",
                  ID_Value);
               return False;
            elsif not Valid_Label (Label_Value.As_String) then
               Set_Error
                 (Diag, Source_Name, Path & ".label",
                  "expected non-empty label without surrounding whitespace or controls",
                  Label_Value);
               return False;
            elsif Contains (Envelope_IDs, ID_Value.As_String) then
               Set_Error
                 (Diag, Source_Name, Path & ".id",
                  "duplicate envelope identity", ID_Value);
               return False;
            elsif Contains (Envelope_Labels, Label_Value.As_String) then
               Set_Error
                 (Diag, Source_Name, Path & ".label",
                  "duplicate envelope label", Label_Value);
               return False;
            elsif not Contains (Pool_IDs, Pool_Value.As_String) then
               Set_Error
                 (Diag, Source_Name, Path & ".backing-pool",
                  "unknown backing pool", Pool_Value);
               return False;
            end if;

            if Pacing_Value.As_String = "daily" then
               Pacing := Daily;
            elsif Pacing_Value.As_String = "flex" then
               Pacing := Flex;
            else
               Set_Error
                 (Diag, Source_Name, Path & ".pacing",
                  "expected daily or flex", Pacing_Value);
               return False;
            end if;

            Envelope_IDs.Append (ID_Value.As_String);
            Envelope_Labels.Append (Label_Value.As_String);
            Result.Envelopes.Append
              (Envelope_Definition'
                 (ID           => ID_Value.As_Unbounded_String,
                  Label        => Label_Value.As_Unbounded_String,
                  Pacing       => Pacing,
                  Backing_Pool => Pool_Value.As_Unbounded_String));
         end;
      end loop;

      Policy := Result;
      return True;
   end Parse_Budget_Policy;

end HRA.Budget_Config;
