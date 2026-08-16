with Ada.Containers.Indefinite_Vectors;
with Ada.Directories;          use Ada.Directories;
with Ada.Streams;              use Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Strings.Unbounded;    use Ada.Strings.Unbounded;
with ALedger.Journal;          use ALedger.Journal;
with ALedger.Journal_Evidence; use ALedger.Journal_Evidence;

package body ALedger.Journal_Loader is

   package String_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => String);

   type Include_Line_Kind is
     (Not_Include, Valid_Include, Invalid_Include);

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

   function Is_Outer_Whitespace (C : Character) return Boolean is
     (C = ' ' or else C = ASCII.HT or else C = ASCII.CR);

   function Trim_Whitespace (Value : String) return String is
      First : Integer := Value'First;
      Last  : Integer := Value'Last;
   begin
      while First <= Last and then Is_Outer_Whitespace (Value (First)) loop
         First := First + 1;
      end loop;
      while Last >= First and then Is_Outer_Whitespace (Value (Last)) loop
         Last := Last - 1;
      end loop;

      if First > Last then
         return "";
      end if;
      return Value (First .. Last);
   end Trim_Whitespace;

   function Parse_Include_Line
     (Line : String;
      Path : out Unbounded_String) return Include_Line_Kind
   is
      Clean      : constant String := Trim_Whitespace (Line);
      Comment_At : Natural := 0;
   begin
      Path := Null_Unbounded_String;

      if Line'Length = 0
        or else Line (Line'First) = ' '
        or else Line (Line'First) = ASCII.HT
        or else Clean'Length < 7
      then
         return Not_Include;
      end if;

      if Lower_String (Clean (Clean'First .. Clean'First + 6)) /= "include" then
         return Not_Include;
      end if;

      if Clean'Length > 7
        and then Clean (Clean'First + 7) /= ' '
        and then Clean (Clean'First + 7) /= ASCII.HT
      then
         return Invalid_Include;
      end if;

      if Clean'Length = 7 then
         return Invalid_Include;
      end if;

      declare
         Remainder : constant String :=
           Trim_Whitespace (Clean (Clean'First + 7 .. Clean'Last));
      begin
         for I in Remainder'Range loop
            if Remainder (I) = ';' then
               Comment_At := I;
               exit;
            end if;
         end loop;

         declare
            Include_Path : constant String :=
              (if Comment_At = 0 then
                  Trim_Whitespace (Remainder)
               elsif Comment_At = Remainder'First then
                  ""
               else
                  Trim_Whitespace
                    (Remainder (Remainder'First .. Comment_At - 1)));
         begin
            if Include_Path'Length = 0 then
               return Invalid_Include;
            end if;
            Path := To_Unbounded_String (Include_Path);
            return Valid_Include;
         end;
      end;
   end Parse_Include_Line;

   function Contains
     (Items : String_Vectors.Vector;
      Value : String) return Boolean
   is
   begin
      for I in 1 .. Natural (Items.Length) loop
         if Items.Element (I) = Value then
            return True;
         end if;
      end loop;
      return False;
   end Contains;

   function Index_Of
     (Items : String_Vectors.Vector;
      Value : String) return Natural
   is
   begin
      for I in 1 .. Natural (Items.Length) loop
         if Items.Element (I) = Value then
            return I;
         end if;
      end loop;
      return 0;
   end Index_Of;

   function Trace_Image (Trace : String_Vectors.Vector) return String is
      Result : Unbounded_String := Null_Unbounded_String;
   begin
      for I in 1 .. Natural (Trace.Length) loop
         if I > 1 then
            Append (Result, " -> ");
         end if;
         Append (Result, Trace.Element (I));
      end loop;
      return To_String (Result);
   end Trace_Image;

   function Is_Absolute_Path (Path : String) return Boolean is
   begin
      if Path'Length = 0 then
         return False;
      end if;
      if Path (Path'First) = '/' or else Path (Path'First) = '\' then
         return True;
      end if;
      return Path'Length >= 2 and then Path (Path'First + 1) = ':';
   end Is_Absolute_Path;

   function Resolve_Include_Path
     (Parent_Path  : String;
      Include_Path : String;
      Resolved     : out Unbounded_String;
      Error_Msg    : out Unbounded_String) return Boolean
   is
      Candidate : constant String :=
        (if Is_Absolute_Path (Include_Path) then Include_Path
         else Compose (Containing_Directory (Parent_Path), Include_Path));
   begin
      if not Exists (Candidate) or else Kind (Candidate) /= Ordinary_File then
         Error_Msg := To_Unbounded_String
           ("included journal is missing or not a regular file: " & Candidate);
         return False;
      end if;

      Resolved := To_Unbounded_String (Full_Name (Candidate));
      return True;
   exception
      when others =>
         Error_Msg := To_Unbounded_String
           ("cannot resolve included journal: " & Candidate);
         return False;
   end Resolve_Include_Path;

   function Read_Exact_Text
     (Path      : String;
      Text      : out Unbounded_String;
      Error_Msg : out Unbounded_String) return Boolean
   is
      package SIO renames Ada.Streams.Stream_IO;
      use type SIO.Count;
      File : SIO.File_Type;
   begin
      SIO.Open (File, SIO.In_File, Path);
      declare
         Byte_Count : constant SIO.Count := SIO.Size (File);
      begin
         if Byte_Count = 0 then
            Text := Null_Unbounded_String;
         else
            declare
               Bytes : Stream_Element_Array
                 (1 .. Stream_Element_Offset (Byte_Count));
               Last  : Stream_Element_Offset;
               Value : String (1 .. Natural (Byte_Count));
            begin
               SIO.Read (File, Bytes, Last);
               if Last /= Bytes'Last then
                  SIO.Close (File);
                  Error_Msg := To_Unbounded_String
                    ("short read while loading included journal: " & Path);
                  return False;
               end if;

               for I in Bytes'Range loop
                  Value (Natural (I)) := Character'Val (Bytes (I));
               end loop;
               Text := To_Unbounded_String (Value);
            end;
         end if;
      end;
      SIO.Close (File);
      Error_Msg := Null_Unbounded_String;
      return True;
   exception
      when others =>
         if SIO.Is_Open (File) then
            SIO.Close (File);
         end if;
         Text := Null_Unbounded_String;
         Error_Msg := To_Unbounded_String
           ("cannot read included journal: " & Path);
         return False;
   end Read_Exact_Text;

   function Load_From_Root_Source
     (Root_Path   : String;
      Root_Text   : String;
      Observation : out Journal_Observation;
      Error_Msg   : out Unbounded_String) return Boolean
   is
      Trace         : String_Vectors.Vector;
      Loaded_Paths  : String_Vectors.Vector;
      Loaded_Traces : String_Vectors.Vector;
      Expanded      : Unbounded_String := Null_Unbounded_String;
      Graph_Evidence : ALedger.Journal_Evidence.Journal_Evidence;

      function Expand_Document
        (Path : String;
         Text : String) return Boolean;

      function Expand_Document
        (Path : String;
         Text : String) return Boolean
      is
         Canonical_Path : Unbounded_String;
         Existing       : Natural;
         Check_Ledger   : ALedger.Ledger.Ledger;
         Local_Evidence : ALedger.Journal_Evidence.Journal_Evidence;
         Evidence_Diag  : Evidence_Diagnostic;
         Diag           : Parse_Diagnostic;
         Line_Start     : Natural := Text'First;
         Line_Number    : Natural := 0;
         Evidence_Index : Natural := 1;
      begin
         begin
            Canonical_Path := To_Unbounded_String (Full_Name (Path));
         exception
            when others =>
               Error_Msg := To_Unbounded_String
                 ("cannot normalize journal path: " & Path);
               return False;
         end;

         if Contains (Trace, To_String (Canonical_Path)) then
            Error_Msg := To_Unbounded_String
              ("journal include cycle: " & Trace_Image (Trace) &
               " -> " & To_String (Canonical_Path));
            return False;
         end if;

         Existing := Index_Of (Loaded_Paths, To_String (Canonical_Path));
         if Existing > 0 then
            Error_Msg := To_Unbounded_String
              ("journal include already loaded: " & To_String (Canonical_Path) &
               "; first trace: " & Loaded_Traces.Element (Existing) &
               "; repeated trace: " & Trace_Image (Trace) &
               (if Trace.Is_Empty then "" else " -> ") &
               To_String (Canonical_Path));
            return False;
         end if;

         Trace.Append (To_String (Canonical_Path));
         Loaded_Paths.Append (To_String (Canonical_Path));
         Loaded_Traces.Append (Trace_Image (Trace));

         --  Parse each physical document from its exact bytes before
         --  substitution. The current Journal parser treats include lines as
         --  structural boundaries, so this yields exactly the transactions
         --  physically owned by this document.
         if not Parse_Journal_Text
           (Text, To_String (Canonical_Path), Check_Ledger, Diag)
         then
            Error_Msg := To_Unbounded_String (Format_Diagnostic (Diag));
            Trace.Delete_Last;
            return False;
         end if;

         if not ALedger.Journal_Evidence.Extract
           (Text,
            To_String (Canonical_Path),
            Check_Ledger,
            Local_Evidence,
            Evidence_Diag)
         then
            Error_Msg := To_Unbounded_String
              (To_String (Canonical_Path) & ": source evidence error: " &
               To_String (Evidence_Diag.Message));
            Trace.Delete_Last;
            return False;
         end if;

         while Line_Start <= Text'Last loop
            Line_Number := Line_Number + 1;
            declare
               Line_End : Natural := Line_Start;
            begin
               while Line_End <= Text'Last
                 and then Text (Line_End) /= ASCII.LF
               loop
                  Line_End := Line_End + 1;
               end loop;

               --  Retain physical transaction evidence at exactly the point
               --  where this document contributes the transaction to the
               --  resolved graph. Recursive include evidence therefore lands
               --  between surrounding parent transactions in source order.
               if Evidence_Index <= Natural (Local_Evidence.Transactions.Length)
                 and then Local_Evidence.Transactions.Element
                   (Evidence_Index).Header_Line = Line_Number
               then
                  Graph_Evidence.Transactions.Append
                    (Local_Evidence.Transactions.Element (Evidence_Index));
                  Evidence_Index := Evidence_Index + 1;
               end if;

               declare
                  Raw_Line : constant String := Text (Line_Start .. Line_End - 1);
                  Include_Path : Unbounded_String;
                  Include_Kind : constant Include_Line_Kind :=
                    Parse_Include_Line (Raw_Line, Include_Path);
               begin
                  case Include_Kind is
                     when Not_Include =>
                        Append (Expanded, Raw_Line);
                        Append (Expanded, ASCII.LF);

                     when Invalid_Include =>
                        Error_Msg := To_Unbounded_String
                          (To_String (Canonical_Path) & ":" &
                           Natural'Image (Line_Number) &
                           ": invalid include directive");
                        Trace.Delete_Last;
                        return False;

                     when Valid_Include =>
                        declare
                           Child_Path : Unbounded_String;
                           Child_Text : Unbounded_String;
                        begin
                           if not Resolve_Include_Path
                             (To_String (Canonical_Path),
                              To_String (Include_Path),
                              Child_Path,
                              Error_Msg)
                           then
                              Error_Msg := To_Unbounded_String
                                (To_String (Canonical_Path) & ":" &
                                 Natural'Image (Line_Number) & ": " &
                                 To_String (Error_Msg));
                              Trace.Delete_Last;
                              return False;
                           end if;

                           if not Read_Exact_Text
                             (To_String (Child_Path), Child_Text, Error_Msg)
                           then
                              Error_Msg := To_Unbounded_String
                                (To_String (Canonical_Path) & ":" &
                                 Natural'Image (Line_Number) & ": " &
                                 To_String (Error_Msg));
                              Trace.Delete_Last;
                              return False;
                           end if;

                           if not Expand_Document
                             (To_String (Child_Path), To_String (Child_Text))
                           then
                              Trace.Delete_Last;
                              return False;
                           end if;
                        end;
                  end case;
               end;

               Line_Start := Line_End + 1;
            end;
         end loop;

         if Evidence_Index <= Natural (Local_Evidence.Transactions.Length) then
            Error_Msg := To_Unbounded_String
              (To_String (Canonical_Path) &
               ": transaction evidence was not placed into resolved graph");
            Trace.Delete_Last;
            return False;
         end if;

         Trace.Delete_Last;
         return True;
      end Expand_Document;

      Diag : Parse_Diagnostic;
   begin
      Observation.Value := ALedger.Ledger.Empty_Ledger;
      Observation.Evidence.Transactions.Clear;
      Error_Msg := Null_Unbounded_String;

      if not Expand_Document (Root_Path, Root_Text) then
         return False;
      end if;

      if not Parse_Journal_Text
        (To_String (Expanded), Root_Path, Observation.Value, Diag)
      then
         Error_Msg := To_Unbounded_String (Format_Diagnostic (Diag));
         return False;
      end if;

      if Natural (Graph_Evidence.Transactions.Length) /=
         Natural (Observation.Value.Transactions.Length)
      then
         Error_Msg := To_Unbounded_String
           ("resolved Journal transaction evidence count does not match Ledger");
         return False;
      end if;

      for I in 1 .. Natural (Observation.Value.Transactions.Length) loop
         declare
            Source : constant Transaction_Source :=
              Graph_Evidence.Transactions.Element (I);
            Tx : constant ALedger.Ledger.Transaction :=
              Observation.Value.Transactions.Element (I);
         begin
            if To_String (Source.Date_Text) /= To_String (Tx.Date_Text)
              or else To_String (Source.Description) /= To_String (Tx.Code_Or_Payee)
            then
               Error_Msg := To_Unbounded_String
                 ("resolved Journal evidence does not align at " &
                  To_String (Source.Source_Path) & ":" &
                  Positive'Image (Source.Header_Line));
               return False;
            end if;
         end;
      end loop;

      Observation.Evidence := Graph_Evidence;
      return True;
   exception
      when others =>
         Observation.Value := ALedger.Ledger.Empty_Ledger;
         Observation.Evidence.Transactions.Clear;
         Error_Msg := To_Unbounded_String
           ("failed to admit journal include graph rooted at: " & Root_Path);
         return False;
   end Load_From_Root_Source;

   function Load_From_Root_Source
     (Root_Path : String;
      Root_Text : String;
      L         : out ALedger.Ledger.Ledger;
      Error_Msg : out Unbounded_String) return Boolean
   is
      Observation : Journal_Observation;
   begin
      if not Load_From_Root_Source
        (Root_Path, Root_Text, Observation, Error_Msg)
      then
         L := ALedger.Ledger.Empty_Ledger;
         return False;
      end if;

      L := Observation.Value;
      return True;
   end Load_From_Root_Source;

end ALedger.Journal_Loader;
