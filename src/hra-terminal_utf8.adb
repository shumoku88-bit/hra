with Interfaces.C;
with Interfaces.C.Strings;

package body HRA.Terminal_UTF8 is

   package C renames Interfaces.C;
   package C_Strings renames Interfaces.C.Strings;
   use type C.int;
   use type C.unsigned;
   use type C_Strings.chars_ptr;

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

   function C_Read_Key
     (Kind  : access C.int;
      Value : access C.unsigned) return C.int
     with Import,
          Convention    => C,
          External_Name => "hra_terminal_utf8_read_key";

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

   function Is_Unicode_Scalar (Code_Point : Unicode_Code_Point) return Boolean is
     (Code_Point not in 16#D800# .. 16#DFFF#);

   function Read_Input return Input_Event is
      Kind  : aliased C.int := 0;
      Value : aliased C.unsigned := 0;
   begin
      if C_Read_Key (Kind'Access, Value'Access) /= 0 then
         raise Program_Error with "unable to read wide terminal input";
      end if;

      if Kind = 0 then
         if Value > C.unsigned (Unicode_Code_Point'Last) then
            raise Program_Error with "terminal returned an invalid Unicode code point";
         end if;

         declare
            Code : constant Unicode_Code_Point := Unicode_Code_Point (Value);
         begin
            if not Is_Unicode_Scalar (Code) then
               raise Program_Error with "terminal returned a non-scalar Unicode value";
            end if;
            return (Kind => Character_Input, Code_Point => Code);
         end;
      else
         return (Kind => Special_Key_Input, Key_Code => Integer (Value));
      end if;
   end Read_Input;

   function Append_Code_Point
     (Text       : String;
      Code_Point : Unicode_Code_Point) return String
   is
      function Byte (Value : Natural) return Character is
        (Character'Val (Value));
   begin
      if Code_Point <= 16#7F# then
         return Text & Byte (Code_Point);
      elsif Code_Point <= 16#7FF# then
         return
           Text &
           Byte (16#C0# + Code_Point / 64) &
           Byte (16#80# + Code_Point mod 64);
      elsif Code_Point <= 16#FFFF# then
         return
           Text &
           Byte (16#E0# + Code_Point / 4096) &
           Byte (16#80# + (Code_Point / 64) mod 64) &
           Byte (16#80# + Code_Point mod 64);
      else
         return
           Text &
           Byte (16#F0# + Code_Point / 262144) &
           Byte (16#80# + (Code_Point / 4096) mod 64) &
           Byte (16#80# + (Code_Point / 64) mod 64) &
           Byte (16#80# + Code_Point mod 64);
      end if;
   end Append_Code_Point;

   function Drop_Last_Code_Point (Text : String) return String is
      Start : Integer;
   begin
      if Text'Length = 0 then
         return "";
      end if;

      Start := Text'Last;
      while Start > Text'First
        and then Character'Pos (Text (Start)) in 16#80# .. 16#BF#
      loop
         Start := Start - 1;
      end loop;

      if Start = Text'First then
         return "";
      else
         return Text (Text'First .. Start - 1);
      end if;
   end Drop_Last_Code_Point;

end HRA.Terminal_UTF8;
