with Ada.Characters.Handling; use Ada.Characters.Handling;
with Ada.Strings.Fixed;            use Ada.Strings.Fixed;

package body ALedger.Money is

   --  ========================================================================
   --  Commodity Implementation
   --  ========================================================================

   function Create_Commodity
     (Code   : String;
      Symbol : out Commodity;
      Status : out Commodity_Status) return Boolean
   is
   begin
      if Code'Length = 0 then
         Status := Empty_Commodity_Code;
         return False;
      end if;

      for I in Code'Range loop
         if Is_Space (Code (I)) then
            Status := Commodity_Contains_Whitespace;
            return False;
         end if;
      end loop;

      Symbol := (Code_Text => To_Unbounded_String (Code));
      Status := Success;
      return True;
   end Create_Commodity;

   function Make_Commodity (Code : String) return Commodity is
      Result : Commodity;
      Status : Commodity_Status;
   begin
      if not Create_Commodity (Code, Result, Status) then
         raise Constraint_Error with "Invalid commodity code: " & Code;
      end if;
      return Result;
   end Make_Commodity;

   function Code (C : Commodity) return String is
   begin
      return To_String (C.Code_Text);
   end Code;

   function To_Unbounded (C : Commodity) return Unbounded_String is
   begin
      return C.Code_Text;
   end To_Unbounded;

   function "=" (Left, Right : Commodity) return Boolean is
   begin
      return Left.Code_Text = Right.Code_Text;
   end "=";

   function "<" (Left, Right : Commodity) return Boolean is
   begin
      return Left.Code_Text < Right.Code_Text;
   end "<";

   --  ========================================================================
   --  Quantity Implementation
   --  ========================================================================

   function Parse_Quantity (Input : String; Value : out Quantity) return Boolean is
      Trimmed : constant String := Trim (Input, Ada.Strings.Both);
   begin
      if Trimmed'Length = 0 then
         return False;
      end if;
      Value := Quantity'Value (Trimmed);
      return True;
   exception
      when others =>
         return False;
   end Parse_Quantity;

   function Render_Quantity (Q : Quantity) return String is
      Img : constant String := Quantity'Image (Q);
      Trimmed : constant String := Trim (Img, Ada.Strings.Both);
   begin
      --  Remove trailing fractional zeros if applicable
      if Index (Trimmed, ".") > 0 then
         declare
            Last_Non_Zero : Natural := Trimmed'Last;
         begin
            while Last_Non_Zero > Trimmed'First
              and then Trimmed (Last_Non_Zero) = '0'
            loop
               Last_Non_Zero := Last_Non_Zero - 1;
            end loop;
            if Trimmed (Last_Non_Zero) = '.' then
               Last_Non_Zero := Last_Non_Zero - 1;
            end if;
            return Trimmed (Trimmed'First .. Last_Non_Zero);
         end;
      else
         return Trimmed;
      end if;
   end Render_Quantity;

   function Is_Zero (Q : Quantity) return Boolean is
   begin
      return Q = Zero_Quantity;
   end Is_Zero;

   --  ========================================================================
   --  Amount Implementation
   --  ========================================================================

   function Make_Amount (C : Commodity; Q : Quantity) return Amount is
   begin
      return (Comm => C, Val => Q);
   end Make_Amount;

   function Negate_Amount (A : Amount) return Amount is
   begin
      return (Comm => A.Comm, Val => -A.Val);
   end Negate_Amount;

   --  ========================================================================
   --  Balance Implementation
   --  ========================================================================

   function Empty_Balance return Balance is
      B : Balance;
   begin
      return B;
   end Empty_Balance;

   function Singleton_Balance (A : Amount) return Balance is
      B : Balance;
   begin
      if not Is_Zero (A.Val) then
         B.Map.Insert (Code (A.Comm), A.Val);
      end if;
      return B;
   end Singleton_Balance;

   function Add_Balance (Left, Right : Balance) return Balance is
      Result : Balance := Left;
      Cursor : Commodity_Maps.Cursor := Right.Map.First;
   begin
      while Commodity_Maps.Has_Element (Cursor) loop
         declare
            C_Code : constant String := Commodity_Maps.Key (Cursor);
            C_Val  : constant Quantity := Commodity_Maps.Element (Cursor);
         begin
            if Result.Map.Contains (C_Code) then
               declare
                  New_Val : constant Quantity := Result.Map.Element (C_Code) + C_Val;
               begin
                  if Is_Zero (New_Val) then
                     Result.Map.Delete (C_Code);
                  else
                     Result.Map.Replace (C_Code, New_Val);
                  end if;
               end;
            else
               if not Is_Zero (C_Val) then
                  Result.Map.Insert (C_Code, C_Val);
               end if;
            end if;
         end;
         Commodity_Maps.Next (Cursor);
      end loop;
      return Result;
   end Add_Balance;

   function Negate_Balance (B : Balance) return Balance is
      Result : Balance;
      Cursor : Commodity_Maps.Cursor := B.Map.First;
   begin
      while Commodity_Maps.Has_Element (Cursor) loop
         Result.Map.Insert
           (Commodity_Maps.Key (Cursor),
            -Commodity_Maps.Element (Cursor));
         Commodity_Maps.Next (Cursor);
      end loop;
      return Result;
   end Negate_Balance;

   function Subtract_Balance (Left, Right : Balance) return Balance is
   begin
      return Add_Balance (Left, Negate_Balance (Right));
   end Subtract_Balance;

   function Lookup_Balance (B : Balance; C : Commodity) return Quantity is
      C_Code : constant String := Code (C);
   begin
      if B.Map.Contains (C_Code) then
         return B.Map.Element (C_Code);
      else
         return Zero_Quantity;
      end if;
   end Lookup_Balance;

   function Is_Zero_Balance (B : Balance) return Boolean is
   begin
      return B.Map.Is_Empty;
   end Is_Zero_Balance;

   function Entries (B : Balance) return Balance_Entry_Array is
      Arr : Balance_Entry_Array (1 .. Natural (B.Map.Length));
      Idx : Positive := 1;
      Cursor : Commodity_Maps.Cursor := B.Map.First;
   begin
      while Commodity_Maps.Has_Element (Cursor) loop
         Arr (Idx) :=
           (Comm => Make_Commodity (Commodity_Maps.Key (Cursor)),
            Val  => Commodity_Maps.Element (Cursor));
         Idx := Idx + 1;
         Commodity_Maps.Next (Cursor);
      end loop;
      return Arr;
   end Entries;

end ALedger.Money;
