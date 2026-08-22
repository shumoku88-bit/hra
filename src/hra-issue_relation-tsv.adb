with Ada.Containers.Indefinite_Ordered_Sets;
with Ada.Strings;       use Ada.Strings;
with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with HRA.Actual_Admission;
with HRA.Dates;
with HRA.Issues;

package body HRA.Issue_Relation.TSV is

   Canonical_Header : constant String :=
     "relation_event_id" & ASCII.HT &
     "recorded_on"       & ASCII.HT &
     "issue_id"          & ASCII.HT &
     "relation_kind"     & ASCII.HT &
     "target_id"         & ASCII.HT &
     "details";

   package String_Sets is new Ada.Containers.Indefinite_Ordered_Sets
     (Element_Type => String);

   type Field_Array is array (1 .. 6) of Unbounded_String;

   function Count (History : Relation_History) return Natural is
     (Natural (History.Items.Length));

   function Element
     (History : Relation_History;
      Index   : Positive) return HRA.Issue_Relation.Relation_Event is
     (History.Items.Element (Index));

   function Without_Trailing_CR (Line : String) return String;

   function Canonical_Header_Text return String is (Canonical_Header);

   function Render_Event_Row
     (Event : HRA.Issue_Relation.Relation_Event) return String is
     (HRA.Issue_Relation.Text (HRA.Issue_Relation.Event_Id (Event)) &
      ASCII.HT &
      HRA.Dates.Image (HRA.Issue_Relation.Recorded_On (Event)) &
      ASCII.HT &
      HRA.Issues.Text (HRA.Issue_Relation.Issue_Id (Event)) &
      ASCII.HT &
      (case HRA.Issue_Relation.Kind (Event) is
          when HRA.Issue_Relation.Realized_As => "realized-as") &
      ASCII.HT &
      (case HRA.Issue_Relation.Kind (Event) is
          when HRA.Issue_Relation.Realized_As =>
             HRA.Actual_Admission.Text
               (HRA.Issue_Relation.Actual_Id (Event))) &
      ASCII.HT &
      HRA.Issue_Relation.Details (Event));

   function Has_Canonical_Header (Source_Text : String) return Boolean is
      Line_Start : Natural := Source_Text'First;
   begin
      while Line_Start <= Source_Text'Last loop
         declare
            Line_End : Natural := Line_Start;
         begin
            while Line_End <= Source_Text'Last
              and then Source_Text (Line_End) /= ASCII.LF
            loop
               Line_End := Line_End + 1;
            end loop;

            declare
               Raw : constant String :=
                 (if Line_End > Line_Start
                  then Source_Text (Line_Start .. Line_End - 1)
                  else "");
               Line : constant String := Without_Trailing_CR (Raw);
            begin
               if Line = Canonical_Header then
                  return True;
               end if;
            end;

            Line_Start := Line_End + 1;
         end;
      end loop;
      return False;
   end Has_Canonical_Header;

   function Without_Trailing_CR (Line : String) return String is
   begin
      if Line'Length = 0 or else Line (Line'Last) /= ASCII.CR then
         return Line;
      elsif Line'Length = 1 then
         return "";
      else
         return Line (Line'First .. Line'Last - 1);
      end if;
   end Without_Trailing_CR;

   function Is_Meaningful (Line : String) return Boolean is
      Stripped : constant String := Trim (Line, Both);
   begin
      return Stripped'Length > 0 and then Stripped (Stripped'First) /= '#';
   end Is_Meaningful;

   function Split_Line
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
   end Split_Line;

   function Admit
     (TSV_Text : String;
      History  : out Relation_History;
      Diag     : out Admission_Diagnostic) return Boolean
   is
      Output     : Relation_History;
      Seen       : String_Sets.Set;
      Saw_Header : Boolean := False;
      Line_Start : Natural := TSV_Text'First;
      Line_No    : Natural := 0;

      procedure Fail
        (Status   : Admission_Status;
         Line     : Natural;
         Event_ID : String;
         Message  : String)
      is
      begin
         Diag :=
           (Status            => Status,
            Line_Number       => Line,
            Relation_Event_Id => To_Unbounded_String (Event_ID),
            Message           => To_Unbounded_String (Message));
      end Fail;

      function Parse_Row (Line : String; Number : Positive) return Boolean is
         Fields       : Field_Array;
         Event_ID     : HRA.Issue_Relation.Relation_Event_Id;
         Event_Status : HRA.Issue_Relation.Relation_Event_Id_Status;
         Event_Date   : HRA.Dates.Date;
         Date_Status  : HRA.Dates.Date_Status;
         Issue_ID     : HRA.Issues.Issue_Id;
         Issue_Status : HRA.Issues.Issue_Id_Status;
         Actual_ID    : HRA.Actual_Admission.Actual_Id;
         Actual_Status : HRA.Actual_Admission.Actual_Id_Status;
         Event        : HRA.Issue_Relation.Relation_Event;
         Create_State : HRA.Issue_Relation.Create_Status;
      begin
         if not Split_Line (Line, Fields) then
            Fail
              (Malformed_Column_Count, Number, "",
               "expected six Issue relation columns");
            return False;
         end if;

         if not HRA.Issue_Relation.Create_Relation_Event_Id
           (To_String (Fields (1)), Event_ID, Event_Status)
         then
            Fail
              (Invalid_Relation_Event_Id, Number, To_String (Fields (1)),
               "invalid relation_event_id");
            return False;
         end if;

         if Seen.Contains (HRA.Issue_Relation.Text (Event_ID)) then
            Fail
              (Duplicate_Relation_Event_Id, Number,
               HRA.Issue_Relation.Text (Event_ID),
               "relation_event_id identifies more than one relation event");
            return False;
         end if;

         if not HRA.Dates.Parse
           (To_String (Fields (2)), Event_Date, Date_Status)
         then
            Fail
              (Invalid_Recorded_Date, Number,
               HRA.Issue_Relation.Text (Event_ID),
               "invalid recorded_on date");
            return False;
         end if;

         if not HRA.Issues.Create_Issue_Id
           (To_String (Fields (3)), Issue_ID, Issue_Status)
         then
            Fail
              (Invalid_Issue_Id, Number,
               HRA.Issue_Relation.Text (Event_ID),
               "invalid issue_id");
            return False;
         end if;

         if To_String (Fields (4)) /= "realized-as" then
            Fail
              (Unknown_Relation_Kind, Number,
               HRA.Issue_Relation.Text (Event_ID),
               "unknown relation_kind");
            return False;
         end if;

         if not HRA.Actual_Admission.Create_Actual_Id
           (To_String (Fields (5)), Actual_ID, Actual_Status)
         then
            Fail
              (Invalid_Actual_Id, Number,
               HRA.Issue_Relation.Text (Event_ID),
               "invalid realized-as target_id");
            return False;
         end if;

         if not HRA.Issue_Relation.Create_Realized_As
           (Event_ID    => Event_ID,
            Recorded_On => Event_Date,
            Issue_ID    => Issue_ID,
            Actual_ID   => Actual_ID,
            Details     => To_String (Fields (6)),
            Event       => Event,
            Status      => Create_State)
         then
            Fail
              (Invalid_Details, Number,
               HRA.Issue_Relation.Text (Event_ID),
               "invalid relation details");
            return False;
         end if;

         Seen.Insert (HRA.Issue_Relation.Text (Event_ID));
         Output.Items.Append (Event);
         return True;
      end Parse_Row;

      function Process_Line (Raw_Line : String; Number : Positive) return Boolean is
         Line : constant String := Without_Trailing_CR (Raw_Line);
      begin
         if not Is_Meaningful (Line) then
            return True;
         elsif not Saw_Header then
            if Line /= Canonical_Header then
               Fail (Invalid_Header, Number, "", "unexpected Issue relation header");
               return False;
            end if;
            Saw_Header := True;
            return True;
         else
            return Parse_Row (Line, Number);
         end if;
      end Process_Line;

   begin
      Output.Items.Clear;
      History.Items.Clear;
      Diag :=
        (Status            => Success,
         Line_Number       => 0,
         Relation_Event_Id => Null_Unbounded_String,
         Message           => Null_Unbounded_String);

      while Line_Start <= TSV_Text'Last loop
         Line_No := Line_No + 1;
         declare
            Line_End : Natural := Line_Start;
         begin
            while Line_End <= TSV_Text'Last
              and then TSV_Text (Line_End) /= ASCII.LF
            loop
               Line_End := Line_End + 1;
            end loop;

            if not Process_Line
              (TSV_Text (Line_Start .. Line_End - 1), Positive (Line_No))
            then
               return False;
            end if;

            Line_Start := Line_End + 1;
         end;
      end loop;

      History := Output;
      return True;
   end Admit;

end HRA.Issue_Relation.TSV;
