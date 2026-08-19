with Ada.Command_Line;
with Ada.Text_IO; use Ada.Text_IO;
with HRA.Dates;   use HRA.Dates;
with HRA.Household_Home_Interaction; use HRA.Household_Home_Interaction;

procedure Test_Household_Home_Interaction is
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

   Horizon : constant HRA.Dates.Date := D ("2026-08-19");

begin
   Put_Line ("--- Testing HRA.Household_Home_Interaction ---");

   -- =========================================================================
   -- 1. Coordinate Construction
   -- =========================================================================
   declare
      C1 : constant Home_Coordinates := Make_Coordinates (Horizon);
      C2 : constant Home_Coordinates := Make_Coordinates (Horizon, D ("2026-08-25"));
   begin
      Assert
        (Image (C1.Observed_Through) = "2026-08-19"
           and then Image (C1.Selected_Day) = "2026-08-19",
         "Make_Coordinates (1-arg) defaults Selected_Day to Observed_Through");

      Assert
        (Image (C2.Observed_Through) = "2026-08-19"
           and then Image (C2.Selected_Day) = "2026-08-25",
         "Make_Coordinates (2-arg) retains explicit Selected_Day");
   end;

   -- =========================================================================
   -- 2. Next Day Navigation
   -- =========================================================================
   declare
      Coord : constant Home_Coordinates := Make_Coordinates (Horizon, D ("2026-08-10"));
      Res1  : constant Transition_Result := Next_Day (Coord);
      Res2  : constant Transition_Result := Apply_Intent (Coord, Intent_Next_Day);
   begin
      Assert (Res1.Status = Applied, "Next_Day status is Applied");
      Assert (Is_Applied (Res1), "Is_Applied returns True for Applied");
      Assert (Image (Res1.Coordinates.Selected_Day) = "2026-08-11", "Next_Day advances +1 day within month");
      Assert (Image (Res1.Coordinates.Observed_Through) = "2026-08-19", "Next_Day preserves Observed_Through");

      Assert (Res2.Status = Applied, "Intent_Next_Day status is Applied");
      Assert (Image (Res2.Coordinates.Selected_Day) = "2026-08-11", "Intent_Next_Day advances +1 day within month");
      Assert (Image (Res2.Coordinates.Observed_Through) = "2026-08-19", "Intent_Next_Day preserves Observed_Through");
   end;

   -- =========================================================================
   -- 3. Previous Day Navigation
   -- =========================================================================
   declare
      Coord : constant Home_Coordinates := Make_Coordinates (Horizon, D ("2026-08-10"));
      Res1  : constant Transition_Result := Previous_Day (Coord);
      Res2  : constant Transition_Result := Apply_Intent (Coord, Intent_Previous_Day);
   begin
      Assert (Res1.Status = Applied, "Previous_Day status is Applied");
      Assert (Image (Res1.Coordinates.Selected_Day) = "2026-08-09", "Previous_Day retreats -1 day within month");
      Assert (Image (Res1.Coordinates.Observed_Through) = "2026-08-19", "Previous_Day preserves Observed_Through");

      Assert (Res2.Status = Applied, "Intent_Previous_Day status is Applied");
      Assert (Image (Res2.Coordinates.Selected_Day) = "2026-08-09", "Intent_Previous_Day retreats -1 day within month");
      Assert (Image (Res2.Coordinates.Observed_Through) = "2026-08-19", "Intent_Previous_Day preserves Observed_Through");
   end;

   -- =========================================================================
   -- 4. Next Week Navigation
   -- =========================================================================
   declare
      Coord : constant Home_Coordinates := Make_Coordinates (Horizon, D ("2026-08-10"));
      Res1  : constant Transition_Result := Next_Week (Coord);
      Res2  : constant Transition_Result := Apply_Intent (Coord, Intent_Next_Week);
   begin
      Assert (Res1.Status = Applied, "Next_Week status is Applied");
      Assert (Image (Res1.Coordinates.Selected_Day) = "2026-08-17", "Next_Week advances +7 days within month");
      Assert (Image (Res1.Coordinates.Observed_Through) = "2026-08-19", "Next_Week preserves Observed_Through");

      Assert (Res2.Status = Applied, "Intent_Next_Week status is Applied");
      Assert (Image (Res2.Coordinates.Selected_Day) = "2026-08-17", "Intent_Next_Week advances +7 days within month");
      Assert (Image (Res2.Coordinates.Observed_Through) = "2026-08-19", "Intent_Next_Week preserves Observed_Through");
   end;

   -- =========================================================================
   -- 5. Previous Week Navigation
   -- =========================================================================
   declare
      Coord : constant Home_Coordinates := Make_Coordinates (Horizon, D ("2026-08-17"));
      Res1  : constant Transition_Result := Previous_Week (Coord);
      Res2  : constant Transition_Result := Apply_Intent (Coord, Intent_Previous_Week);
   begin
      Assert (Res1.Status = Applied, "Previous_Week status is Applied");
      Assert (Image (Res1.Coordinates.Selected_Day) = "2026-08-10", "Previous_Week retreats -7 days within month");
      Assert (Image (Res1.Coordinates.Observed_Through) = "2026-08-19", "Previous_Week preserves Observed_Through");

      Assert (Res2.Status = Applied, "Intent_Previous_Week status is Applied");
      Assert (Image (Res2.Coordinates.Selected_Day) = "2026-08-10", "Intent_Previous_Week retreats -7 days within month");
      Assert (Image (Res2.Coordinates.Observed_Through) = "2026-08-19", "Intent_Previous_Week preserves Observed_Through");
   end;

   -- =========================================================================
   -- 6. Month Boundary Crossing
   -- =========================================================================
   declare
      -- Jan 31 -> Feb 1
      Coord_Jan_End : constant Home_Coordinates := Make_Coordinates (Horizon, D ("2026-01-31"));
      Res_Next_Jan  : constant Transition_Result := Next_Day (Coord_Jan_End);

      -- Mar 1 -> Feb 28 (common year)
      Coord_Mar_Beg : constant Home_Coordinates := Make_Coordinates (Horizon, D ("2026-03-01"));
      Res_Prev_Mar  : constant Transition_Result := Previous_Day (Coord_Mar_Beg);

      -- Jan 28 + 7 days -> Feb 4
      Coord_Jan_Wk  : constant Home_Coordinates := Make_Coordinates (Horizon, D ("2026-01-28"));
      Res_Next_Wk   : constant Transition_Result := Next_Week (Coord_Jan_Wk);

      -- Mar 4 - 7 days -> Feb 25
      Coord_Mar_Wk  : constant Home_Coordinates := Make_Coordinates (Horizon, D ("2026-03-04"));
      Res_Prev_Wk   : constant Transition_Result := Previous_Week (Coord_Mar_Wk);

      -- Apr 30 -> May 1 (30-day month)
      Coord_Apr_End : constant Home_Coordinates := Make_Coordinates (Horizon, D ("2026-04-30"));
      Res_Next_Apr  : constant Transition_Result := Next_Day (Coord_Apr_End);

      -- May 1 -> Apr 30 (30-day month)
      Coord_May_Beg : constant Home_Coordinates := Make_Coordinates (Horizon, D ("2026-05-01"));
      Res_Prev_May  : constant Transition_Result := Previous_Day (Coord_May_Beg);
   begin
      Assert
        (Res_Next_Jan.Status = Applied
           and then Image (Res_Next_Jan.Coordinates.Selected_Day) = "2026-02-01",
         "Next_Day crosses Jan 31 -> Feb 01 month boundary");

      Assert
        (Res_Prev_Mar.Status = Applied
           and then Image (Res_Prev_Mar.Coordinates.Selected_Day) = "2026-02-28",
         "Previous_Day crosses Mar 01 -> Feb 28 month boundary (common year)");

      Assert
        (Res_Next_Wk.Status = Applied
           and then Image (Res_Next_Wk.Coordinates.Selected_Day) = "2026-02-04",
         "Next_Week crosses Jan 28 -> Feb 04 month boundary");

      Assert
        (Res_Prev_Wk.Status = Applied
           and then Image (Res_Prev_Wk.Coordinates.Selected_Day) = "2026-02-25",
         "Previous_Week crosses Mar 04 -> Feb 25 month boundary");

      Assert
        (Res_Next_Apr.Status = Applied
           and then Image (Res_Next_Apr.Coordinates.Selected_Day) = "2026-05-01",
         "Next_Day crosses Apr 30 -> May 01 month boundary");

      Assert
        (Res_Prev_May.Status = Applied
           and then Image (Res_Prev_May.Coordinates.Selected_Day) = "2026-04-30",
         "Previous_Day crosses May 01 -> Apr 30 month boundary");
   end;

   -- =========================================================================
   -- 7. Year Boundary Crossing
   -- =========================================================================
   declare
      -- Dec 31 -> Jan 1
      Coord_Dec_End : constant Home_Coordinates := Make_Coordinates (Horizon, D ("2026-12-31"));
      Res_Next_Dec  : constant Transition_Result := Next_Day (Coord_Dec_End);

      -- Jan 1 -> Dec 31
      Coord_Jan_Beg : constant Home_Coordinates := Make_Coordinates (Horizon, D ("2026-01-01"));
      Res_Prev_Jan  : constant Transition_Result := Previous_Day (Coord_Jan_Beg);

      -- Dec 28 + 7 days -> Jan 4
      Coord_Dec_Wk  : constant Home_Coordinates := Make_Coordinates (Horizon, D ("2026-12-28"));
      Res_Next_Yr   : constant Transition_Result := Next_Week (Coord_Dec_Wk);

      -- Jan 4 - 7 days -> Dec 28
      Coord_Jan_Wk  : constant Home_Coordinates := Make_Coordinates (Horizon, D ("2026-01-04"));
      Res_Prev_Yr   : constant Transition_Result := Previous_Week (Coord_Jan_Wk);
   begin
      Assert
        (Res_Next_Dec.Status = Applied
           and then Image (Res_Next_Dec.Coordinates.Selected_Day) = "2027-01-01",
         "Next_Day crosses Dec 31 -> Jan 01 year boundary");

      Assert
        (Res_Prev_Jan.Status = Applied
           and then Image (Res_Prev_Jan.Coordinates.Selected_Day) = "2025-12-31",
         "Previous_Day crosses Jan 01 -> Dec 31 year boundary");

      Assert
        (Res_Next_Yr.Status = Applied
           and then Image (Res_Next_Yr.Coordinates.Selected_Day) = "2027-01-04",
         "Next_Week crosses Dec 28 -> Jan 04 year boundary");

      Assert
        (Res_Prev_Yr.Status = Applied
           and then Image (Res_Prev_Yr.Coordinates.Selected_Day) = "2025-12-28",
         "Previous_Week crosses Jan 04 -> Dec 28 year boundary");
   end;

   -- =========================================================================
   -- 8. Leap-Day Crossing
   -- =========================================================================
   declare
      -- 2024-02-28 -> 2024-02-29
      Coord_Leap_Eve : constant Home_Coordinates := Make_Coordinates (Horizon, D ("2024-02-28"));
      Res_To_Leap    : constant Transition_Result := Next_Day (Coord_Leap_Eve);

      -- 2024-02-29 -> 2024-03-01
      Coord_Leap_Day : constant Home_Coordinates := Make_Coordinates (Horizon, D ("2024-02-29"));
      Res_From_Leap  : constant Transition_Result := Next_Day (Coord_Leap_Day);

      -- 2024-03-01 -> 2024-02-29
      Coord_Mar_Leap : constant Home_Coordinates := Make_Coordinates (Horizon, D ("2024-03-01"));
      Res_Back_Leap  : constant Transition_Result := Previous_Day (Coord_Mar_Leap);

      -- 2024-02-29 -> 2024-02-28
      Res_Prev_Leap  : constant Transition_Result := Previous_Day (Coord_Leap_Day);

      -- 2024-02-25 + 7 days -> 2024-03-03 (spanning leap day)
      Coord_Wk_Leap  : constant Home_Coordinates := Make_Coordinates (Horizon, D ("2024-02-25"));
      Res_Wk_Fwd     : constant Transition_Result := Next_Week (Coord_Wk_Leap);

      -- 2024-03-05 - 7 days -> 2024-02-27 (spanning leap day)
      Coord_Wk_Mar   : constant Home_Coordinates := Make_Coordinates (Horizon, D ("2024-03-05"));
      Res_Wk_Back    : constant Transition_Result := Previous_Week (Coord_Wk_Mar);
   begin
      Assert
        (Res_To_Leap.Status = Applied
           and then Image (Res_To_Leap.Coordinates.Selected_Day) = "2024-02-29",
         "Next_Day enters leap day (2024-02-28 -> 2024-02-29)");

      Assert
        (Res_From_Leap.Status = Applied
           and then Image (Res_From_Leap.Coordinates.Selected_Day) = "2024-03-01",
         "Next_Day leaves leap day (2024-02-29 -> 2024-03-01)");

      Assert
        (Res_Back_Leap.Status = Applied
           and then Image (Res_Back_Leap.Coordinates.Selected_Day) = "2024-02-29",
         "Previous_Day enters leap day (2024-03-01 -> 2024-02-29)");

      Assert
        (Res_Prev_Leap.Status = Applied
           and then Image (Res_Prev_Leap.Coordinates.Selected_Day) = "2024-02-28",
         "Previous_Day leaves leap day (2024-02-29 -> 2024-02-28)");

      Assert
        (Res_Wk_Fwd.Status = Applied
           and then Image (Res_Wk_Fwd.Coordinates.Selected_Day) = "2024-03-03",
         "Next_Week spans leap day (2024-02-25 + 7d = 2024-03-03)");

      Assert
        (Res_Wk_Back.Status = Applied
           and then Image (Res_Wk_Back.Coordinates.Selected_Day) = "2024-02-27",
         "Previous_Week spans leap day (2024-03-05 - 7d = 2024-02-27)");
   end;

   -- =========================================================================
   -- 9. Direct Select_Day
   -- =========================================================================
   declare
      Coord : constant Home_Coordinates := Make_Coordinates (Horizon, D ("2026-08-10"));
      Res1  : constant Transition_Result := Select_Day (Coord, D ("2030-11-20"));
      Res2  : constant Transition_Result := Apply_Intent (Coord, Intent_Select_Day (D ("2020-05-15")));
   begin
      Assert (Res1.Status = Applied, "Select_Day status is Applied");
      Assert (Image (Res1.Coordinates.Selected_Day) = "2030-11-20", "Select_Day jumps directly to target date");
      Assert (Image (Res1.Coordinates.Observed_Through) = "2026-08-19", "Select_Day preserves Observed_Through");

      Assert (Res2.Status = Applied, "Intent_Select_Day status is Applied");
      Assert (Image (Res2.Coordinates.Selected_Day) = "2020-05-15", "Intent_Select_Day jumps directly to target date");
      Assert (Image (Res2.Coordinates.Observed_Through) = "2026-08-19", "Intent_Select_Day preserves Observed_Through");
   end;

   -- =========================================================================
   -- 10. Focus_Observed_Through
   -- =========================================================================
   declare
      Coord_Past   : constant Home_Coordinates := Make_Coordinates (Horizon, D ("2026-01-15"));
      Coord_Future : constant Home_Coordinates := Make_Coordinates (Horizon, D ("2026-12-25"));
      Coord_Same   : constant Home_Coordinates := Make_Coordinates (Horizon, Horizon);

      Res_Past   : constant Transition_Result := Focus_Observed_Through (Coord_Past);
      Res_Future : constant Transition_Result := Apply_Intent (Coord_Future, Intent_Focus_Observed_Through);
      Res_Same   : constant Transition_Result := Focus_Observed_Through (Coord_Same);
   begin
      Assert (Res_Past.Status = Applied, "Focus_Observed_Through from past is Applied");
      Assert (Image (Res_Past.Coordinates.Selected_Day) = "2026-08-19", "Focus_Observed_Through resets focus to horizon");
      Assert (Image (Res_Past.Coordinates.Observed_Through) = "2026-08-19", "Observed_Through unchanged");

      Assert (Res_Future.Status = Applied, "Intent_Focus_Observed_Through from future is Applied");
      Assert (Image (Res_Future.Coordinates.Selected_Day) = "2026-08-19", "Focus_Observed_Through resets future focus to horizon");
      Assert (Image (Res_Future.Coordinates.Observed_Through) = "2026-08-19", "Observed_Through unchanged");

      Assert (Res_Same.Status = Applied, "Focus_Observed_Through when already on horizon is Applied");
      Assert (Image (Res_Same.Coordinates.Selected_Day) = "2026-08-19", "Focus remains on horizon");
   end;

   -- =========================================================================
   -- 11. Selected_Day May Move Beyond Observed_Through
   -- =========================================================================
   declare
      Coord : constant Home_Coordinates := Make_Coordinates (Horizon, Horizon);
      Res1  : constant Transition_Result := Next_Day (Coord);
      Res2  : constant Transition_Result := Next_Week (Res1.Coordinates);
   begin
      Assert
        (Res1.Status = Applied
           and then Image (Res1.Coordinates.Selected_Day) = "2026-08-20",
         "Selected_Day moves 1 day beyond Observed_Through");
      Assert
        (Image (Res1.Coordinates.Observed_Through) = "2026-08-19",
         "Observed_Through remains invariant when focus enters future");

      Assert
        (Res2.Status = Applied
           and then Image (Res2.Coordinates.Selected_Day) = "2026-08-27",
         "Selected_Day moves further into future (+1 week)");
      Assert
        (Image (Res2.Coordinates.Observed_Through) = "2026-08-19",
         "Observed_Through remains invariant across future week navigation");
   end;

   -- =========================================================================
   -- 12. Lower Gregorian Bound Fail-Closed (0001-01-01) & No Wraparound
   -- =========================================================================
   declare
      Coord_Origin : constant Home_Coordinates := Make_Coordinates (Horizon, D ("0001-01-01"));
      Coord_Jan_05 : constant Home_Coordinates := Make_Coordinates (Horizon, D ("0001-01-05"));

      Res_Prev_Day : constant Transition_Result := Previous_Day (Coord_Origin);
      Res_Prev_Wk  : constant Transition_Result := Previous_Week (Coord_Jan_05);
      Res_Wk_Orig  : constant Transition_Result := Previous_Week (Coord_Origin);
      Res_Intent   : constant Transition_Result := Apply_Intent (Coord_Origin, Intent_Previous_Day);
   begin
      Assert
        (Res_Prev_Day.Status = Lower_Bound_Exceeded,
         "Previous_Day from 0001-01-01 fails closed with Lower_Bound_Exceeded");
      Assert
        (not Is_Applied (Res_Prev_Day),
         "Is_Applied returns False for Lower_Bound_Exceeded");
      Assert
        (Image (Res_Prev_Day.Coordinates.Selected_Day) = "0001-01-01",
         "Selected_Day remains strictly 0001-01-01 without wraparound");
      Assert
        (Image (Res_Prev_Day.Coordinates.Observed_Through) = "2026-08-19",
         "Observed_Through preserved on lower bound failure");

      Assert
        (Res_Prev_Wk.Status = Lower_Bound_Exceeded,
         "Previous_Week from 0001-01-05 fails closed with Lower_Bound_Exceeded");
      Assert
        (Image (Res_Prev_Wk.Coordinates.Selected_Day) = "0001-01-05",
         "Selected_Day remains strictly 0001-01-05 without partial retreat or wraparound");

      Assert
        (Res_Wk_Orig.Status = Lower_Bound_Exceeded,
         "Previous_Week from 0001-01-01 fails closed with Lower_Bound_Exceeded");
      Assert
        (Image (Res_Wk_Orig.Coordinates.Selected_Day) = "0001-01-01",
         "Selected_Day remains 0001-01-01");

      Assert
        (Res_Intent.Status = Lower_Bound_Exceeded,
         "Intent_Previous_Day from 0001-01-01 fails closed with Lower_Bound_Exceeded");
      Assert
        (Image (Res_Intent.Coordinates.Selected_Day) = "0001-01-01",
         "Intent dispatch preserves Selected_Day on lower bound failure");
   end;

   -- =========================================================================
   -- 13. Upper Gregorian Bound Fail-Closed (9999-12-31) & No Wraparound
   -- =========================================================================
   declare
      Coord_Max    : constant Home_Coordinates := Make_Coordinates (Horizon, D ("9999-12-31"));
      Coord_Dec_28 : constant Home_Coordinates := Make_Coordinates (Horizon, D ("9999-12-28"));

      Res_Next_Day : constant Transition_Result := Next_Day (Coord_Max);
      Res_Next_Wk  : constant Transition_Result := Next_Week (Coord_Dec_28);
      Res_Wk_Max   : constant Transition_Result := Next_Week (Coord_Max);
      Res_Intent   : constant Transition_Result := Apply_Intent (Coord_Max, Intent_Next_Day);
   begin
      Assert
        (Res_Next_Day.Status = Upper_Bound_Exceeded,
         "Next_Day from 9999-12-31 fails closed with Upper_Bound_Exceeded");
      Assert
        (not Is_Applied (Res_Next_Day),
         "Is_Applied returns False for Upper_Bound_Exceeded");
      Assert
        (Image (Res_Next_Day.Coordinates.Selected_Day) = "9999-12-31",
         "Selected_Day remains strictly 9999-12-31 without wraparound");
      Assert
        (Image (Res_Next_Day.Coordinates.Observed_Through) = "2026-08-19",
         "Observed_Through preserved on upper bound failure");

      Assert
        (Res_Next_Wk.Status = Upper_Bound_Exceeded,
         "Next_Week from 9999-12-28 fails closed with Upper_Bound_Exceeded");
      Assert
        (Image (Res_Next_Wk.Coordinates.Selected_Day) = "9999-12-28",
         "Selected_Day remains strictly 9999-12-28 without partial advance or wraparound");

      Assert
        (Res_Wk_Max.Status = Upper_Bound_Exceeded,
         "Next_Week from 9999-12-31 fails closed with Upper_Bound_Exceeded");
      Assert
        (Image (Res_Wk_Max.Coordinates.Selected_Day) = "9999-12-31",
         "Selected_Day remains 9999-12-31");

      Assert
        (Res_Intent.Status = Upper_Bound_Exceeded,
         "Intent_Next_Day from 9999-12-31 fails closed with Upper_Bound_Exceeded");
      Assert
        (Image (Res_Intent.Coordinates.Selected_Day) = "9999-12-31",
         "Intent dispatch preserves Selected_Day on upper bound failure");
   end;

   -- =========================================================================
   -- 14. Complex Navigation Sequence & Invariance Under Multi-Step Transitions
   -- =========================================================================
   declare
      Coord : Home_Coordinates := Make_Coordinates (Horizon, D ("2026-08-19"));
      Intents : constant array (1 .. 6) of Home_Intent :=
        [Intent_Next_Day,               -- 2026-08-20
         Intent_Next_Week,              -- 2026-08-27
         Intent_Previous_Day,           -- 2026-08-26
         Intent_Previous_Week,          -- 2026-08-19
         Intent_Select_Day (D ("2026-12-01")), -- 2026-12-01
         Intent_Focus_Observed_Through];       -- 2026-08-19
      Expected : constant array (1 .. 6) of String (1 .. 10) :=
        ["2026-08-20",
         "2026-08-27",
         "2026-08-26",
         "2026-08-19",
         "2026-12-01",
         "2026-08-19"];
   begin
      for I in Intents'Range loop
         declare
            Res : constant Transition_Result := Apply_Intent (Coord, Intents (I));
         begin
            Assert (Res.Status = Applied, "Step" & Natural'Image (I) & " Applied");
            Assert
              (Image (Res.Coordinates.Selected_Day) = Expected (I),
               "Step" & Natural'Image (I) & " reached " & Expected (I));
            Assert
              (Image (Res.Coordinates.Observed_Through) = "2026-08-19",
               "Step" & Natural'Image (I) & " preserved Observed_Through");
            Coord := Res.Coordinates;
         end;
      end loop;
   end;

   Put_Line ("--------------------------------------------------");
   Put_Line
     ("Summary: Passed = " & Natural'Image (Passed_Count) &
      ", Failed = " & Natural'Image (Failed_Count));

   if Failed_Count > 0 then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   else
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);
   end if;
end Test_Household_Home_Interaction;
