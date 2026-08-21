package body HRA.Issue_Close is

   use type HRA.Dates.Date;
   use type HRA.Issues.Issue_Id;
   use type HRA.Issues.Issue_Status;

   type Field_Array is array (1 .. 10) of Unbounded_String;

   function Text (Candidate : Candidate_Source) return String is
     (To_String (Candidate.Source_Text));

   function Split_Row
     (Line   : String;
      Fields : out Field_Array) return Boolean
   is
      Field_Index : Positive := 1;
      Field_Start : Natural := Line'First;
   begin
      Fields := [others => Null_Unbounded_String];

      for I in Line'Range loop
         if Line (I) = ASCII.HT then
            if Field_Index = Fields'Last then
               return False;
            end if;

            if Field_Start <= I - 1 then
               Fields (Field_Index) :=
                 To_Unbounded_String (Line (Field_Start .. I - 1));
            end if;
            Field_Index := Field_Index + 1;
            Field_Start := I + 1;
         end if;
      end loop;

      if Field_Start <= Line'Last then
         Fields (Field_Index) :=
           To_Unbounded_String (Line (Field_Start .. Line'Last));
      end if;

      return Field_Index = Fields'Last;
   end Split_Row;

   function Join_Row (Fields : Field_Array) return String is
      Result : Unbounded_String;
   begin
      for I in Fields'Range loop
         if I > Fields'First then
            Append (Result, ASCII.HT);
         end if;
         Append (Result, Fields (I));
      end loop;
      return To_String (Result);
   end Join_Row;

   function Status_Text (Disposition : Close_Disposition) return String is
     (case Disposition is
         when Resolve_Issue => "resolved",
         when Drop_Issue    => "dropped");

   function Replace_Target_Row
     (Existing_Source : String;
      Issue_ID        : HRA.Issues.Issue_Id;
      Disposition     : Close_Disposition;
      Closed_On       : HRA.Dates.Date;
      Result          : out Unbounded_String) return Boolean
   is
      Output      : Unbounded_String;
      Line_Start  : Natural := Existing_Source'First;
      Line_Number : Natural := 0;
      Match_Count : Natural := 0;
   begin
      while Line_Start <= Existing_Source'Last loop
         Line_Number := Line_Number + 1;
         declare
            Line_End : Natural := Line_Start;
         begin
            while Line_End <= Existing_Source'Last
              and then Existing_Source (Line_End) /= ASCII.LF
            loop
               Line_End := Line_End + 1;
            end loop;

            declare
               Has_LF : constant Boolean := Line_End <= Existing_Source'Last;
               Raw    : constant String :=
                 (if Line_End > Line_Start
                  then Existing_Source (Line_Start .. Line_End - 1)
                  else "");
               Has_CR : constant Boolean :=
                 Raw'Length > 0 and then Raw (Raw'Last) = ASCII.CR;
               Row    : constant String :=
                 (if Has_CR and then Raw'Length > 1
                  then Raw (Raw'First .. Raw'Last - 1)
                  elsif Has_CR
                  then ""
                  else Raw);
               Fields : Field_Array;
               Is_Target : Boolean := False;
            begin
               if Line_Number > 1 and then Row'Length > 0
                 and then Split_Row (Row, Fields)
               then
                  Is_Target :=
                    To_String (Fields (1)) = HRA.Issues.Text (Issue_ID);
               end if;

               if Is_Target then
                  Match_Count := Match_Count + 1;
                  Fields (2) := To_Unbounded_String (Status_Text (Disposition));
                  Fields (5) := To_Unbounded_String (HRA.Dates.Image (Closed_On));
                  Append (Output, Join_Row (Fields));
                  if Has_CR then
                     Append (Output, ASCII.CR);
                  end if;
               else
                  Append (Output, Raw);
               end if;

               if Has_LF then
                  Append (Output, ASCII.LF);
               end if;
            end;

            Line_Start := Line_End + 1;
         end;
      end loop;

      Result := Output;
      return Match_Count = 1;
   end Replace_Target_Row;

   function Prepare_Close
     (Existing_Source : String;
      Issue_ID        : HRA.Issues.Issue_Id;
      Disposition     : Close_Disposition;
      Closed_On       : HRA.Dates.Date;
      Candidate       : out Candidate_Source;
      Diag            : out Close_Diagnostic) return Boolean
   is
      Source_Inventory   : HRA.Issues.Issues_Inventory;
      Source_Diag        : HRA.Issues.Admission_Diagnostic;
      Candidate_Inventory : HRA.Issues.Issues_Inventory;
      Candidate_Diag     : HRA.Issues.Admission_Diagnostic;
      Target             : HRA.Issues.Household_Issue;
      Found              : Boolean := False;
      Candidate_Text     : Unbounded_String;
   begin
      Candidate := (Source_Text => Null_Unbounded_String);
      Diag :=
        (Status  => Success,
         Issue   => HRA.Issues.To_Unbounded (Issue_ID),
         Source  =>
           (Status      => HRA.Issues.Success,
            Line_Number => 0,
            Issue_ID    => Null_Unbounded_String,
            Message     => Null_Unbounded_String),
         Message => Null_Unbounded_String);

      if not HRA.Issues.Admit_Issues_TSV
        (Existing_Source, Source_Inventory, Source_Diag)
      then
         Diag :=
           (Status  => Source_Admission_Failed,
            Issue   => HRA.Issues.To_Unbounded (Issue_ID),
            Source  => Source_Diag,
            Message => To_Unbounded_String ("current issues source is not admitted"));
         return False;
      end if;

      for I in 1 .. HRA.Issues.Count (Source_Inventory) loop
         if HRA.Issues.Element (Source_Inventory, I).ID = Issue_ID then
            Target := HRA.Issues.Element (Source_Inventory, I);
            Found := True;
            exit;
         end if;
      end loop;

      if not Found then
         Diag.Status := Issue_Not_Found;
         Diag.Message := To_Unbounded_String ("Issue identity is not present in current source");
         return False;
      end if;

      if Target.Status /= HRA.Issues.Open then
         Diag.Status := Issue_Not_Open;
         Diag.Message := To_Unbounded_String ("only an Open Issue may be closed");
         return False;
      end if;

      if Closed_On < Target.Recorded_On then
         Diag.Status := Close_Before_Recorded;
         Diag.Message := To_Unbounded_String
           ("Issue cannot close before its recorded date");
         return False;
      end if;

      if not Replace_Target_Row
        (Existing_Source, Issue_ID, Disposition, Closed_On, Candidate_Text)
      then
         Diag.Status := Physical_Row_Mismatch;
         Diag.Message := To_Unbounded_String
           ("admitted Issue identity did not map to exactly one physical row");
         return False;
      end if;

      if not HRA.Issues.Admit_Issues_TSV
        (To_String (Candidate_Text), Candidate_Inventory, Candidate_Diag)
      then
         Diag :=
           (Status  => Candidate_Admission_Failed,
            Issue   => HRA.Issues.To_Unbounded (Issue_ID),
            Source  => Candidate_Diag,
            Message => To_Unbounded_String ("prepared Issue close candidate is not admitted"));
         return False;
      end if;

      Candidate := (Source_Text => Candidate_Text);
      return True;
   end Prepare_Close;

end HRA.Issue_Close;
