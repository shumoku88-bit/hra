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

   declare
      use type HRA.Terminal_UTF8.Decode_Status;
      use type HRA.Terminal_UTF8.Unicode_Code_Point;
      State : HRA.Terminal_UTF8.Decoder_State :=
        HRA.Terminal_UTF8.Initial_Decoder_State;
      Res   : HRA.Terminal_UTF8.Decode_Result;
   begin
      Res := HRA.Terminal_UTF8.Feed_Keystroke (State, Character'Pos ('Z'));
      Assert
        (Res.Status = HRA.Terminal_UTF8.Decoded_Character
         and then Res.Code_Point = Character'Pos ('Z'),
         "stream decoder decodes single-byte ASCII");

      Res := HRA.Terminal_UTF8.Feed_Keystroke (State, 263);
      Assert
        (Res.Status = HRA.Terminal_UTF8.Decoded_Special_Key
         and then Res.Key_Code = 263,
         "stream decoder decodes curses special key");

      Res := HRA.Terminal_UTF8.Feed_Keystroke (State, 16#C3#);
      Assert
        (Res.Status = HRA.Terminal_UTF8.Incomplete,
         "2-byte sequence byte 1 is incomplete");
      Res := HRA.Terminal_UTF8.Feed_Keystroke (State, 16#A9#);
      Assert
        (Res.Status = HRA.Terminal_UTF8.Decoded_Character
         and then Res.Code_Point = 16#E9#,
         "2-byte sequence decodes complete Unicode scalar");

      Res := HRA.Terminal_UTF8.Feed_Keystroke (State, 16#E5#);
      Assert
        (Res.Status = HRA.Terminal_UTF8.Incomplete,
         "3-byte sequence byte 1 is incomplete");
      Res := HRA.Terminal_UTF8.Feed_Keystroke (State, 16#AE#);
      Assert
        (Res.Status = HRA.Terminal_UTF8.Incomplete,
         "3-byte sequence byte 2 is incomplete");
      Res := HRA.Terminal_UTF8.Feed_Keystroke (State, 16#B6#);
      Assert
        (Res.Status = HRA.Terminal_UTF8.Decoded_Character
         and then Res.Code_Point = 16#5BB6#,
         "3-byte sequence decodes complete Kanji code point");

      Res := HRA.Terminal_UTF8.Feed_Keystroke (State, 16#F0#);
      Assert
        (Res.Status = HRA.Terminal_UTF8.Incomplete,
         "4-byte sequence byte 1 is incomplete");
      Res := HRA.Terminal_UTF8.Feed_Keystroke (State, 16#9F#);
      Assert
        (Res.Status = HRA.Terminal_UTF8.Incomplete,
         "4-byte sequence byte 2 is incomplete");
      Res := HRA.Terminal_UTF8.Feed_Keystroke (State, 16#90#);
      Assert
        (Res.Status = HRA.Terminal_UTF8.Incomplete,
         "4-byte sequence byte 3 is incomplete");
      Res := HRA.Terminal_UTF8.Feed_Keystroke (State, 16#B8#);
      Assert
        (Res.Status = HRA.Terminal_UTF8.Decoded_Character
         and then Res.Code_Point = 16#1F438#,
         "4-byte sequence decodes complete Emoji code point");

      --  Special key interrupts incomplete sequence
      Res := HRA.Terminal_UTF8.Feed_Keystroke (State, 16#E5#);
      Assert
        (Res.Status = HRA.Terminal_UTF8.Incomplete,
         "incomplete 3-byte start");
      Res := HRA.Terminal_UTF8.Feed_Keystroke (State, 259);
      Assert
        (Res.Status = HRA.Terminal_UTF8.Decoded_Special_Key
         and then Res.Key_Code = 259,
         "special key immediately interrupts incomplete sequence");

      --  Invalid byte validations
      Res := HRA.Terminal_UTF8.Feed_Keystroke (State, 16#80#);
      Assert
        (Res.Status = HRA.Terminal_UTF8.Invalid_Sequence,
         "stray continuation byte is rejected");

      Res := HRA.Terminal_UTF8.Feed_Keystroke (State, 16#C0#);
      Assert
        (Res.Status = HRA.Terminal_UTF8.Invalid_Sequence,
         "overlong leading byte 16#C0# is rejected");

      Res := HRA.Terminal_UTF8.Feed_Keystroke (State, 16#ED#);
      Assert (Res.Status = HRA.Terminal_UTF8.Incomplete, "ED is incomplete");
      Res := HRA.Terminal_UTF8.Feed_Keystroke (State, 16#A0#);
      Assert (Res.Status = HRA.Terminal_UTF8.Incomplete, "A0 is incomplete");
      Res := HRA.Terminal_UTF8.Feed_Keystroke (State, 16#80#);
      Assert
        (Res.Status = HRA.Terminal_UTF8.Invalid_Sequence,
         "UTF-16 surrogate code point 16#D800# is rejected");
   end;

   Put_Line
     ("Summary: Passed =" & Natural'Image (Passed_Count) &
      ", Failed =" & Natural'Image (Failed_Count));
   if Failed_Count > 0 then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   else
      Put_Line ("RESULT: SUCCESS");
   end if;
end Test_Terminal_UTF8_Text;
