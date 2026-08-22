with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA.Account;
with HRA.Household_Actual_Draft;
with HRA.Money;
with HRA.Terminal_UTF8;
with Terminal_Interface.Curses;

package body HRA.Household_Actual_Record_TUI is

   package Drafts renames HRA.Household_Actual_Draft;
   package Curses renames Terminal_Interface.Curses;

   type Editor_Mode is (Editing, Previewing);

   type Focus_Field is
     (Description_Field,
      First_Account_Field,
      First_Amount_Field,
      Second_Account_Field,
      Second_Amount_Field);

   function Next_Field (Field : Focus_Field) return Focus_Field is
   begin
      case Field is
         when Description_Field    => return First_Account_Field;
         when First_Account_Field  => return First_Amount_Field;
         when First_Amount_Field   => return Second_Account_Field;
         when Second_Account_Field => return Second_Amount_Field;
         when Second_Amount_Field  => return Description_Field;
      end case;
   end Next_Field;

   function Previous_Field (Field : Focus_Field) return Focus_Field is
   begin
      case Field is
         when Description_Field    => return Second_Amount_Field;
         when First_Account_Field  => return Description_Field;
         when First_Amount_Field   => return First_Account_Field;
         when Second_Account_Field => return First_Amount_Field;
         when Second_Amount_Field  => return Second_Account_Field;
      end case;
   end Previous_Field;

   function Field_Text
     (Draft : Drafts.Record_Draft;
      Field : Focus_Field) return String
   is
   begin
      case Field is
         when Description_Field =>
            return Drafts.Description_Text (Draft);
         when First_Account_Field =>
            return To_String (Drafts.Posting_At (Draft, 1).Account_Text);
         when First_Amount_Field =>
            return To_String (Drafts.Posting_At (Draft, 1).Amount_Text);
         when Second_Account_Field =>
            return To_String (Drafts.Posting_At (Draft, 2).Account_Text);
         when Second_Amount_Field =>
            return To_String (Drafts.Posting_At (Draft, 2).Amount_Text);
      end case;
   end Field_Text;

   function Set_Field_Text
     (Draft : Drafts.Record_Draft;
      Field : Focus_Field;
      Text  : String) return Drafts.Record_Draft
   is
   begin
      case Field is
         when Description_Field =>
            return Drafts.Set_Description (Draft, Text);
         when First_Account_Field =>
            return Drafts.Set_Posting
              (Draft,
               1,
               Text,
               To_String (Drafts.Posting_At (Draft, 1).Amount_Text));
         when First_Amount_Field =>
            return Drafts.Set_Posting
              (Draft,
               1,
               To_String (Drafts.Posting_At (Draft, 1).Account_Text),
               Text);
         when Second_Account_Field =>
            return Drafts.Set_Posting
              (Draft,
               2,
               Text,
               To_String (Drafts.Posting_At (Draft, 2).Amount_Text));
         when Second_Amount_Field =>
            return Drafts.Set_Posting
              (Draft,
               2,
               To_String (Drafts.Posting_At (Draft, 2).Account_Text),
               Text);
      end case;
   end Set_Field_Text;

   function Edit
     (State : HRA.Household.Household_State;
      Day   : HRA.Dates.Date) return Edit_Result
   is
      Draft : Drafts.Record_Draft := Drafts.Start (Day);
      Focus : Focus_Field := Description_Field;
      Mode  : Editor_Mode := Editing;
      Candidate : HRA.Ledger.Transaction;
      Draft_Diag : Drafts.Build_Diagnostic;
      Notice : Unbounded_String := Null_Unbounded_String;

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
           (Field : Focus_Field;
            Label : String)
         is
            Prefix : constant String :=
              (if Mode = Editing and then Focus = Field then "> " else "  ");
         begin
            Add (Prefix & Label & Field_Text (Draft, Field));
         end Add_Field;
      begin
         Curses.Clear;
         Add ("================================================================================");
         Add (" Record Actual: " & HRA.Dates.Image (Day));
         Add ("================================================================================");

         if Mode = Editing then
            Add (" Signed postings must balance. Amount may be '-700' or '-12.50 USD'.");
            Add ("");
            Add_Field (Description_Field, "Description : ");
            Add ("");
            Add (" Posting 1");
            Add_Field (First_Account_Field, "Account     : ");
            Add_Field (First_Amount_Field,  "Amount      : ");
            Add ("");
            Add (" Posting 2");
            Add_Field (Second_Account_Field, "Account     : ");
            Add_Field (Second_Amount_Field,  "Amount      : ");
            Add ("");
            if Length (Notice) > 0 then
               Add (" ! " & To_String (Notice));
               Add ("");
            end if;
            Add (" [Tab] next  [Shift-Tab] previous  [Enter] preview  [Esc] cancel");
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
                    (" " & Positive'Image (Index) & ". " &
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
                     when 27 =>
                        if Mode = Previewing then
                           Mode := Editing;
                        else
                           return (Kind => Cancelled);
                        end if;
                     when 9 =>
                        if Mode = Editing then
                           Focus := Next_Field (Focus);
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
                     when 32 .. HRA.Terminal_UTF8.Unicode_Code_Point'Last =>
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
                     Focus := Previous_Field (Focus);
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
