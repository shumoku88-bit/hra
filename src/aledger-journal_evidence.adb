with Ada.Strings;       use Ada.Strings;
with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with ALedger.Dates;

package body ALedger.Journal_Evidence is

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
   begin
      return Line'Length > 0
        and then (Line (Line'First) = ' ' or else Line (Line'First) = ASCII.HT);
   end Is_Indented;

   function Is_Comment (Text : String) return Boolean is
   begin
      return Text'Length > 0
        and then (Text (Text'First) = ';' or else Text (Text'First) = '#');
   end Is_Comment;

   function Is_Transaction_Header (Text : String) return Boolean is
   begin
      return Text'Length >= 10 and then Text (Text'First) in '0' .. '9';
   end Is_Transaction_Header;

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

   function Extract
     (Input    : String;
      L        : ALedger.Ledger.Ledger;
      Evidence : out Journal_Evidence;
      Diag     : out Evidence_Diagnostic) return Boolean
   is
   begin
      return Extract
        (Input       => Input,
         Source_Path => "",
         L           => L,
         Evidence    => Evidence,
         Diag        => Diag);
   end Extract;

   function Extract
     (Input       : String;
      Source_Path : String;
      L           : ALedger.Ledger.Ledger;
      Evidence    : out Journal_Evidence;
      Diag        : out Evidence_Diagnostic) return Boolean
   is
      Result       : Journal_Evidence;
      Line_Start   : Natural := Input'First;
      Line_Number  : Natural := 0;
      In_Tx        : Boolean := False;
      Header_Line  : Positive := 1;
      Current_Date : Unbounded_String;
      Current_Desc : Unbounded_String;
      Current_Meta : Metadata_Vectors.Vector;

      procedure Fail (Line : Natural; Message : String) is
      begin
         Diag.Line_Number := Line;
         Diag.Message := To_Unbounded_String (Message);
      end Fail;

      procedure Flush is
      begin
         if not In_Tx then
            return;
         end if;

         Result.Transactions.Append
           (Transaction_Source'
              (Source_Path => To_Unbounded_String (Source_Path),
               Header_Line => Header_Line,
               Date_Text   => Current_Date,
               Description => Current_Desc,
               Metadata    => Current_Meta));
         Current_Meta.Clear;
         In_Tx := False;
      end Flush;

      procedure Admit_Metadata (Text : String) is
      begin
         if not Is_Comment (Text) or else Text'Length = 1 then
            return;
         end if;

         declare
            Comment_Text : constant String :=
              Trim (Text (Text'First + 1 .. Text'Last), Both);
         begin
            if Comment_Text'Length = 0 then
               return;
            end if;

            declare
               Colon : constant Natural := Index (Comment_Text, ":");
            begin
               if Colon = 0 or else Colon = Comment_Text'First then
                  return;
               end if;

               declare
                  Key : constant String :=
                    Lower_String
                      (Trim
                         (Comment_Text (Comment_Text'First .. Colon - 1), Both));
                  Val : constant String :=
                    (if Colon = Comment_Text'Last then ""
                     else Trim
                       (Comment_Text (Colon + 1 .. Comment_Text'Last), Both));
               begin
                  if Key'Length > 0 then
                     Current_Meta.Append
                       (Metadata_Entry'
                          (Key         => To_Unbounded_String (Key),
                           Value       => To_Unbounded_String (Val),
                           Line_Number => Positive (Line_Number)));
                  end if;
               end;
            end;
         end;
      end Admit_Metadata;

   begin
      Evidence := Result;
      Diag := (Line_Number => 0, Message => Null_Unbounded_String);

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
               Last_Idx  : constant Natural :=
                 (if Raw_Slice'Length > 0
                    and then Raw_Slice (Raw_Slice'Last) = ASCII.CR
                  then Raw_Slice'Last - 1
                  else Raw_Slice'Last);
               Raw_Line  : constant String :=
                 (if Raw_Slice'Length > 0
                    and then Last_Idx >= Raw_Slice'First
                  then Raw_Slice (Raw_Slice'First .. Last_Idx)
                  else "");
               Trimmed   : constant String := Trim (Raw_Line, Both);
            begin
               if Trimmed'Length = 0 then
                  Flush;
               elsif not Is_Indented (Raw_Line) then
                  if Is_Transaction_Header (Trimmed) then
                     Flush;
                     In_Tx := True;
                     Header_Line := Positive (Line_Number);
                     Split_Header (Trimmed, Current_Date, Current_Desc);
                  else
                     Flush;
                  end if;
               elsif In_Tx and then Is_Comment (Trimmed) then
                  Admit_Metadata (Trimmed);
               end if;
            end;

            Line_Start := Line_End + 1;
         end;
      end loop;

      Flush;

      if Natural (Result.Transactions.Length) /= Natural (L.Transactions.Length) then
         Fail
           (0,
            "transaction source evidence count does not match admitted Journal");
         return False;
      end if;

      for I in 1 .. Natural (L.Transactions.Length) loop
         declare
            Source : constant Transaction_Source := Result.Transactions.Element (I);
            Tx     : constant ALedger.Ledger.Transaction := L.Transactions.Element (I);
         begin
            if To_String (Source.Date_Text) /= ALedger.Dates.Image (Tx.Date)
              or else To_String (Source.Description) /= To_String (Tx.Code_Or_Payee)
            then
               Fail
                 (Source.Header_Line,
                  "transaction source evidence does not align with admitted Journal");
               return False;
            end if;
         end;
      end loop;

      Evidence := Result;
      return True;
   end Extract;

end ALedger.Journal_Evidence;
