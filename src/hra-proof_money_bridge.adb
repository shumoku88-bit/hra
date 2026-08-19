package body HRA.Proof_Money_Bridge is

   use type HRA.Money.Quantity;

   --  A decimal fixed-point view of the integer quanta count. Quantity uses
   --  the same 10^-8 quantum as Proof_Core, so division/multiplication by
   --  Quantity'Small must round-trip exactly. The explicit round-trip checks
   --  below are part of the fail-closed boundary rather than an assumption.
   type Quanta_Decimal is delta 1.0 digits 18;

   function To_Atomic_Quanta
     (Value  : HRA.Money.Quantity;
      Result : out HRA.Proof_Core.Atomic_Quanta;
      Status : out Bridge_Status) return Boolean
   is
      Scaled_Decimal : Quanta_Decimal;
      Scaled_Integer : Long_Long_Integer;
      Round_Trip     : HRA.Money.Quantity;
   begin
      Result := 0;

      Scaled_Decimal :=
        Quanta_Decimal (Value / HRA.Money.Quantity'Small);
      Scaled_Integer := Long_Long_Integer (Scaled_Decimal);
      Round_Trip :=
        HRA.Money.Quantity
          (Scaled_Decimal * HRA.Money.Quantity'Small);

      if Round_Trip /= Value then
         Status := Non_Exact_Conversion;
         return False;
      end if;

      if Scaled_Integer < Long_Long_Integer (HRA.Proof_Core.Atomic_Quanta'First)
        or else
          Scaled_Integer > Long_Long_Integer (HRA.Proof_Core.Atomic_Quanta'Last)
      then
         Status := Out_Of_Proof_Input_Range;
         return False;
      end if;

      Result := HRA.Proof_Core.Atomic_Quanta (Scaled_Integer);
      Status := Success;
      return True;
   exception
      when Constraint_Error =>
         Result := 0;
         Status := Non_Exact_Conversion;
         return False;
   end To_Atomic_Quanta;

   function Balance_To_Atomic_Quanta
     (Value     : HRA.Money.Balance;
      Commodity : HRA.Money.Commodity;
      Result    : out HRA.Proof_Core.Atomic_Quanta;
      Status    : out Bridge_Status) return Boolean
   is
   begin
      return To_Atomic_Quanta
        (HRA.Money.Lookup_Balance (Value, Commodity), Result, Status);
   end Balance_To_Atomic_Quanta;

   function To_Money_Quantity
     (Value  : Long_Long_Integer;
      Result : out HRA.Money.Quantity;
      Status : out Bridge_Status) return Boolean
   is
      Scaled_Decimal : Quanta_Decimal;
      Candidate      : HRA.Money.Quantity;
      Round_Trip     : Long_Long_Integer;
   begin
      Result := HRA.Money.Zero_Quantity;

      Scaled_Decimal := Quanta_Decimal (Value);
      Candidate :=
        HRA.Money.Quantity
          (Scaled_Decimal * HRA.Money.Quantity'Small);
      Round_Trip :=
        Long_Long_Integer
          (Quanta_Decimal
             (Candidate / HRA.Money.Quantity'Small));

      if Round_Trip /= Value then
         Status := Non_Exact_Conversion;
         return False;
      end if;

      Result := Candidate;
      Status := Success;
      return True;
   exception
      when Constraint_Error =>
         Result := HRA.Money.Zero_Quantity;
         Status := Out_Of_Money_Output_Range;
         return False;
   end To_Money_Quantity;

   function To_Singleton_Balance
     (Commodity : HRA.Money.Commodity;
      Value     : Long_Long_Integer;
      Result    : out HRA.Money.Balance;
      Status    : out Bridge_Status) return Boolean
   is
      Quantity_Result : HRA.Money.Quantity;
   begin
      Result := HRA.Money.Empty_Balance;

      if not To_Money_Quantity (Value, Quantity_Result, Status) then
         return False;
      end if;

      Result := HRA.Money.Singleton_Balance
        (HRA.Money.Make_Amount (Commodity, Quantity_Result));
      Status := Success;
      return True;
   end To_Singleton_Balance;

end HRA.Proof_Money_Bridge;
