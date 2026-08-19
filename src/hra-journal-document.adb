with Ada.Strings;       use Ada.Strings;
with Ada.Strings.Fixed; use Ada.Strings.Fixed;

package body HRA.Journal.Document is

   function Lower_String (Value : String) return String is
      Result : String := Value;
   begin
      for I in Result'Range loop
         if Result (I) in 'A' .. 'Z' then
            Result (I) := Character'Val (Character'Pos (Result (I)) + 32);
         end if;
      end loop;
      return Result;
   end Lower_String;

   function Is_Indented (Line : String) return Boolean is
     (Line'Length > 0
      and then (Line (Line'First) = ' ' or else Line (Line'First) = ASCII.HT));

   function Without_Trailing_CR (Line : String) return String is
   begin
      if Line'Length > 0 and then Line (Line'Last) = ASCII.CR then
         if Line'Length = 1 then
            return "";
         end if;
         return Line (Line'First .. Line'Last - 1);
      end if;
      return Line;
   end Without_Trailing_CR;

   procedure Set_Error
     (File_Name : String;
      Line      : Positive;
      Raw       : String;
      Message   : String;
      Diag      : out HRA.Journal.Parse_Diagnostic)
   is
   begin
      Diag :=
        (File_Name   => To_Unbounded_String (File_Name),
         Line_Number => Line,
         Raw_Text    => To_Unbounded_String (Raw),
         Message     => To_Unbounded_String (Message));
   end Set_Error;

   function Parse
     (Input     : String;
      File_Name : String;
      Result    : out Parsed_Document;
      Diag      : out HRA.Journal.Parse_Diagnostic) return Boolean
   is
      Output      : Parsed_Document;
      Line_Start  : Natural := Input'First;
      Line_Number : Natural := 0;
   begin
      Result := Output;
      Diag :=
        (File_Name   => To_Unbounded_String (File_Name),
         Line_Number => 0,
         Raw_Text    => Null_Unbounded_String,
         Message     => Null_Unbounded_String);

      while Line_Start <= Input'Last loop
         Line_Number := Line_Number + 1;
         declare
            Line_End : Natural := Line_Start;
         begin
            while Line_End <= Input'Last and then Input (Line_End) /= ASCII.LF loop
               Line_End := Line_End + 1;
            end loop;

            declare
               Raw_Slice : constant String := Input (Line_Start .. Line_End - 1);
               Raw_Line  : constant String := Without_Trailing_CR (Raw_Slice);
               Clean     : constant String := Trim (Raw_Line, Both);
            begin
               if not Is_Indented (Raw_Line)
                 and then Clean'Length >= 7
                 and then Lower_String
                   (Clean (Clean'First .. Clean'First + 6)) = "include"
               then
                  if Clean'Length = 7
                    or else
                      (Clean (Clean'First + 7) /= ' '
                       and then Clean (Clean'First + 7) /= ASCII.HT)
                  then
                     Set_Error
                       (File_Name,
                        Positive (Line_Number),
                        Raw_Line,
                        "invalid include directive",
                        Diag);
                     return False;
                  end if;

                  declare
                     Remainder : constant String :=
                       Trim (Clean (Clean'First + 7 .. Clean'Last), Both);
                     Comment_At : constant Natural := Index (Remainder, ";");
                     Include_Path : constant String :=
                       (if Comment_At = 0 then
                           Trim (Remainder, Both)
                        elsif Comment_At = Remainder'First then
                           ""
                        else
                           Trim
                             (Remainder
                                (Remainder'First .. Comment_At - 1),
                              Both));
                  begin
                     if Include_Path'Length = 0 then
                        Set_Error
                          (File_Name,
                           Positive (Line_Number),
                           Raw_Line,
                           "include directive requires a path",
                           Diag);
                        return False;
                     end if;

                     Output.Includes.Append
                       (Include_Directive'
                          (Line_Number => Positive (Line_Number),
                           Path        => To_Unbounded_String (Include_Path)));
                  end;
               end if;
            end;

            Line_Start := Line_End + 1;
         end;
      end loop;

      Result := Output;
      return True;
   exception
      when Constraint_Error =>
         Result :=
           (Includes => Include_Directive_Vectors.Empty_Vector);
         Diag :=
           (File_Name   => To_Unbounded_String (File_Name),
            Line_Number => Line_Number,
            Raw_Text    => Null_Unbounded_String,
            Message     => To_Unbounded_String
              ("journal document structure exceeds supported bounds"));
         return False;
   end Parse;

end HRA.Journal.Document;
