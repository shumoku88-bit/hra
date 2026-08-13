with Ada.Characters.Handling; use Ada.Characters.Handling;
with Ada.Strings.Fixed;            use Ada.Strings.Fixed;

package body ALedger.Account is

   function Lower_String (S : String) return String is
      Result : String (S'Range);
   begin
      for I in S'Range loop
         Result (I) := To_Lower (S (I));
      end loop;
      return Result;
   end Lower_String;

   function Account_Type_Image (Category : Account_Type) return String is
   begin
      case Category is
         when Asset     => return "Asset";
         when Liability => return "Liability";
         when Equity    => return "Equity";
         when Income    => return "Income";
         when Expense   => return "Expense";
         when Budget    => return "Budget";
      end case;
   end Account_Type_Image;

   function Create_Account
     (Name    : String;
      Acc     : out Account;
      Status  : out Account_Status) return Boolean
   is
   begin
      if Name'Length = 0 then
         Status := Empty_Account_Name;
         return False;
      end if;

      if Trim (Name, Ada.Strings.Both) /= Name then
         Status := Account_Has_Surrounding_Whitespace;
         return False;
      end if;

      --  Check for ASCII control characters (0..31, 127), allowing UTF-8 multibyte bytes (128..255)
      for I in Name'Range loop
         if Character'Pos (Name (I)) < 32 or else Character'Pos (Name (I)) = 127 then
            Status := Account_Contains_Control_Character;
            return False;
         end if;
      end loop;

      Acc := (Name_Text => To_Unbounded_String (Name));
      Status := Success;
      return True;
   end Create_Account;

   function Make_Account (Name : String) return Account is
      Acc    : Account;
      Status : Account_Status;
   begin
      if not Create_Account (Name, Acc, Status) then
         raise Constraint_Error with "Invalid account name: " & Name;
      end if;
      return Acc;
   end Make_Account;

   function Name (Acc : Account) return String is
   begin
      return To_String (Acc.Name_Text);
   end Name;

   function To_Unbounded (Acc : Account) return Unbounded_String is
   begin
      return Acc.Name_Text;
   end To_Unbounded;

   function "=" (Left, Right : Account) return Boolean is
   begin
      return Left.Name_Text = Right.Name_Text;
   end "=";

   function "<" (Left, Right : Account) return Boolean is
   begin
      return Left.Name_Text < Right.Name_Text;
   end "<";

   function Declare_Account
     (Acc      : Account;
      Acc_Type : Account_Type) return Account_Declaration
   is
      Dummy_Comm : Commodity;
   begin
      return (Acc                   => Acc,
              Acc_Type              => Acc_Type,
              Has_Default_Commodity => False,
              Default_Commodity     => Dummy_Comm);
   end Declare_Account;

   function Declare_Account_With_Default_Commodity
     (Acc       : Account;
      Acc_Type  : Account_Type;
      Default_C : Commodity) return Account_Declaration
   is
   begin
      return (Acc                   => Acc,
              Acc_Type              => Acc_Type,
              Has_Default_Commodity => True,
              Default_Commodity     => Default_C);
   end Declare_Account_With_Default_Commodity;

   function Empty_Registry return Account_Registry is
      Reg : Account_Registry;
   begin
      return Reg;
   end Empty_Registry;

   function Register_Account
     (Reg    : in out Account_Registry;
      Decl   : Account_Declaration;
      Status : out Registry_Status) return Boolean
   is
      Acc_Key : constant String := Name (Decl.Acc);
   begin
      if Reg.Map.Contains (Acc_Key) then
         Status := Duplicate_Account_Declaration;
         return False;
      end if;

      Reg.Map.Insert (Acc_Key, Decl);
      Status := Success;
      return True;
   end Register_Account;

   procedure Register_Or_Update_Account
     (Reg  : in out Account_Registry;
      Decl : Account_Declaration)
   is
      Acc_Key : constant String := Name (Decl.Acc);
   begin
      if Reg.Map.Contains (Acc_Key) then
         Reg.Map.Replace (Acc_Key, Decl);
      else
         Reg.Map.Insert (Acc_Key, Decl);
      end if;
   end Register_Or_Update_Account;

   function Infer_Account_Type_From_Name (Acc_Name : String; Category : out Account_Type) return Boolean is
      Lower : constant String := Lower_String (Acc_Name);
   begin
      if Lower'Length >= 7 and then Lower (Lower'First .. Lower'First + 6) = "assets:" then
         Category := Asset;
         return True;
      elsif Lower'Length >= 12 and then Lower (Lower'First .. Lower'First + 11) = "liabilities:" then
         Category := Liability;
         return True;
      elsif Lower'Length >= 7 and then Lower (Lower'First .. Lower'First + 6) = "equity:" then
         Category := Equity;
         return True;
      elsif Lower'Length >= 7 and then Lower (Lower'First .. Lower'First + 6) = "income:" then
         Category := Income;
         return True;
      elsif Lower'Length >= 9 and then Lower (Lower'First .. Lower'First + 8) = "expenses:" then
         Category := Expense;
         return True;
      elsif Lower'Length >= 7 and then Lower (Lower'First .. Lower'First + 6) = "budget:" then
         Category := Budget;
         return True;
      else
         return False;
      end if;
   end Infer_Account_Type_From_Name;

   function Lookup_Declaration
     (Reg  : Account_Registry;
      Acc  : Account;
      Decl : out Account_Declaration) return Boolean
   is
      Acc_Key : constant String := Name (Acc);
   begin
      if Reg.Map.Contains (Acc_Key) then
         Decl := Reg.Map.Element (Acc_Key);
         return True;
      else
         --  Fallback to inferring account category from standard prefix (e.g. assets:, expenses:)
         declare
            Inferred_Cat : Account_Type;
         begin
            if Infer_Account_Type_From_Name (Acc_Key, Inferred_Cat) then
               Decl := Declare_Account (Acc, Inferred_Cat);
               return True;
            else
               return False;
            end if;
         end;
      end if;
   end Lookup_Declaration;

   function Account_Type_For
     (Reg      : Account_Registry;
      Acc      : Account;
      Category : out Account_Type) return Boolean
   is
      Decl : Account_Declaration;
   begin
      if Lookup_Declaration (Reg, Acc, Decl) then
         Category := Decl.Acc_Type;
         return True;
      else
         return False;
      end if;
   end Account_Type_For;

   function Declarations (Reg : Account_Registry) return Declaration_Array is
      Arr    : Declaration_Array (1 .. Natural (Reg.Map.Length));
      Idx    : Positive := 1;
      Cursor : Registry_Maps.Cursor := Reg.Map.First;
   begin
      while Registry_Maps.Has_Element (Cursor) loop
         Arr (Idx) := Registry_Maps.Element (Cursor);
         Idx := Idx + 1;
         Registry_Maps.Next (Cursor);
      end loop;
      return Arr;
   end Declarations;

end ALedger.Account;
