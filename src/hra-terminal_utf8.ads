package HRA.Terminal_UTF8 is

   --  Activate the process locale for terminal UTF-8 operations. Call once at
   --  an explicit application or test boundary before terminal cell layout or
   --  Init_Screen. Raises Program_Error if the host locale cannot be activated.
   procedure Initialize;

   --  Draw one UTF-8 line on the standard curses window without splitting a
   --  multi-byte code point or a multi-column terminal glyph. The C boundary
   --  owns locale/wchar_t/wcwidth details; Household rendering stays UTF-8.
   procedure Add_Line
     (Line        : Natural;
      Column      : Natural;
      Max_Columns : Natural;
      Text        : String);

   --  Terminal input stays below Household interaction.
   --  Unicode code points and curses special-key codes are kept distinct so a
   --  delivery never confuses a Unicode code point with KEY_* integer space.
   subtype Unicode_Code_Point is Natural range 0 .. 16#10FFFF#;

   function Is_Unicode_Scalar (Code_Point : Natural) return Boolean;

   type Input_Kind is (Character_Input, Special_Key_Input);

   type Input_Event (Kind : Input_Kind := Character_Input) is record
      case Kind is
         when Character_Input =>
            Code_Point : Unicode_Code_Point;
         when Special_Key_Input =>
            Key_Code : Integer;
      end case;
   end record;

   type Decode_Status is
     (Incomplete,
      Decoded_Character,
      Decoded_Special_Key,
      Invalid_Sequence);

   type Decode_Result (Status : Decode_Status := Incomplete) is record
      case Status is
         when Decoded_Character =>
            Code_Point : Unicode_Code_Point;
         when Decoded_Special_Key =>
            Key_Code : Integer;
         when Incomplete
            | Invalid_Sequence =>
            null;
      end case;
   end record;

   type Decoder_State is private;

   function Initial_Decoder_State return Decoder_State;

   --  Feed one raw keystroke (either an octet in 0 .. 255 or a curses KEY_* >= 256)
   --  into the decoder state machine.
   function Feed_Keystroke
     (State : in out Decoder_State;
      Key   : Integer) return Decode_Result;

   --  Blocking UTF-8 / special-key read from the standard curses window.
   --  Initialize and Init_Screen must already have been called.
   function Read_Input return Input_Event;

   --  Small UTF-8 editing primitives used by terminal text fields. They operate
   --  on code-point boundaries, never by deleting a single byte from a
   --  multi-byte character.
   function Append_Code_Point
     (Text       : String;
      Code_Point : Unicode_Code_Point) return String
     with Pre => Is_Unicode_Scalar (Code_Point);

   function Drop_Last_Code_Point (Text : String) return String;

private

   type Decoder_State is record
      Remaining_Bytes : Natural range 0 .. 3 := 0;
      Accumulator     : Natural := 0;
      Min_Code_Point  : Natural := 0;
      Max_Code_Point  : Natural := 0;
   end record;

end HRA.Terminal_UTF8;
