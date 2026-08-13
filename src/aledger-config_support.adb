with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with Interfaces;

package body ALedger.Config_Support is

   use type TOML.Any_Value_Kind;

   function Format_Diagnostic (Diag : Config_Diagnostic) return String is
      Prefix : Unbounded_String := Diag.Source_Name;
   begin
      if Diag.Line > 0 then
         Append (Prefix, ":" & Trim (Natural'Image (Diag.Line), Ada.Strings.Both));
         if Diag.Column > 0 then
            Append (Prefix, ":" & Trim (Natural'Image (Diag.Column), Ada.Strings.Both));
         end if;
      end if;
      if Length (Diag.Path) > 0 then
         Append (Prefix, ": " & To_String (Diag.Path));
      end if;
      return To_String (Prefix) & ": " & To_String (Diag.Message);
   end Format_Diagnostic;

   procedure Set_Error
     (Diag        : out Config_Diagnostic;
      Source_Name : String;
      Path        : String;
      Message     : String;
      Value       : TOML.TOML_Value := TOML.No_TOML_Value)
   is
      Loc : TOML.Source_Location := TOML.No_Location;
   begin
      if Value.Is_Present then
         Loc := Value.Location;
      end if;
      Diag :=
        (Source_Name => To_Unbounded_String (Source_Name),
         Path        => To_Unbounded_String (Path),
         Message     => To_Unbounded_String (Message),
         Line        => Loc.Line,
         Column      => Loc.Column);
   end Set_Error;

   function Parser_Compatible_UTF8 (Text : String) return String is
      use type Interfaces.Unsigned_32;
      Result       : Unbounded_String;
      In_String    : Boolean := False;
      In_Comment   : Boolean := False;
      Escaped      : Boolean := False;
      I            : Natural := Text'First;

      function Hex (Value : Interfaces.Unsigned_32; Width : Positive) return String is
         Hex_Digits : constant String := "0123456789ABCDEF";
         Item   : Interfaces.Unsigned_32 := Value;
         Image  : String (1 .. Width);
      begin
         for J in reverse Image'Range loop
            Image (J) := Hex_Digits (Natural (Item mod 16) + 1);
            Item := Item / 16;
         end loop;
         return Image;
      end Hex;
   begin
      --  ada_toml 0.5.0 incorrectly rejects valid three-byte codepoints below
      --  U+8000. Canonical non-ASCII values use TOML basic strings, so encode
      --  those codepoints as standard TOML escapes before parsing. Comments
      --  have no semantic value and are replaced without changing line count.
      while I <= Text'Last loop
         declare
            First : constant Natural := Character'Pos (Text (I));
         begin
            if First < 16#80# then
               declare
                  C : constant Character := Text (I);
               begin
                  Append (Result, C);
                  if In_Comment then
                     if C = ASCII.LF then In_Comment := False; end if;
                  elsif In_String then
                     if C = '"' and then not Escaped then In_String := False; end if;
                     if C = '\' and then not Escaped then Escaped := True; else Escaped := False; end if;
                  elsif C = '#' then
                     In_Comment := True;
                  elsif C = '"' then
                     In_String := True;
                     Escaped := False;
                  end if;
                  I := I + 1;
               end;
            else
               declare
                  Count : Positive;
                  Code  : Interfaces.Unsigned_32;
               begin
                  if First in 16#C2# .. 16#DF# then Count := 2; Code := Interfaces.Unsigned_32 (First mod 32);
                  elsif First in 16#E0# .. 16#EF# then Count := 3; Code := Interfaces.Unsigned_32 (First mod 16);
                  elsif First in 16#F0# .. 16#F4# then Count := 4; Code := Interfaces.Unsigned_32 (First mod 8);
                  else return Text; end if;
                  if I + Count - 1 > Text'Last then return Text; end if;
                  for J in I + 1 .. I + Count - 1 loop
                     declare B : constant Natural := Character'Pos (Text (J)); begin
                        if B not in 16#80# .. 16#BF# then return Text; end if;
                        Code := Code * 64 + Interfaces.Unsigned_32 (B mod 64);
                     end;
                  end loop;
                  if (Count = 2 and then Code < 16#80#)
                    or else (Count = 3 and then Code < 16#800#)
                    or else (Count = 4 and then Code < 16#1_0000#)
                    or else Code > 16#10_FFFF#
                    or else Code in 16#D800# .. 16#DFFF#
                  then
                     return Text;
                  end if;
                  if In_String then
                     if Code <= 16#FFFF# then Append (Result, "\u" & Hex (Code, 4));
                     else Append (Result, "\U" & Hex (Code, 8)); end if;
                  elsif In_Comment then
                     Append (Result, '?');
                  else
                     --  Non-ASCII bare keys/literal strings are not part of
                     --  the shared schema; leave them for the parser to reject.
                     Append (Result, Text (I .. I + Count - 1));
                  end if;
                  I := I + Count;
               end;
            end if;
         end;
      end loop;
      return To_String (Result);
   end Parser_Compatible_UTF8;

   function Parse_Root
     (Text        : String;
      Source_Name : String;
      Root        : out TOML.TOML_Value;
      Diag        : out Config_Diagnostic) return Boolean
   is
      Result : constant TOML.Read_Result :=
        TOML.Load_String (Parser_Compatible_UTF8 (Text));
   begin
      if not Result.Success then
         Diag :=
           (Source_Name => To_Unbounded_String (Source_Name),
            Path        => Null_Unbounded_String,
            Message     => Result.Message,
            Line        => Result.Location.Line,
            Column      => Result.Location.Column);
         return False;
      elsif Result.Value.Kind /= TOML.TOML_Table then
         Set_Error (Diag, Source_Name, "", "expected a TOML document table", Result.Value);
         return False;
      end if;

      Root := Result.Value;
      return True;
   end Parse_Root;

   function Is_Allowed (Key, Allowed : String) return Boolean is
      Start : Positive := Allowed'First;
   begin
      if Allowed'Length = 0 then
         return False;
      end if;
      for I in Allowed'Range loop
         if Allowed (I) = '|' then
            if I > Start and then Allowed (Start .. I - 1) = Key then
               return True;
            end if;
            Start := I + 1;
         end if;
      end loop;
      return Start <= Allowed'Last and then Allowed (Start .. Allowed'Last) = Key;
   end Is_Allowed;

   function Check_Keys
     (Table       : TOML.TOML_Value;
      Allowed     : String;
      Source_Name : String;
      Path        : String;
      Diag        : out Config_Diagnostic) return Boolean
   is
   begin
      if Table.Kind /= TOML.TOML_Table then
         Set_Error (Diag, Source_Name, Path, "expected table", Table);
         return False;
      end if;
      for Pair of Table.Iterate_On_Table loop
         declare
            Key : constant String := To_String (Pair.Key);
         begin
            if not Is_Allowed (Key, Allowed) then
               Set_Error
                 (Diag, Source_Name,
                  (if Path'Length = 0 then Key else Path & "." & Key),
                  "unknown key", Pair.Value);
               return False;
            end if;
         end;
      end loop;
      return True;
   end Check_Keys;

   function Kind_Name (Kind : TOML.Any_Value_Kind) return String is
     (case Kind is
         when TOML.TOML_Table => "table",
         when TOML.TOML_Array => "array",
         when TOML.TOML_String => "string",
         when TOML.TOML_Integer => "integer",
         when TOML.TOML_Float => "float",
         when TOML.TOML_Boolean => "boolean",
         when TOML.TOML_Offset_Datetime => "offset datetime",
         when TOML.TOML_Local_Datetime => "local datetime",
         when TOML.TOML_Local_Date => "local date",
         when TOML.TOML_Local_Time => "local time");

   function Require
     (Table       : TOML.TOML_Value;
      Key         : String;
      Kind        : TOML.Any_Value_Kind;
      Source_Name : String;
      Path        : String;
      Value       : out TOML.TOML_Value;
      Diag        : out Config_Diagnostic) return Boolean
   is
      Full_Path : constant String :=
        (if Path'Length = 0 then Key else Path & "." & Key);
   begin
      if not Table.Has (Key) then
         Set_Error (Diag, Source_Name, Full_Path, "missing required key", Table);
         return False;
      end if;
      Value := Table.Get (Key);
      if Value.Kind /= Kind then
         Set_Error (Diag, Source_Name, Full_Path, "expected " & Kind_Name (Kind), Value);
         return False;
      end if;
      return True;
   end Require;

   function Optional
     (Table       : TOML.TOML_Value;
      Key         : String;
      Kind        : TOML.Any_Value_Kind;
      Source_Name : String;
      Path        : String;
      Value       : out TOML.TOML_Value;
      Present     : out Boolean;
      Diag        : out Config_Diagnostic) return Boolean
   is
      Full_Path : constant String :=
        (if Path'Length = 0 then Key else Path & "." & Key);
   begin
      Present := Table.Has (Key);
      if not Present then
         Value := TOML.No_TOML_Value;
         return True;
      end if;
      Value := Table.Get (Key);
      if Value.Kind /= Kind then
         Set_Error (Diag, Source_Name, Full_Path, "expected " & Kind_Name (Kind), Value);
         return False;
      end if;
      return True;
   end Optional;

   function Read_String_Array
     (Value       : TOML.TOML_Value;
      Source_Name : String;
      Path        : String;
      Items       : out String_Vectors.Vector;
      Diag        : out Config_Diagnostic) return Boolean
   is
   begin
      Items.Clear;
      if Value.Kind /= TOML.TOML_Array then
         Set_Error (Diag, Source_Name, Path, "expected array", Value);
         return False;
      end if;
      for I in 1 .. Value.Length loop
         declare
            Item : constant TOML.TOML_Value := Value.Item (I);
         begin
            if Item.Kind /= TOML.TOML_String then
               Set_Error
                 (Diag, Source_Name,
                  Path & "[" & Trim (Positive'Image (I), Ada.Strings.Both) & "]",
                  "expected string", Item);
               return False;
            elsif Item.As_String'Length = 0 then
               Set_Error
                 (Diag, Source_Name,
                  Path & "[" & Trim (Positive'Image (I), Ada.Strings.Both) & "]",
                  "expected non-empty string", Item);
               return False;
            end if;
            Items.Append (Item.As_String);
         end;
      end loop;
      return True;
   end Read_String_Array;

end ALedger.Config_Support;
