with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA.Account;
with HRA.Household_Actual_Draft;
with HRA.Household_Actual_Record_Interaction;
with HRA.Money;
with HRA.Terminal_UTF8;
with Terminal_Interface.Curses;

package body HRA.Household_Actual_Record_TUI is

   package Drafts      renames HRA.Household_Actual_Draft;
   package Interaction renames HRA.Household_Actual_Record_Interaction;
   package Curses      renames Terminal_Interface.Curses;

   type Editor_Mode is (Editing, Previewing);

   function Field_Text
     (Draft : Drafts.Record_Draft;
      Focus : Interaction.Editor_Focus) return String
   is
   begin
      case Focus.Kind is
         when Interaction.Description_Field =>
            return Drafts.Description_Text (Draft);
         when Interaction.Account_Field =>
            return To_String
              (Drafts.Posting_At (Draft, Focus.Posting_Index).Account_Text);
         when Interaction.Amount_Field =>
            return To_String
              (Drafts.Posting_At (Draft, Focus.Posting_Index).Amount_Text);
      end case;
   end Field_Text;

   function Set_Field_Text
     (Draft : Drafts.Record_Draft;
      Focus : Interaction.Editor_Focus;
      Text  : String) return Drafts.Record_Draft
   is
   begin
      case Focus.Kind is
         when Interaction.Description_Field =>
            return Drafts.Set_Description (Draft, Text);
         when Interaction.Account_Field =>
            return Drafts.Set_Posting
              (Draft,
               Focus.Posting_Index,
               Text,
               To_String
                 (Drafts.Posting_At (Draft, Focus.Posting_Index).Amount_Text));
         when Interaction.Amount_Field =>
            return Drafts.Set_Posting
              (Draft,
               Focus.Posting_Index,
               To_String
                 (Drafts.Posting_At (Draft, Focus.Posting_Index).Account_Text),
               Text);
      end case;
   end Set_Field_Text;

   function Edit
     (State : HRA.Household.Household_State;
      Day   : HRA.Dates.Date) return Edit_Result
   is
      Draft      : Drafts.Record_Draft := Drafts.Start (Day);
      Focus      : Interaction.Editor_Focus := Interaction.Initial_Focus;
      Mode       : Editor_Mode := Editing;
      Candidate  : HRA.Ledger.Transaction;
      Draft_Diag : Drafts.Build_Diagnostic;
      Notice     : Unbounded_String := Null_Unbounded_String;

      procedure Apply_Interaction
        (Intent : Interaction.Interaction_Intent_Kind)
      is
         use type Interaction.Interaction_Result_Kind;
         Res : constant Interaction.Interaction_Result :=
           Interaction.Apply_Intent
             (Focus         => Focus,
              Posting_Count => Drafts.Posting_Count (Draft),
              Intent        => Intent);
      begin
         case Res.Kind is
            when Interaction.Navigation_Applied =>
               Focus  := Res.Focus;
               Notice := Null_Unbounded_String;
            when Interaction.Row_Added =>
               Draft  := Drafts.Resize_Postings (Draft, Res.New_Count);
               Focus  := Res.Focus;
               Notice := Null_Unbounded_String;
            when Interaction.Row_Dropped =>
               Draft  := Drafts.Resize_Postings (Draft, Res.New_Count);
               Focus  := Res.Focus;
               Notice := Null_Unbounded_String;
            when Interaction.Notice_Minimum_Postings =>
               Focus  := Res.Focus;
               Notice :=
                 To_Unbounded_String
                   ("Transaction requires at least two postings.");
            when Interaction.Notice_Maximum_Postings =>
               Focus  := Res.Focus;
               Notice :=
                 To_Unbounded_String
                   ("Maximum number of postings reached.");
            when Interaction.Notice_Not_Tail_Posting =>
               Focus  := Res.Focus;
               Notice :=
                 To_Unbounded_String
                   ("Only the last posting row can be dropped. Move focus to last row.");
         end case;
      end Apply_Interaction;

      procedure Draw is
         Max_Rows : constant Natural := Natural (Curses.Lines);
         Max_Columns : constant Natural := Natural (Curses.Columns);
         Writable_Columns : constant Natural :=
           (if Max_Columns > 1 then Max_Columns - 1 else 0);
         Row : Natural := 0;

         procedure Add (Text : String) is
         begin
            if Row < Max_Rows and then Writable_Columns > 0 then
               HRA.Terminal_UTF8.Add_Line
                 (Line        => Row,
                  Column      => 0,
                  Max_Columns => Writable_Columns,
                  Text        => Text);
            end if;
            Row := Row + 1;
         end Add;

         procedure Add_Field
           (Loc   : Interaction.Editor_Focus;
            Label : String)
         is
            use type Interaction.Focus_Kind;
            Prefix : constant String :=
              (if Mode = Editing
                 and then Focus.Kind = Loc.Kind
                 and then (Loc.Kind = Interaction.Description_Field
                           or else Focus.Posting_Index = Loc.Posting_Index)
               then "> "
               else "  ");
         begin
            Add (Prefix & Label & Field_Text (Draft, Loc));
         end Add_Field;

         function Formatted_Index (Index : Positive) return String is
            Raw : constant String := Positive'Image (Index);
         begin
            if Raw'Length > 0 and then Raw (Raw'First) = ' ' then
               return Raw (Raw'First + 1 .. Raw'Last);
            else
               return Raw;
            end if;
         end Formatted_Index;

      begin
         Curses.Clear;
         Add ("================================================================================");
         Add (" Record Actual: " & HRA.Dates.Image (Day));
         Add ("================================================================================");

         if Mode = Editing then
            Add (" Signed postings must balance. Amount may be '-700' or '-12.50 USD'.");
            Add ("");
            Add_Field
              (Loc   => (Kind => Interaction.Description_Field, Posting_Index => 1),
               Label => "Description : ");
            Add ("");
            for Index in 1 .. Drafts.Posting_Count (Draft) loop
               Add (" Posting " & Formatted_Index (Index));
               Add_Field
                 (Loc   => (Kind => Interaction.Account_Field, Posting_Index => Index),
                  Label => "Account     : ");
               Add_Field
                 (Loc   => (Kind => Interaction.Amount_Field, Posting_Index => Index),
                  Label => "Amount      : ");
               Add ("");
            end loop;
            if Length (Notice) > 0 then
               Add (" ! " & To_String (Notice));
               Add ("");
            end if;
            Add (" [Tab] next  [Shift-Tab] prev  [Ctrl-N] add row  [Ctrl-D] drop last  [Enter] preview  [Esc] cancel");
         else
            Add (" Preview");
            Add ("");
            Add (" Description : " & To_String (Candidate.Code_Or_Payee));
            Add ("");
            for Index in 1 .. Natural (Candidate.Postings.Length) loop
               declare
                  Posting : constant HRA.Ledger.Posting :=
                    Candidate.Postings.Element (Index);
               begin
                  Add
                    (" " & Formatted_Index (Index) & ". " &
                     HRA.Account.Name (Posting.Acc) & "  " &
                     HRA.Money.Render_Quantity (Posting.Amt.Val) & " " &
                     HRA.Money.Code (Posting.Amt.Comm));
               end;
            end loop;
            Add ("");
            Add (" [Enter] record  [Esc] edit");
         end if;

         Curses.Refresh;
      end Draw;

      procedure Append_Character
        (Code_Point : HRA.Terminal_UTF8.Unicode_Code_Point)
      is
         Current : constant String := Field_Text (Draft, Focus);
      begin
         Draft :=
           Set_Field_Text
             (Draft,
              Focus,
              HRA.Terminal_UTF8.Append_Code_Point (Current, Code_Point));
         Notice := Null_Unbounded_String;
      end Append_Character;

      procedure Backspace is
         Current : constant String := Field_Text (Draft, Focus);
      begin
         Draft :=
           Set_Field_Text
             (Draft,
              Focus,
              HRA.Terminal_UTF8.Drop_Last_Code_Point (Current));
         Notice := Null_Unbounded_String;
      end Backspace;

      procedure Prepare_Preview is
      begin
         if Drafts.Build_Transaction
           (State, Draft, Candidate, Draft_Diag)
         then
            Mode := Previewing;
            Notice := Null_Unbounded_String;
         else
            Notice :=
              (if Length (Draft_Diag.Message) > 0
               then Draft_Diag.Message
               else To_Unbounded_String
                 (Drafts.Build_Status'Image (Draft_Diag.Status)));
         end if;
      end Prepare_Preview;

   begin
      Draw;
      loop
         declare
            Event : constant HRA.Terminal_UTF8.Input_Event :=
              HRA.Terminal_UTF8.Read_Input;
         begin
            case Event.Kind is
               when HRA.Terminal_UTF8.Character_Input =>
                  case Event.Code_Point is
                     when 14 =>
                        if Mode = Editing then
                           Apply_Interaction (Interaction.Add_Row_Intent);
                        end if;
                     when 4 =>
                        if Mode = Editing then
                           Apply_Interaction (Interaction.Drop_Last_Intent);
                        end if;
                     when 27 =>
                        if Mode = Previewing then
                           Mode := Editing;
                        else
                           return (Kind => Cancelled);
                        end if;
                     when 9 =>
                        if Mode = Editing then
                           Apply_Interaction (Interaction.Next_Field_Intent);
                        end if;
                     when 10 | 13 =>
                        if Mode = Previewing then
                           return (Kind => Accepted, Tx => Candidate);
                        else
                           Prepare_Preview;
                        end if;
                     when 8 | 127 =>
                        if Mode = Editing then
                           Backspace;
                        end if;
                     when 32 .. 126
                        | 128 .. HRA.Terminal_UTF8.Unicode_Code_Point'Last =>
                        if Mode = Editing then
                           Append_Character (Event.Code_Point);
                        end if;
                     when others =>
                        null;
                  end case;

               when HRA.Terminal_UTF8.Special_Key_Input =>
                  if Event.Key_Code = Integer (Curses.Key_Resize) then
                     null;
                  elsif Mode = Editing
                    and then Event.Key_Code = Integer (Curses.Key_Backspace)
                  then
                     Backspace;
                  elsif Mode = Editing
                    and then Event.Key_Code = Integer (Curses.Key_Back_Tab)
                  then
                     Apply_Interaction (Interaction.Previous_Field_Intent);
                  elsif Event.Key_Code = Integer (Curses.Key_Enter_Or_Send) then
                     if Mode = Previewing then
                        return (Kind => Accepted, Tx => Candidate);
                      else
                        Prepare_Preview;
                     end if;
                  end if;
            end case;
         end;
         Draw;
      end loop;
   end Edit;

end HRA.Household_Actual_Record_TUI;
