with Ada.Containers.Indefinite_Vectors;
with Ada.Directories; use Ada.Directories;
with Ada.Directories.Hierarchical_File_Names;
with Ada.IO_Exceptions;
with Ada.Streams; use Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Strings; use Ada.Strings;
with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with HRA.Journal; use HRA.Journal;
with HRA.Journal.Document;
with HRA.Journal_Evidence; use HRA.Journal_Evidence;
with HRA.Dates;

package body HRA.Journal_Loader is

   package HFN renames Ada.Directories.Hierarchical_File_Names;

   package String_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => String);

   function Contains
     (Items : String_Vectors.Vector;
      Value : String) return Boolean
   is
   begin
      for Item of Items loop
         if Item = Value then
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
      First  : Boolean := True;
   begin
      for Item of Trace loop
         if not First then
            Append (Result, " -> ");
         end if;
         Append (Result, Item);
         First := False;
      end loop;
      return To_String (Result);
   end Trace_Image;

   function Line_Image (Line : Positive) return String is
     (Trim (Positive'Image (Line), Both));

   function Resolve_Include_Path
     (Parent_Path  : String;
      Include_Path : String;
      Resolved     : out Unbounded_String;
      Error_Msg    : out Unbounded_String) return Boolean
   is
      Candidate : Unbounded_String := Null_Unbounded_String;
   begin
      Resolved  := Null_Unbounded_String;
      Error_Msg := Null_Unbounded_String;

      if HFN.Is_Full_Name (Include_Path) then
         Candidate := To_Unbounded_String (Include_Path);
      elsif HFN.Is_Relative_Name (Include_Path) then
         Candidate := To_Unbounded_String
           (HFN.Compose
              (Directory     => Containing_Directory (Parent_Path),
               Relative_Name => Include_Path));
      else
         Error_Msg := To_Unbounded_String
           ("include path is neither a full nor relative hierarchical name: " &
            Include_Path);
         return False;
      end if;

      if not Exists (To_String (Candidate))
        or else Kind (To_String (Candidate)) /= Ordinary_File
      then
         Error_Msg := To_Unbounded_String
           ("included journal is missing or not a regular file: " &
            To_String (Candidate));
         return False;
      end if;

      Resolved := To_Unbounded_String (Full_Name (To_String (Candidate)));
      return True;
   exception
      when Ada.IO_Exceptions.Name_Error | Ada.IO_Exceptions.Use_Error =>
         Resolved := Null_Unbounded_String;
         Error_Msg := To_Unbounded_String
           ("cannot resolve included journal: " & Include_Path);
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
      Text      := Null_Unbounded_String;
      Error_Msg := Null_Unbounded_String;
      SIO.Open (File, SIO.In_File, Path);

      declare
         Byte_Count : constant SIO.Count := SIO.Size (File);
      begin
         if Byte_Count > SIO.Count (Natural'Last) then
            SIO.Close (File);
            Error_Msg := To_Unbounded_String
              ("included journal is too large to load: " & Path);
            return False;
         elsif Byte_Count > 0 then
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
      return True;
   exception
      when Ada.IO_Exceptions.Name_Error
         | Ada.IO_Exceptions.Use_Error
         | Ada.IO_Exceptions.Device_Error
         | Ada.IO_Exceptions.End_Error
         | Ada.IO_Exceptions.Data_Error =>
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
      Trace          : String_Vectors.Vector;
      Loaded_Paths   : String_Vectors.Vector;
      Loaded_Traces  : String_Vectors.Vector;
      Expanded       : Unbounded_String := Null_Unbounded_String;
      Graph_Evidence : HRA.Journal_Evidence.Journal_Evidence;

      function Expand_Document
        (Path : String;
         Text : String) return Boolean;

      function Expand_Document
        (Path : String;
         Text : String) return Boolean
      is
         Canonical_Path : Unbounded_String;
         Existing       : Natural;
         Local_Document : HRA.Journal.Document.Parsed_Document;
         Check_Ledger   : HRA.Ledger.Ledger;
         Local_Evidence : HRA.Journal_Evidence.Journal_Evidence;
         Evidence_Diag  : Evidence_Diagnostic;
         Diag           : Parse_Diagnostic;
         Line_Start     : Natural := Text'First;
         Line_Number    : Natural := 0;
         Evidence_Index : Natural := 1;
         Include_Index  : Natural := 1;
      begin
         begin
            Canonical_Path := To_Unbounded_String (Full_Name (Path));
         exception
            when Ada.IO_Exceptions.Name_Error | Ada.IO_Exceptions.Use_Error =>
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

         --  Journal syntax owns include recognition and validation. The loader
         --  consumes only typed source coordinates and performs graph I/O.
         if not HRA.Journal.Document.Parse
           (Text, To_String (Canonical_Path), Local_Document, Diag)
         then
            Error_Msg := To_Unbounded_String (Format_Diagnostic (Diag));
            Trace.Delete_Last;
            return False;
         end if;

         --  Parse each physical document from its exact bytes before graph
         --  substitution. This retains the local semantic value paired with
         --  source evidence from the same physical document.
         if not Parse_Journal_Text
           (Text, To_String (Canonical_Path), Check_Ledger, Diag)
         then
            Error_Msg := To_Unbounded_String (Format_Diagnostic (Diag));
            Trace.Delete_Last;
            return False;
         end if;

         if not HRA.Journal_Evidence.Extract
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

               if Evidence_Index <= Natural (Local_Evidence.Transactions.Length)
                 and then Local_Evidence.Transactions.Element
                   (Evidence_Index).Header_Line = Line_Number
               then
                  Graph_Evidence.Transactions.Append
                    (Local_Evidence.Transactions.Element (Evidence_Index));
                  Evidence_Index := Evidence_Index + 1;
               end if;

               if Include_Index <= Natural (Local_Document.Includes.Length)
                 and then Local_Document.Includes.Element
                   (Include_Index).Line_Number = Line_Number
               then
                  declare
                     Directive  : constant HRA.Journal.Document.Include_Directive :=
                       Local_Document.Includes.Element (Include_Index);
                     Child_Path : Unbounded_String;
                     Child_Text : Unbounded_String;
                  begin
                     if not Resolve_Include_Path
                       (To_String (Canonical_Path),
                        To_String (Directive.Path),
                        Child_Path,
                        Error_Msg)
                     then
                        Error_Msg := To_Unbounded_String
                          (To_String (Canonical_Path) & ":" &
                           Line_Image (Directive.Line_Number) & ": " &
                           To_String (Error_Msg));
                        Trace.Delete_Last;
                        return False;
                     end if;

                     if not Read_Exact_Text
                       (To_String (Child_Path), Child_Text, Error_Msg)
                     then
                        Error_Msg := To_Unbounded_String
                          (To_String (Canonical_Path) & ":" &
                           Line_Image (Directive.Line_Number) & ": " &
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

                     Include_Index := Include_Index + 1;
                  end;
               else
                  Append (Expanded, Text (Line_Start .. Line_End - 1));
                  Append (Expanded, ASCII.LF);
               end if;

               Line_Start := Line_End + 1;
            end;
         end loop;

         if Evidence_Index <= Natural (Local_Evidence.Transactions.Length) then
            Error_Msg := To_Unbounded_String
              (To_String (Canonical_Path) &
               ": transaction evidence was not placed into resolved graph");
            Trace.Delete_Last;
            return False;
         elsif Include_Index <= Natural (Local_Document.Includes.Length) then
            Error_Msg := To_Unbounded_String
              (To_String (Canonical_Path) &
               ": include directive was not placed into resolved graph");
            Trace.Delete_Last;
            return False;
         end if;

         Trace.Delete_Last;
         return True;
      end Expand_Document;

      Diag : Parse_Diagnostic;
   begin
      Observation.Value := HRA.Ledger.Empty_Ledger;
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
            Tx : constant HRA.Ledger.Transaction :=
              Observation.Value.Transactions.Element (I);
         begin
            if To_String (Source.Date_Text) /= HRA.Dates.Image (Tx.Date)
              or else To_String (Source.Description) /= To_String (Tx.Code_Or_Payee)
            then
               Error_Msg := To_Unbounded_String
                 ("resolved Journal evidence does not align at " &
                  To_String (Source.Source_Path) & ":" &
                  Line_Image (Source.Header_Line));
               return False;
            end if;
         end;
      end loop;

      Observation.Evidence := Graph_Evidence;
      return True;
   end Load_From_Root_Source;

   function Load_From_Root_Source
     (Root_Path : String;
      Root_Text : String;
      L         : out HRA.Ledger.Ledger;
      Error_Msg : out Unbounded_String) return Boolean
   is
      Observation : Journal_Observation;
   begin
      if not Load_From_Root_Source
        (Root_Path, Root_Text, Observation, Error_Msg)
      then
         L := HRA.Ledger.Empty_Ledger;
         return False;
      end if;

      L := Observation.Value;
      return True;
   end Load_From_Root_Source;

end HRA.Journal_Loader;
