with Ada.Command_Line;
with Ada.Text_IO; use Ada.Text_IO;
with HRA.Dates; use HRA.Dates;
with HRA.Household_Home_Interaction; use HRA.Household_Home_Interaction;
with HRA.Household_Home_TUI_Input; use HRA.Household_Home_TUI_Input;
with Terminal_Interface.Curses;

procedure Test_Household_Home_TUI_Input is
   package Curses renames Terminal_Interface.Curses;

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

   function D (S : String) return HRA.Dates.Date is
      Val  : HRA.Dates.Date;
      Stat : HRA.Dates.Date_Status;
   begin
      if not HRA.Dates.Parse (S, Val, Stat) then
         raise Program_Error with "invalid test date: " & S;
      end if;
      return Val;
   end D;

   function Is_Navigation
     (Key  : Integer;
      Kind : Home_Intent_Kind) return Boolean
   is
      Action : constant Input_Action := Decode_Key (Key);
   begin
      return
        Action.Kind = Navigate
        and then Action.Intent.Kind = Kind;
   end Is_Navigation;

begin
   Put_Line ("--- Testing HRA.Household_Home_TUI_Input ---");

   Assert
     (Is_Navigation (Character'Pos ('h'), Previous_Day),
      "h maps to Previous_Day");
   Assert
     (Is_Navigation (Integer (Curses.KEY_LEFT), Previous_Day),
      "KEY_LEFT maps to Previous_Day");
   Assert
     (Is_Navigation (Character'Pos ('l'), Next_Day),
      "l maps to Next_Day");
   Assert
     (Is_Navigation (Integer (Curses.KEY_RIGHT), Next_Day),
      "KEY_RIGHT maps to Next_Day");
   Assert
     (Is_Navigation (Character'Pos ('k'), Previous_Week),
      "k maps to Previous_Week");
   Assert
     (Is_Navigation (Integer (Curses.KEY_UP), Previous_Week),
      "KEY_UP maps to Previous_Week");
   Assert
     (Is_Navigation (Character'Pos ('j'), Next_Week),
      "j maps to Next_Week");
   Assert
     (Is_Navigation (Integer (Curses.KEY_DOWN), Next_Week),
      "KEY_DOWN maps to Next_Week");
   Assert
     (Is_Navigation (Character'Pos ('g'), Focus_Observed_Through),
      "g maps to Focus_Observed_Through");
   Assert
     (Is_Navigation (Character'Pos ('G'), Focus_Observed_Through),
      "G maps to Focus_Observed_Through");

   Assert
     (Decode_Key (Character'Pos ('q')).Kind = Quit,
      "q maps to Quit without a Home intent");
   Assert
     (Decode_Key (Character'Pos ('Q')).Kind = Quit,
      "Q maps to Quit without a Home intent");
   Assert
     (Decode_Key (12).Kind = Redraw,
      "Ctrl+L maps to Redraw without a Home intent");
   Assert
     (Decode_Key (Integer (Curses.Key_Resize)).Kind = Redraw,
      "KEY_RESIZE maps to Redraw without a Home intent");
   Assert
     (Decode_Key (Character'Pos ('x')).Kind = Ignored,
      "undefined key maps to Ignored");

   --  The mapper produces semantic intents; the proved interaction owner remains
   --  responsible for all coordinate changes.
   declare
      Horizon : constant HRA.Dates.Date := D ("2026-08-19");
      Before  : constant Home_Coordinates :=
        Make_Coordinates (Horizon, D ("2026-08-10"));
      Action  : constant Input_Action := Decode_Key (Character'Pos ('l'));
   begin
      if Action.Kind = Navigate then
         declare
            Result : constant Transition_Result :=
              Apply_Intent (Before, Action.Intent);
         begin
            Assert
              (Result.Status = Applied
                 and then Image (Result.Coordinates.Selected_Day) = "2026-08-11",
               "decoded Next_Day is applied by Home interaction");
            Assert
              (Result.Coordinates.Observed_Through = Horizon,
               "decoded navigation preserves Observed_Through");
         end;
      else
         Assert (False, "l must produce a navigation intent");
         Assert (False, "l navigation must preserve Observed_Through");
      end if;
   end;

   declare
      Minimum : constant Home_Coordinates :=
        Make_Coordinates (D ("2026-08-19"), D ("0001-01-01"));
      Action  : constant Input_Action := Decode_Key (Character'Pos ('h'));
   begin
      if Action.Kind = Navigate then
         declare
            Result : constant Transition_Result :=
              Apply_Intent (Minimum, Action.Intent);
         begin
            Assert
              (Result.Status = Lower_Bound_Exceeded,
               "decoded Previous_Day fails closed at Gregorian lower bound");
            Assert
              (Result.Coordinates.Selected_Day = Minimum.Selected_Day,
               "lower-bound failure preserves Selected_Day");
         end;
      else
         Assert (False, "h must produce a navigation intent at lower bound");
         Assert (False, "lower-bound navigation must preserve Selected_Day");
      end if;
   end;

   declare
      Maximum : constant Home_Coordinates :=
        Make_Coordinates (D ("2026-08-19"), D ("9999-12-31"));
      Action  : constant Input_Action := Decode_Key (Character'Pos ('l'));
   begin
      if Action.Kind = Navigate then
         declare
            Result : constant Transition_Result :=
              Apply_Intent (Maximum, Action.Intent);
         begin
            Assert
              (Result.Status = Upper_Bound_Exceeded,
               "decoded Next_Day fails closed at Gregorian upper bound");
            Assert
              (Result.Coordinates.Selected_Day = Maximum.Selected_Day,
               "upper-bound failure preserves Selected_Day");
         end;
      else
         Assert (False, "l must produce a navigation intent at upper bound");
         Assert (False, "upper-bound navigation must preserve Selected_Day");
      end if;
   end;

   New_Line;
   Put_Line
     ("Home TUI input tests: " & Natural'Image (Passed_Count) &
      " passed," & Natural'Image (Failed_Count) & " failed");

   if Failed_Count > 0 then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Test_Household_Home_TUI_Input;
