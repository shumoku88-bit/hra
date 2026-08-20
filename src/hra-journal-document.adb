with Ada.Strings;       use Ada.Strings;
with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with HRA.Journal_Evidence; use HRA.Journal_Evidence;

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

   function Is_Comment (Text : String) return Boolean is
     (Text'Length > 0
      and then (Text (Text'First) = ';' or else Text (Text'First) = '#'));

   function Is_Transaction_Header (Text : String) return Boolean is
     (Text'Length >= 10 and then Text (Text'First) in '0' .. '9');

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

   procedure Split_Header
     (Text        : String;
      Date_Text   : out Unbounded_String;
      Description : out Unbounded_String)
   is
      Space_Idx : constant Natural := Index (Text, " ");
      Date_End  : constant Natural :=
        (if Space_Idx > 0 then Space_Idx - 1 else Text'Last);
   begin
      Date_Text := To_Unbounded_String (Text (Text'First .. Date_End));
      if Space_Idx = 0 then
         Description := Null_Unbounded_String;
         return;
      end if;

      declare
         Rest : constant String := Trim (Text (Space_Idx + 1 .. Text'Last), Both);
      begin
         if Rest'Length > 0
           and then (Rest (Rest'First) = '*' or else Rest (Rest'First) = '!')
         then
            if Rest'Length = 1 then
               Description := Null_Unbounded_String;
            else
               Description := To_Unbounded_String
                 (Trim (Rest (Rest'First + 1 .. Rest'Last), Both));
            end if;
         else
            Description := To_Unbounded_String (Rest);
         end if;
      end;
   end Split_Header;

   function Parse
     (Input     : String;
      File_Name : String;
      Result    : out Parsed_Document;
      Diag      : out HRA.Journal.Parse_Diagnostic) return Boolean
   is
      Output       : Parsed_Document;
      Line_Start   : Natural := Input'First;
      Line_Number  : Natural := 0;
      In_Tx        : Boolean := False;
      Header_Line  : Positive := 1;
      Current_Date : Unbounded_String;
      Current_Desc : Unbounded_String;
      Current_Meta : Metadata_Vectors.Vector;

      procedure Flush_Transaction is
      begin
         if not In_Tx then
            return;
         end if;

         Output.Transactions.Append
           (Transaction_Source'
              (Source_Path => To_Unbounded_String (File_Name),
               Header_Line => Header_Line,
               Date_Text   => Current_Date,
               Description => Current_Desc,
               Metadata    => Current_Meta));
         Current_Meta.Clear;
         In_Tx := False;
      end Flush_Transaction;

      procedure Append_Metadata
        (Text : String;
         Line : Positive)
      is
         Colon : constant Natural := Index (Text, ":");
      begin
         if Text'Length = 0 or else Colon = 0 or else Colon = Text'First then
            return;
         end if;

         declare
            Key : constant String :=
              Lower_String (Trim (Text (Text'First .. Colon - 1), Both));
            Val : constant String :=
              (if Colon = Text'Last then ""
               else Trim (Text (Colon + 1 .. Text'Last), Both));
         begin
            if Key'Length > 0 then
               Current_Meta.Append
                 (Metadata_Entry'
                    (Key         => To_Unbounded_String (Key),
                     Value       => To_Unbounded_String (Val),
                     Line_Number => Line));
            end if;
         end;
      end Append_Metadata;

      procedure Admit_Metadata
        (Text : String;
         Line : Positive)
      is
      begin
         if not Is_Comment (Text) or else Text'Length = 1 then
            return;
         end if;

         declare
            Comment_Text : constant String :=
              Trim (Text (Text'First + 1 .. Text'Last), Both);
         begin
            Append_Metadata (Comment_Text, Line);
         end;
      end Admit_Metadata;

      procedure Admit_Header_Metadata
        (Text : String;
         Line : Positive)
      is
         Cursor : Natural := Text'First;
      begin
         while Cursor <= Text'Last loop
            declare
               Open_Idx  : Natural := 0;
               Close_Idx : Natural := 0;
            begin
               for I in Cursor .. Text'Last loop
                  if Text (I) = '[' then
                     Open_Idx := I;
                     exit;
                  end if;
               end loop;

               exit when Open_Idx = 0;

               if Open_Idx < Text'Last then
                  for I in Open_Idx + 1 .. Text'Last loop
                     if Text (I) = ']' then
                        Close_Idx := I;
                        exit;
                     end if;
                  end loop;
               end if;

               exit when Close_Idx = 0;

               if Close_Idx > Open_Idx + 1 then
                  Append_Metadata
                    (Trim (Text (Open_Idx + 1 .. Close_Idx - 1), Both), Line);
               end if;

               Cursor := Close_Idx + 1;
            end;
         end loop;
      end Admit_Header_Metadata;

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
               if Clean'Length = 0 then
                  Flush_Transaction;
               elsif not Is_Indented (Raw_Line) then
                  Flush_Transaction;

                  if Clean'Length >= 7
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
                  elsif Is_Transaction_Header (Clean) then
                     In_Tx := True;
                     Header_Line := Positive (Line_Number);
                     Split_Header (Clean, Current_Date, Current_Desc);
                     Admit_Header_Metadata (Clean, Positive (Line_Number));
                  end if;
               elsif In_Tx and then Is_Comment (Clean) then
                  Admit_Metadata (Clean, Positive (Line_Number));
               end if;
            end;

            Line_Start := Line_End + 1;
         end;
      end loop;

      Flush_Transaction;
      Result := Output;
      return True;
   exception
      when Constraint_Error =>
         Result :=
           (Includes     => Include_Directive_Vectors.Empty_Vector,
            Transactions => HRA.Journal_Evidence.Transaction_Source_Vectors.Empty_Vector);
         Diag :=
           (File_Name   => To_Unbounded_String (File_Name),
            Line_Number => Line_Number,
            Raw_Text    => Null_Unbounded_String,
            Message     => To_Unbounded_String
              ("journal document structure exceeds supported bounds"));
         return False;
   end Parse;

end HRA.Journal.Document;
