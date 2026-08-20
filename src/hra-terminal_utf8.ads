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

end HRA.Terminal_UTF8;
