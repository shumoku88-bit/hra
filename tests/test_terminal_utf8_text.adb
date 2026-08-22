with Ada.Command_Line;
with Ada.Text_IO; use Ada.Text_IO;
with HRA.Terminal_UTF8;

procedure Test_Terminal_UTF8_Text is
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

   House_UTF8 : constant String :=
     (1 => Character'Val (16#E5#),
      2 => Character'Val (16#AE#),
      3 => Character'Val (16#B6#));

   Frog_UTF8 : constant String :=
     (1 => Character'Val (16#F0#),
      2 => Character'Val (16#9F#),
      3 => Character'Val (16#90#),
      4 => Character'Val (16#B8#));

begin
   Put_Line ("--- Testing terminal UTF-8 text primitives ---");

   Assert
     (HRA.Terminal_UTF8.Is_Unicode_Scalar (Character'Pos ('A')),
      "ASCII code point is a Unicode scalar");
   Assert
     (not HRA.Terminal_UTF8.Is_Unicode_Scalar (16#D800#),
      "UTF-16 surrogate value is not a Unicode scalar");
   Assert
     (HRA.Terminal_UTF8.Is_Unicode_Scalar (16#10FFFF#),
      "maximum Unicode scalar is admitted");

   declare
      Value : constant String :=
        HRA.Terminal_UTF8.Append_Code_Point ("", 16#5BB6#);
   begin
      Assert
        (Value = House_UTF8,
         "three-byte Unicode code point is encoded to exact UTF-8 bytes");
      Assert
        (HRA.Terminal_UTF8.Drop_Last_Code_Point (Value) = "",
         "backspace removes a complete three-byte code point");
   end;

   declare
      Value : constant String :=
        HRA.Terminal_UTF8.Append_Code_Point ("A", 16#1F438#);
   begin
      Assert
        (Value = "A" & Frog_UTF8,
         "four-byte Unicode code point appends after existing text");
      Assert
        (HRA.Terminal_UTF8.Drop_Last_Code_Point (Value) = "A",
         "backspace removes a complete four-byte code point");
   end;

   Assert
     (HRA.Terminal_UTF8.Drop_Last_Code_Point ("AB") = "A",
      "ASCII backspace removes exactly one code point");
   Assert
     (HRA.Terminal_UTF8.Drop_Last_Code_Point ("") = "",
      "backspace on empty text remains empty");

   Put_Line
     ("Summary: Passed =" & Natural'Image (Passed_Count) &
      ", Failed =" & Natural'Image (Failed_Count));
   if Failed_Count > 0 then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   else
      Put_Line ("RESULT: SUCCESS");
   end if;
end Test_Terminal_UTF8_Text;
