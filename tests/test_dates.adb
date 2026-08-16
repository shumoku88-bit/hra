with Ada.Text_IO; use Ada.Text_IO;
with ALedger.Dates; use ALedger.Dates;

procedure Test_Dates is
   Passed_Count : Natural := 0;
   Failed_Count : Natural := 0;

   procedure Assert (Condition : Boolean; Test_Name : String) is
   begin
      if Condition then
         Put_Line ("[PASS] " & Test_Name);
         Passed_Count := Passed_Count + 1;
      else
         Put_Line ("[FAIL] " & Test_Name);
         Failed_Count := Failed_Count + 1;
      end if;
   end Assert;

   function Must_Date (Text : String) return Date is
      Value  : Date;
      Status : Date_Status;
   begin
      if not Parse (Text, Value, Status) then
         raise Program_Error with "test date failed to parse: " & Text;
      end if;
      return Value;
   end Must_Date;

   procedure Assert_Invalid (Text : String; Test_Name : String) is
      Value  : Date;
      Status : Date_Status;
   begin
      Assert (not Parse (Text, Value, Status), Test_Name);
   end Assert_Invalid;

begin
   Put_Line ("--- Testing ALedger.Dates ---");

   declare
      Value  : Date;
      Status : Date_Status;
   begin
      Assert
        (Parse ("2024-02-29", Value, Status)
           and then Status = Success
           and then Image (Value) = "2024-02-29",
         "admit and round-trip leap day");
   end;

   Assert_Invalid ("2026-02-29", "reject non-leap February 29");
   Assert_Invalid ("2026-02-30", "reject February 30");
   Assert_Invalid ("2026-04-31", "reject April 31");
   Assert_Invalid ("0000-01-01", "reject Gregorian year zero");
   Assert_Invalid ("2026-8-01", "reject non-canonical date format");

   Assert
     (Image (Next (Must_Date ("2026-01-31"))) = "2026-02-01",
      "successor crosses month boundary");
   Assert
     (Image (Next (Must_Date ("2024-02-28"))) = "2024-02-29",
      "successor enters leap day");
   Assert
     (Image (Next (Must_Date ("2024-02-29"))) = "2024-03-01",
      "successor leaves leap day");
   Assert
     (Image (Next (Must_Date ("2026-12-31"))) = "2027-01-01",
      "successor crosses year boundary");

   declare
      One_Day    : Closed_Period;
      Period_Val : Closed_Period;
   begin
      Assert
        (Make_Closed_Period
           (Must_Date ("2026-08-16"), Must_Date ("2026-08-16"), One_Day),
         "closed period admits one day");
      Assert
        (Contains (One_Day, Must_Date ("2026-08-16")),
         "closed period includes its only day");
      Assert
        (Make_Closed_Period
           (Must_Date ("2026-08-01"), Must_Date ("2026-08-31"), Period_Val)
           and then Contains (Period_Val, Must_Date ("2026-08-01"))
           and then Contains (Period_Val, Must_Date ("2026-08-31")),
         "closed period includes both boundaries");
      Assert
        (not Make_Closed_Period
           (Must_Date ("2026-08-31"), Must_Date ("2026-08-01"), Period_Val),
         "closed period rejects reversed boundaries");
   end;

   declare
      Period_Val : Half_Open_Period;
   begin
      Assert
        (Make_Half_Open_Period
           (Must_Date ("2026-08-01"), Must_Date ("2026-09-01"), Period_Val)
           and then Contains (Period_Val, Must_Date ("2026-08-01"))
           and then Contains (Period_Val, Must_Date ("2026-08-31"))
           and then not Contains (Period_Val, Must_Date ("2026-09-01")),
         "half-open period includes first and excludes limit");
      Assert
        (not Make_Half_Open_Period
           (Must_Date ("2026-08-01"), Must_Date ("2026-08-01"), Period_Val),
         "half-open period rejects empty window");
   end;

   Put_Line
     (Natural'Image (Passed_Count) & " passed, " &
      Natural'Image (Failed_Count) & " failed");

   if Failed_Count > 0 then
      raise Program_Error with "date tests failed";
   end if;
end Test_Dates;
