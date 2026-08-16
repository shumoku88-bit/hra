with Ada.Characters.Handling; use Ada.Characters.Handling;

package body ALedger.Plan is

   function Create_Plan_Id
     (Value  : String;
      PID    : out Plan_Id;
      Status : out Plan_Id_Status) return Boolean
   is
   begin
      if Value'Length = 0 then
         Status := Empty_Plan_Id;
         return False;
      end if;

      for I in Value'Range loop
         if Is_Space (Value (I)) then
            Status := Plan_Id_Contains_Whitespace;
            return False;
         elsif Character'Pos (Value (I)) < 32 or else Character'Pos (Value (I)) = 127 then
            Status := Plan_Id_Contains_Control_Character;
            return False;
         end if;
      end loop;

      PID := (ID_Text => To_Unbounded_String (Value));
      Status := Success;
      return True;
   end Create_Plan_Id;

   function Make_Plan_Id (Value : String) return Plan_Id is
      PID    : Plan_Id;
      Status : Plan_Id_Status;
   begin
      if not Create_Plan_Id (Value, PID, Status) then
         raise Constraint_Error with "Invalid plan-id: " & Value;
      end if;
      return PID;
   end Make_Plan_Id;

   function Null_Plan_Id return Plan_Id is
   begin
      return (ID_Text => Null_Unbounded_String);
   end Null_Plan_Id;

   function Is_Null (PID : Plan_Id) return Boolean is
   begin
      return Length (PID.ID_Text) = 0;
   end Is_Null;

   function Text (PID : Plan_Id) return String is
   begin
      return To_String (PID.ID_Text);
   end Text;

   function "=" (Left, Right : Plan_Id) return Boolean is
   begin
      return Left.ID_Text = Right.ID_Text;
   end "=";

   function Empty_Plan_Id_Universe return Plan_Id_Universe is
   begin
      return (Items => Plan_Id_Vectors.Empty_Vector);
   end Empty_Plan_Id_Universe;

   function Contains
     (Universe : Plan_Id_Universe;
      PID      : Plan_Id) return Boolean
   is
   begin
      for Existing of Universe.Items loop
         if Existing = PID then
            return True;
         end if;
      end loop;
      return False;
   end Contains;

   procedure Include
     (Universe : in out Plan_Id_Universe;
      PID      : Plan_Id)
   is
   begin
      if not Contains (Universe, PID) then
         Universe.Items.Append (PID);
      end if;
   end Include;

   function Length (Universe : Plan_Id_Universe) return Natural is
   begin
      return Natural (Universe.Items.Length);
   end Length;

   function Create_Plan_Entry
     (ID_Str   : String;
      Date_Val : ALedger.Dates.Date;
      Memo_Str : String;
      Amt      : Amount;
      From_Acc : Account.Account;
      To_Acc   : Account.Account;
      PE       : out Plan_Entry) return Boolean
   is
      PID    : Plan_Id;
      Status : Plan_Id_Status;
   begin
      if not Create_Plan_Id (ID_Str, PID, Status) then
         return False;
      end if;

      if Is_Zero (Amt.Val) then
         return False;
      end if;

      PE := (ID        => PID,
             Date      => Date_Val,
             Memo      => To_Unbounded_String (Memo_Str),
             Amt       => Amt,
             From_Acc  => From_Acc,
             To_Acc    => To_Acc,
             Status    => Pending,
             Successor => Null_Plan_Id);
      return True;
   end Create_Plan_Entry;

   function Create_Plan_Entry
     (ID_Str   : String;
      Date_Str : String;
      Memo_Str : String;
      Amt      : Amount;
      From_Acc : Account.Account;
      To_Acc   : Account.Account;
      PE       : out Plan_Entry) return Boolean
   is
      Date_Val : ALedger.Dates.Date;
      Status   : ALedger.Dates.Date_Status;
   begin
      if not ALedger.Dates.Parse (Date_Str, Date_Val, Status) then
         return False;
      end if;
      return Create_Plan_Entry (ID_Str, Date_Val, Memo_Str, Amt, From_Acc, To_Acc, PE);
   end Create_Plan_Entry;

   function Complete_Plan
     (P              : in out Plan_Entry;
      Execution_Date : ALedger.Dates.Date;
      Tx             : out Transaction) return Boolean
   is
      Postings  : Posting_Vectors.Vector;
      T_Stat    : Transaction_Error;
      Payee_Str : constant String := To_String (P.Memo) & " ; plan-id: " & Text (P.ID);
   begin
      if P.Status /= Pending then
         return False;
      end if;

      --  Debit destination (Expense/Liability) +Amt
      Postings.Append (Make_Posting (P.To_Acc, P.Amt));
      --  Credit source (Asset) -Amt
      Postings.Append (Make_Posting (P.From_Acc, Negate_Amount (P.Amt)));

      if not Create_Transaction (Execution_Date, Payee_Str, Postings, Tx, T_Stat) then
         return False;
      end if;

      P.Status := Completed;
      return True;
   end Complete_Plan;

   function Complete_Plan
     (P              : in out Plan_Entry;
      Execution_Date : String;
      Tx             : out Transaction) return Boolean
   is
      Date_Val : ALedger.Dates.Date;
      Status   : ALedger.Dates.Date_Status;
   begin
      if not ALedger.Dates.Parse (Execution_Date, Date_Val, Status) then
         return False;
      end if;
      return Complete_Plan (P, Date_Val, Tx);
   end Complete_Plan;

   procedure Cancel_Plan
     (P    : in out Plan_Entry;
      Date : ALedger.Dates.Date)
   is
      pragma Unreferenced (Date);
   begin
      P.Status := Canceled;
   end Cancel_Plan;

   procedure Cancel_Plan
     (P        : in out Plan_Entry;
      Date_Str : String)
   is
      pragma Unreferenced (Date_Str);
   begin
      P.Status := Canceled;
   end Cancel_Plan;

   procedure Supersede_Plan
     (P            : in out Plan_Entry;
      Date         : ALedger.Dates.Date;
      Successor_ID : Plan_Id)
   is
      pragma Unreferenced (Date);
   begin
      P.Status    := Superseded;
      P.Successor := Successor_ID;
   end Supersede_Plan;

   procedure Supersede_Plan
     (P            : in out Plan_Entry;
      Date_Str     : String;
      Successor_ID : Plan_Id)
   is
      pragma Unreferenced (Date_Str);
   begin
      P.Status    := Superseded;
      P.Successor := Successor_ID;
   end Supersede_Plan;

end ALedger.Plan;
