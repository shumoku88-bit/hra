with Ada.Command_Line;
with Ada.Text_IO; use Ada.Text_IO;
with HRA.Terminal_Layout;
with HRA.Terminal_UTF8;

procedure Test_Terminal_Layout is
   use HRA.Terminal_Layout;

   function U
     (Text : String;
      Code : HRA.Terminal_UTF8.Unicode_Code_Point) return String is
     (HRA.Terminal_UTF8.Append_Code_Point (Text, Code));

   Date_JA    : constant String := U (U ("", 16#65E5#), 16#4ED8#);
   Content_JA : constant String := U (U ("", 16#5185#), 16#5BB9#);
   Amount_JA  : constant String := U (U ("", 16#91D1#), 16#984D#);
   Grocery_JA : constant String :=
     U (U (U ("", 16#98DF#), 16#6599#), 16#54C1#);
   Book_JA    : constant String := U ("", 16#672C#);

   Passed_Count : Natural := 0;
   Failed_Count : Natural := 0;

   procedure Assert (Condition : Boolean; Test_Name : String) is
   begin
      if Condition then
         Put_Line ("[PASS] " & Test_Name);
         Passed_Count := Passed_Count + 1;
      else
         Put_Line ("[FAIL] " & Test_Name);
         Failed_Count := Failed_Count + 1;
      end if;
   end Assert;

   function Separator_Column
     (Text : String; Occurrence : Positive) return Natural
   is
      Seen : Natural := 0;
   begin
      for Index in Text'Range loop
         if Text (Index) = '|' then
            Seen := Seen + 1;
            if Seen = Occurrence then
               if Index = Text'First then
                  return 0;
               end if;
               return Display_Width (Text (Text'First .. Index - 1));
            end if;
         end if;
      end loop;
      raise Program_Error with "missing test separator";
   end Separator_Column;

   Header : constant String :=
     "| " & Pad_Right (Date_JA, 10) &
     " | " & Pad_Right (Content_JA, 16) &
     " | " & Pad_Left (Amount_JA, 10) & " |";
   Japanese_Row : constant String :=
     "| " & Pad_Right ("2026-08-22", 10) &
     " | " & Pad_Right (Grocery_JA, 16) &
     " | " & Pad_Left ("1,280", 10) & " |";
   Mixed_Row : constant String :=
     "| " & Pad_Right ("2026-08-22", 10) &
     " | " & Pad_Right ("A Case of You " & Book_JA, 16) &
     " | " & Pad_Left ("3,200", 10) & " |";

begin
   Put_Line ("--- Testing terminal cell layout primitives ---");

   Assert (Display_Width ("ASCII") = 5, "ASCII width is measured in cells");
   Assert
     (Display_Width (Grocery_JA) = 6,
      "Japanese full-width glyphs occupy two cells each");
   Assert
     (Display_Width ("A Case of You " & Book_JA) = 16,
      "mixed UTF-8 width combines ASCII and full-width cells");

   Assert
     (Pad_Right (Grocery_JA, 10) = Grocery_JA & "    ",
      "right padding uses display width rather than UTF-8 byte length");
   Assert
     (Pad_Left ("1,280", 10) = "     1,280",
      "numeric text is right aligned to a display width");
   Assert
     (Align ("42", 5, Right) = "   42"
      and then Align ("42", 5, Left) = "42   ",
      "alignment delegates to left and right padding");
   Assert
     (Pad_Right ("already wide", 4) = "already wide",
      "padding never truncates an over-width value");

   Assert
     (Display_Width (Header) = Display_Width (Japanese_Row)
      and then Display_Width (Header) = Display_Width (Mixed_Row),
      "ASCII, Japanese, and mixed rows have one terminal width");

   for Separator in 1 .. 4 loop
      Assert
        (Separator_Column (Header, Separator) =
           Separator_Column (Japanese_Row, Separator)
         and then Separator_Column (Header, Separator) =
           Separator_Column (Mixed_Row, Separator),
         "separator" & Separator'Image & " stays in one terminal column");
   end loop;

   Assert
     (Separator_Column (Header, 3) = 32
      and then Separator_Column (Header, 4) = 45,
      "right-aligned numeric column has stable boundaries");

   Put_Line
     ("Summary: Passed =" & Natural'Image (Passed_Count) &
      ", Failed =" & Natural'Image (Failed_Count));
   if Failed_Count > 0 then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   else
      Put_Line ("RESULT: SUCCESS");
   end if;
end Test_Terminal_Layout;
