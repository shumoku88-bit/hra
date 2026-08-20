with Interfaces.C;
with Interfaces.C.Strings;

package body HRA.Terminal_UTF8 is

   package C renames Interfaces.C;
   package C_Strings renames Interfaces.C.Strings;

   function C_Initialize return C.int
     with Import,
          Convention    => C,
          External_Name => "hra_terminal_utf8_initialize";

   function C_Add_Line
     (Line        : C.int;
      Column      : C.int;
      Text        : C_Strings.chars_ptr;
      Max_Columns : C.int) return C.int
     with Import,
          Convention    => C,
          External_Name => "hra_terminal_utf8_add_line";

   procedure Initialize is
   begin
      if C_Initialize /= 0 then
         raise Program_Error with "unable to activate terminal locale";
      end if;
   end Initialize;

   procedure Add_Line
     (Line        : Natural;
      Column      : Natural;
      Max_Columns : Natural;
      Text        : String)
   is
      Ptr    : C_Strings.chars_ptr := C_Strings.New_String (Text);
      Result : C.int;
   begin
      Result :=
        C_Add_Line
          (C.int (Line),
           C.int (Column),
           Ptr,
           C.int (Max_Columns));
      C_Strings.Free (Ptr);

      if Result /= 0 then
         raise Program_Error with "unable to render UTF-8 terminal line";
      end if;
   exception
      when others =>
         if Ptr /= C_Strings.Null_Ptr then
            C_Strings.Free (Ptr);
         end if;
         raise;
   end Add_Line;

end HRA.Terminal_UTF8;
