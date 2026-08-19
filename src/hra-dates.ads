package HRA.Dates is

   type Date is private;

   type Date_Status is
     (Success,
      Invalid_Format,
      Invalid_Gregorian_Date);

   function Parse
     (Text   : String;
      Value  : out Date;
      Status : out Date_Status) return Boolean;

   function Image (Value : Date) return String;

   function "<"  (Left, Right : Date) return Boolean;
   function "<=" (Left, Right : Date) return Boolean;
   function ">"  (Left, Right : Date) return Boolean;
   function ">=" (Left, Right : Date) return Boolean;

   function Has_Next (Value : Date) return Boolean;
   function Next (Value : Date) return Date
     with Pre => Has_Next (Value);

   --  Date is intentionally bounded to Gregorian years 1 .. 9999. Previous is
   --  therefore a partial temporal operation with an explicit predicate rather
   --  than a hidden wraparound or sentinel value.
   function Has_Previous (Value : Date) return Boolean;
   function Previous (Value : Date) return Date
     with Pre => Has_Previous (Value);

   function Year  (Value : Date) return Positive;
   function Month (Value : Date) return Positive;
   function Day   (Value : Date) return Positive;

   function First_Of_Month (Value : Date) return Date;
   function Last_Of_Month  (Value : Date) return Date;

   type Day_Of_Week is
     (Monday,
      Tuesday,
      Wednesday,
      Thursday,
      Friday,
      Saturday,
      Sunday);

   function Day_Of_Week_Of (Value : Date) return Day_Of_Week;

   function Days_In_Month
     (Year  : Positive;
      Month : Positive) return Positive
     with Pre => Year in 1 .. 9_999 and then Month in 1 .. 12;

   type Closed_Period is private;

   function Make_Closed_Period
     (First  : Date;
      Last   : Date;
      Result : out Closed_Period) return Boolean;

   function First (Period : Closed_Period) return Date;
   function Last  (Period : Closed_Period) return Date;

   function Contains
     (Period : Closed_Period;
      Value  : Date) return Boolean;

   type Half_Open_Period is private;

   function Make_Half_Open_Period
     (First  : Date;
      Limit  : Date;
      Result : out Half_Open_Period) return Boolean;

   function First (Period : Half_Open_Period) return Date;
   function Limit (Period : Half_Open_Period) return Date;

   function Contains
     (Period : Half_Open_Period;
      Value  : Date) return Boolean;

private

   subtype Year_Number  is Positive range 1 .. 9_999;
   subtype Month_Number is Positive range 1 .. 12;
   subtype Day_Number   is Positive range 1 .. 31;

   --  Defaults are valid private representation values so temporary records and
   --  out parameters never contain range-invalid scalar components. Domain
   --  construction still goes through Parse / period constructors.
   type Date is record
      Y : Year_Number  := 1;
      M : Month_Number := 1;
      D : Day_Number   := 1;
   end record;

   type Closed_Period is record
      First_Date : Date;
      Last_Date  : Date;
   end record;

   type Half_Open_Period is record
      First_Date : Date;
      Limit_Date : Date;
   end record;

end HRA.Dates;
