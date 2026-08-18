package body ALedger.Dates is

   function Is_Leap_Year (Y : Year_Number) return Boolean is
     (Y mod 400 = 0 or else (Y mod 4 = 0 and then Y mod 100 /= 0));

   function Days_In_Month
     (Y : Year_Number;
      M : Month_Number) return Day_Number
   is
   begin
      return
        (case M is
            when 2 => (if Is_Leap_Year (Y) then 29 else 28),
            when 4 | 6 | 9 | 11 => 30,
            when others => 31);
   end Days_In_Month;

   function Parse
     (Text   : String;
      Value  : out Date;
      Status : out Date_Status) return Boolean
   is
      Y : Natural;
      M : Natural;
      D : Natural;
   begin
      if Text'Length /= 10
        or else Text (Text'First + 4) /= '-'
        or else Text (Text'First + 7) /= '-'
      then
         Status := Invalid_Format;
         return False;
      end if;

      for Offset in 0 .. 9 loop
         if Offset /= 4 and then Offset /= 7
           and then Text (Text'First + Offset) not in '0' .. '9'
         then
            Status := Invalid_Format;
            return False;
         end if;
      end loop;

      Y := Natural'Value (Text (Text'First .. Text'First + 3));
      M := Natural'Value (Text (Text'First + 5 .. Text'First + 6));
      D := Natural'Value (Text (Text'First + 8 .. Text'First + 9));

      if Y not in Year_Number
        or else M not in Month_Number
      then
         Status := Invalid_Gregorian_Date;
         return False;
      end if;

      declare
         Typed_Y : constant Year_Number := Year_Number (Y);
         Typed_M : constant Month_Number := Month_Number (M);
      begin
         if D = 0 or else D > Natural (Days_In_Month (Typed_Y, Typed_M)) then
            Status := Invalid_Gregorian_Date;
            return False;
         end if;

         Value :=
           (Y => Typed_Y,
            M => Typed_M,
            D => Day_Number (D));
      end;

      Status := Success;
      return True;
   exception
      when Constraint_Error =>
         Status := Invalid_Gregorian_Date;
         return False;
   end Parse;

   function Image (Value : Date) return String is
      Result : String (1 .. 10);
      Y      : constant Natural := Natural (Value.Y);
      M      : constant Natural := Natural (Value.M);
      D      : constant Natural := Natural (Value.D);
   begin
      Result (1)  := Character'Val (Character'Pos ('0') + (Y / 1_000) mod 10);
      Result (2)  := Character'Val (Character'Pos ('0') + (Y / 100) mod 10);
      Result (3)  := Character'Val (Character'Pos ('0') + (Y / 10) mod 10);
      Result (4)  := Character'Val (Character'Pos ('0') + Y mod 10);
      Result (5)  := '-';
      Result (6)  := Character'Val (Character'Pos ('0') + (M / 10) mod 10);
      Result (7)  := Character'Val (Character'Pos ('0') + M mod 10);
      Result (8)  := '-';
      Result (9)  := Character'Val (Character'Pos ('0') + (D / 10) mod 10);
      Result (10) := Character'Val (Character'Pos ('0') + D mod 10);
      return Result;
   end Image;

   function "<" (Left, Right : Date) return Boolean is
   begin
      return Left.Y < Right.Y
        or else (Left.Y = Right.Y and then Left.M < Right.M)
        or else
          (Left.Y = Right.Y
           and then Left.M = Right.M
           and then Left.D < Right.D);
   end "<";

   function "<=" (Left, Right : Date) return Boolean is
   begin
      return Left = Right or else Left < Right;
   end "<=";

   function ">" (Left, Right : Date) return Boolean is
   begin
      return Right < Left;
   end ">";

   function ">=" (Left, Right : Date) return Boolean is
   begin
      return Right <= Left;
   end ">=";

   function Next (Value : Date) return Date is
      Max_Day : constant Day_Number := Days_In_Month (Value.Y, Value.M);
   begin
      if Value.D < Max_Day then
         return (Y => Value.Y, M => Value.M, D => Value.D + 1);
      elsif Value.M < Month_Number'Last then
         return (Y => Value.Y, M => Value.M + 1, D => 1);
      elsif Value.Y < Year_Number'Last then
         return (Y => Value.Y + 1, M => 1, D => 1);
      else
         raise Constraint_Error with "Date successor is outside supported Gregorian range";
      end if;
   end Next;

   function Has_Previous (Value : Date) return Boolean is
   begin
      return not
        (Value.Y = Year_Number'First
         and then Value.M = Month_Number'First
         and then Value.D = Day_Number'First);
   end Has_Previous;

   function Previous (Value : Date) return Date is
   begin
      if Value.D > Day_Number'First then
         return (Y => Value.Y, M => Value.M, D => Value.D - 1);
      elsif Value.M > Month_Number'First then
         declare
            Previous_Month : constant Month_Number := Value.M - 1;
         begin
            return
              (Y => Value.Y,
               M => Previous_Month,
               D => Days_In_Month (Value.Y, Previous_Month));
         end;
      else
         declare
            Previous_Year : constant Year_Number := Value.Y - 1;
         begin
            return (Y => Previous_Year, M => 12, D => 31);
         end;
      end if;
   end Previous;

   function Year (Value : Date) return Positive is
     (Positive (Value.Y));

   function Month (Value : Date) return Positive is
     (Positive (Value.M));

   function Day (Value : Date) return Positive is
     (Positive (Value.D));

   function Make_Closed_Period
     (First  : Date;
      Last   : Date;
      Result : out Closed_Period) return Boolean
   is
   begin
      if First > Last then
         return False;
      end if;
      Result := (First_Date => First, Last_Date => Last);
      return True;
   end Make_Closed_Period;

   function First (Period : Closed_Period) return Date is
     (Period.First_Date);

   function Last (Period : Closed_Period) return Date is
     (Period.Last_Date);

   function Contains
     (Period : Closed_Period;
      Value  : Date) return Boolean
   is
   begin
      return Period.First_Date <= Value and then Value <= Period.Last_Date;
   end Contains;

   function Make_Half_Open_Period
     (First  : Date;
      Limit  : Date;
      Result : out Half_Open_Period) return Boolean
   is
   begin
      if First >= Limit then
         return False;
      end if;
      Result := (First_Date => First, Limit_Date => Limit);
      return True;
   end Make_Half_Open_Period;

   function First (Period : Half_Open_Period) return Date is
     (Period.First_Date);

   function Limit (Period : Half_Open_Period) return Date is
     (Period.Limit_Date);

   function Contains
     (Period : Half_Open_Period;
      Value  : Date) return Boolean
   is
   begin
      return Period.First_Date <= Value and then Value < Period.Limit_Date;
   end Contains;

end ALedger.Dates;
