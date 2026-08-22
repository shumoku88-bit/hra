with Interfaces.C;
with Interfaces.C.Strings;

package body HRA.Terminal_Layout is

   package C renames Interfaces.C;
   package C_Strings renames Interfaces.C.Strings;
   use type C.int;
   use type C_Strings.chars_ptr;

   function C_Display_Width (Text : C_Strings.chars_ptr) return C.int
     with Import,
          Convention    => C,
          External_Name => "hra_terminal_utf8_display_width";

   function Display_Width (Text : String) return Natural is
      Ptr    : C_Strings.chars_ptr := C_Strings.New_String (Text);
      Result : C.int;
   begin
      Result := C_Display_Width (Ptr);
      C_Strings.Free (Ptr);

      if Result < 0 then
         raise Constraint_Error with "invalid UTF-8 terminal text";
      end if;
      return Natural (Result);
   exception
      when others =>
         if Ptr /= C_Strings.Null_Ptr then
            C_Strings.Free (Ptr);
         end if;
         raise;
   end Display_Width;

   function Padding (Text : String; Width : Natural) return String is
      Used : constant Natural := Display_Width (Text);
   begin
      if Used >= Width then
         return "";
      end if;
      return [1 .. Width - Used => ' '];
   end Padding;

   function Pad_Left (Text : String; Width : Natural) return String is
     (Padding (Text, Width) & Text);

   function Pad_Right (Text : String; Width : Natural) return String is
     (Text & Padding (Text, Width));

   function Align
     (Text          : String;
      Width         : Natural;
      Justification : Alignment) return String
   is
     (case Justification is
         when Left  => Pad_Right (Text, Width),
         when Right => Pad_Left (Text, Width));

end HRA.Terminal_Layout;
