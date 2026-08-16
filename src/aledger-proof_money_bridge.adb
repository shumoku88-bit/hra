package body ALedger.Proof_Money_Bridge is

   --  A decimal fixed-point view of the integer quanta count.  Quantity uses
   --  the same 10^-8 quantum as Proof_Core, so division/multiplication by
   --  Quantity'Small must round-trip exactly.  The explicit round-trip checks
   --  below are part of the fail-closed boundary rather than an assumption.
   type Quanta_Decimal is delta 1.0 digits 18;

   function To_Atomic_Quanta
     (Value  : ALedger.Money.Quantity;
      Result : out ALedger.Proof_Core.Atomic_Quanta;
      Status : out Bridge_Status) return Boolean
   is
      Scaled_Decimal : Quanta_Decimal;
      Scaled_Integer : Long_Long_Integer;
      Round_Trip     : ALedger.Money.Quantity;
   begin
      Result := 0;

      Scaled_Decimal :=
        Quanta_Decimal (Value / ALedger.Money.Quantity'Small);
      Scaled_Integer := Long_Long_Integer (Scaled_Decimal);
      Round_Trip :=
        ALedger.Money.Quantity
          (Scaled_Decimal * ALedger.Money.Quantity'Small);

      if Round_Trip /= Value then
         Status := Non_Exact_Conversion;
         return False;
      end if;

      if Scaled_Integer < Long_Long_Integer (ALedger.Proof_Core.Atomic_Quanta'First)
        or else
          Scaled_Integer > Long_Long_Integer (ALedger.Proof_Core.Atomic_Quanta'Last)
      then
         Status := Out_Of_Proof_Input_Range;
         return False;
      end if;

      Result := ALedger.Proof_Core.Atomic_Quanta (Scaled_Integer);
      Status := Success;
      return True;
   exception
      when Constraint_Error =>
         Result := 0;
         Status := Non_Exact_Conversion;
         return False;
   end To_Atomic_Quanta;

   function To_Money_Quantity
     (Value  : Long_Long_Integer;
      Result : out ALedger.Money.Quantity;
      Status : out Bridge_Status) return Boolean
   is
      Scaled_Decimal : Quanta_Decimal;
      Candidate      : ALedger.Money.Quantity;
      Round_Trip     : Long_Long_Integer;
   begin
      Result := ALedger.Money.Zero_Quantity;

      Scaled_Decimal := Quanta_Decimal (Value);
      Candidate :=
        ALedger.Money.Quantity
          (Scaled_Decimal * ALedger.Money.Quantity'Small);
      Round_Trip :=
        Long_Long_Integer
          (Quanta_Decimal
             (Candidate / ALedger.Money.Quantity'Small));

      if Round_Trip /= Value then
         Status := Non_Exact_Conversion;
         return False;
      end if;

      Result := Candidate;
      Status := Success;
      return True;
   exception
      when Constraint_Error =>
         Result := ALedger.Money.Zero_Quantity;
         Status := Out_Of_Money_Output_Range;
         return False;
   end To_Money_Quantity;

end ALedger.Proof_Money_Bridge;
