package HRA.Terminal_UTF8 is

   --  Establish the process locale required by ncursesw before Init_Screen.
   --  Raises Program_Error if the host locale cannot be activated.
   procedure Initialize;

   --  Draw one UTF-8 line on the standard curses window without splitting a
   --  multi-byte code point or a multi-column terminal glyph. The C boundary
   --  owns locale/wchar_t/wcwidth details; Household rendering stays UTF-8.
   procedure Add_Line
     (Line        : Natural;
      Column      : Natural;
      Max_Columns : Natural;
      Text        : String);

   --  Wide terminal input stays below Household interaction. ncursesw reports
   --  either one Unicode character/control code or one curses special-key code.
   --  The Ada side deliberately keeps those two shapes distinct so a delivery
   --  never confuses a Unicode code point with KEY_* integer space.
   subtype Unicode_Code_Point is Natural range 0 .. 16#10FFFF#;

   function Is_Unicode_Scalar (Code_Point : Unicode_Code_Point) return Boolean;

   type Input_Kind is (Character_Input, Special_Key_Input);

   type Input_Event (Kind : Input_Kind := Character_Input) is record
      case Kind is
         when Character_Input =>
            Code_Point : Unicode_Code_Point;
         when Special_Key_Input =>
            Key_Code : Integer;
      end case;
   end record;

   --  Blocking wide-character read from the standard curses window.
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

end HRA.Terminal_UTF8;
