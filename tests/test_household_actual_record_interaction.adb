with Ada.Command_Line;
with Ada.Text_IO; use Ada.Text_IO;
with HRA.Household_Actual_Record_Interaction;
use HRA.Household_Actual_Record_Interaction;

procedure Test_Household_Actual_Record_Interaction is
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

begin
   Put_Line ("--- Testing HRA.Household_Actual_Record_Interaction ---");

   -- =========================================================================
   -- 1. Initial Focus & Clamping
   -- =========================================================================
   declare
      Init : constant Editor_Focus := Initial_Focus;
      C1   : constant Editor_Focus :=
        Clamp_Focus ((Kind => Account_Field, Posting_Index => 5), 3);
      C2   : constant Editor_Focus :=
        Clamp_Focus ((Kind => Description_Field, Posting_Index => 4), 3);
   begin
      Assert
        (Init.Kind = Description_Field and then Init.Posting_Index = 1,
         "Initial_Focus defaults to Description_Field at index 1");

      Assert
        (C1.Kind = Account_Field and then C1.Posting_Index = 3,
         "Clamp_Focus clamps posting index to current posting count");

      Assert
        (C2.Kind = Description_Field and then C2.Posting_Index = 1,
         "Clamp_Focus sets Description_Field posting index strictly to 1");
   end;

   -- =========================================================================
   -- 2. Forward Cycle Navigation (2 postings)
   -- =========================================================================
   declare
      F0 : Editor_Focus := (Kind => Description_Field, Posting_Index => 1);
      F1, F2, F3, F4, F5 : Editor_Focus;
   begin
      F1 := Next_Field (F0, 2);
      F2 := Next_Field (F1, 2);
      F3 := Next_Field (F2, 2);
      F4 := Next_Field (F3, 2);
      F5 := Next_Field (F4, 2);

      Assert
        (F1.Kind = Account_Field and then F1.Posting_Index = 1,
         "Forward step 1: Description -> P1 Account");
      Assert
        (F2.Kind = Amount_Field and then F2.Posting_Index = 1,
         "Forward step 2: P1 Account -> P1 Amount");
      Assert
        (F3.Kind = Account_Field and then F3.Posting_Index = 2,
         "Forward step 3: P1 Amount -> P2 Account");
      Assert
        (F4.Kind = Amount_Field and then F4.Posting_Index = 2,
         "Forward step 4: P2 Account -> P2 Amount");
      Assert
        (F5.Kind = Description_Field and then F5.Posting_Index = 1,
         "Forward step 5: P2 Amount -> Description (wraps to start)");
   end;

   -- =========================================================================
   -- 3. Reverse Cycle Navigation (2 postings)
   -- =========================================================================
   declare
      F0 : Editor_Focus := (Kind => Description_Field, Posting_Index => 1);
      F1, F2, F3, F4, F5 : Editor_Focus;
   begin
      F1 := Previous_Field (F0, 2);
      F2 := Previous_Field (F1, 2);
      F3 := Previous_Field (F2, 2);
      F4 := Previous_Field (F3, 2);
      F5 := Previous_Field (F4, 2);

      Assert
        (F1.Kind = Amount_Field and then F1.Posting_Index = 2,
         "Reverse step 1: Description -> P2 Amount (wraps to tail)");
      Assert
        (F2.Kind = Account_Field and then F2.Posting_Index = 2,
         "Reverse step 2: P2 Amount -> P2 Account");
      Assert
        (F3.Kind = Amount_Field and then F3.Posting_Index = 1,
         "Reverse step 3: P2 Account -> P1 Amount");
      Assert
        (F4.Kind = Account_Field and then F4.Posting_Index = 1,
         "Reverse step 4: P1 Amount -> P1 Account");
      Assert
        (F5.Kind = Description_Field and then F5.Posting_Index = 1,
         "Reverse step 5: P1 Account -> Description");
   end;

   -- =========================================================================
   -- 4. General Multi-Posting Forward & Reverse Cycles (4 postings)
   -- =========================================================================
   declare
      Cur : Editor_Focus := (Kind => Description_Field, Posting_Index => 1);
   begin
      --  Cycle 1 + (4 * 2) = 9 steps forward
      for Step in 1 .. 9 loop
         Cur := Next_Field (Cur, 4);
      end loop;
      Assert
        (Cur.Kind = Description_Field and then Cur.Posting_Index = 1,
         "4-posting forward cycle completes full 9-field roundtrip to Description");

      --  Cycle 9 steps backward
      for Step in 1 .. 9 loop
         Cur := Previous_Field (Cur, 4);
      end loop;
      Assert
        (Cur.Kind = Description_Field and then Cur.Posting_Index = 1,
         "4-posting reverse cycle completes full 9-field roundtrip to Description");
   end;

   -- =========================================================================
   -- 5. Add Posting Row
   -- =========================================================================
   declare
      Res1 : constant Add_Row_Result := Add_Posting_Row (2);
      Res2 : constant Add_Row_Result := Add_Posting_Row (Res1.New_Count);
   begin
      Assert
        (Res1.New_Count = 3
           and then Res1.Focus.Kind = Account_Field
           and then Res1.Focus.Posting_Index = 3,
         "Add_Posting_Row from 2 yields 3 postings with focus on P3 Account");

      Assert
        (Res2.New_Count = 4
           and then Res2.Focus.Kind = Account_Field
           and then Res2.Focus.Posting_Index = 4,
         "Add_Posting_Row from 3 yields 4 postings with focus on P4 Account");
   end;

   -- =========================================================================
   -- 6. Drop Last Posting - Minimum 2 Postings Law
   -- =========================================================================
   declare
      F_Tail : constant Editor_Focus :=
        (Kind => Account_Field, Posting_Index => 2);
      Res : constant Drop_Row_Result := Drop_Last_Posting (F_Tail, 2);
   begin
      Assert
        (Res.Status = Minimum_Postings_Reached
           and then Res.New_Count = 2
           and then Res.Focus = F_Tail,
         "Drop_Last_Posting rejects dropping when count is 2 (minimum postings)");
   end;

   -- =========================================================================
   -- 7. Drop Last Posting - Accidental Deletion Guard (Not Tail Posting)
   -- =========================================================================
   declare
      F_Desc : constant Editor_Focus :=
        (Kind => Description_Field, Posting_Index => 1);
      F_P1   : constant Editor_Focus :=
        (Kind => Account_Field, Posting_Index => 1);
      F_P2   : constant Editor_Focus :=
        (Kind => Amount_Field, Posting_Index => 2);

      Res_Desc : constant Drop_Row_Result := Drop_Last_Posting (F_Desc, 3);
      Res_P1   : constant Drop_Row_Result := Drop_Last_Posting (F_P1, 3);
      Res_P2   : constant Drop_Row_Result := Drop_Last_Posting (F_P2, 3);
   begin
      Assert
        (Res_Desc.Status = Not_Tail_Posting
           and then Res_Desc.New_Count = 3
           and then Res_Desc.Focus = F_Desc,
         "Drop_Last_Posting rejects drop when focus is on Description");

      Assert
        (Res_P1.Status = Not_Tail_Posting
           and then Res_P1.New_Count = 3
           and then Res_P1.Focus = F_P1,
         "Drop_Last_Posting rejects drop when focus is on row 1 of 3");

      Assert
        (Res_P2.Status = Not_Tail_Posting
           and then Res_P2.New_Count = 3
           and then Res_P2.Focus = F_P2,
         "Drop_Last_Posting rejects drop when focus is on row 2 of 3");
   end;

   -- =========================================================================
   -- 8. Drop Last Posting - Successful Drop on Tail Posting
   -- =========================================================================
   declare
      F_Tail_Acc : constant Editor_Focus :=
        (Kind => Account_Field, Posting_Index => 3);
      F_Tail_Amt : constant Editor_Focus :=
        (Kind => Amount_Field, Posting_Index => 3);

      Res_Acc : constant Drop_Row_Result := Drop_Last_Posting (F_Tail_Acc, 3);
      Res_Amt : constant Drop_Row_Result := Drop_Last_Posting (F_Tail_Amt, 3);
   begin
      Assert
        (Res_Acc.Status = Applied
           and then Res_Acc.New_Count = 2
           and then Res_Acc.Focus.Kind = Account_Field
           and then Res_Acc.Focus.Posting_Index = 2,
         "Drop_Last_Posting on P3 Account succeeds, drops to 2 and moves focus to P2 Account");

      Assert
        (Res_Amt.Status = Applied
           and then Res_Amt.New_Count = 2
           and then Res_Amt.Focus.Kind = Account_Field
           and then Res_Amt.Focus.Posting_Index = 2,
         "Drop_Last_Posting on P3 Amount succeeds, drops to 2 and moves focus to P2 Account");
   end;

   -- =========================================================================
   -- 9. Intent Dispatch
   -- =========================================================================
   declare
      F_Init : constant Editor_Focus := Initial_Focus;
      R_Next : constant Interaction_Result :=
        Apply_Intent (F_Init, 2, Next_Field_Intent);
      R_Prev : constant Interaction_Result :=
        Apply_Intent (F_Init, 2, Previous_Field_Intent);
      R_Add  : constant Interaction_Result :=
        Apply_Intent (F_Init, 2, Add_Row_Intent);
      R_Add_Max : constant Interaction_Result :=
        Apply_Intent (F_Init, Positive'Last, Add_Row_Intent);
      R_Drop_Desc : constant Interaction_Result :=
        Apply_Intent (F_Init, 3, Drop_Last_Intent);
      R_Drop_Min  : constant Interaction_Result :=
        Apply_Intent ((Kind => Account_Field, Posting_Index => 2), 2, Drop_Last_Intent);
      R_Drop_Tail : constant Interaction_Result :=
        Apply_Intent ((Kind => Account_Field, Posting_Index => 3), 3, Drop_Last_Intent);
   begin
      Assert
        (R_Next.Kind = Navigation_Applied
           and then R_Next.Focus.Kind = Account_Field
           and then R_Next.Focus.Posting_Index = 1,
         "Apply_Intent Next_Field_Intent returns Navigation_Applied");

      Assert
        (R_Prev.Kind = Navigation_Applied
           and then R_Prev.Focus.Kind = Amount_Field
           and then R_Prev.Focus.Posting_Index = 2,
         "Apply_Intent Previous_Field_Intent returns Navigation_Applied");

      Assert
        (R_Add.Kind = Row_Added
           and then R_Add.New_Count = 3
           and then R_Add.Focus.Kind = Account_Field
           and then R_Add.Focus.Posting_Index = 3,
         "Apply_Intent Add_Row_Intent returns Row_Added");

      Assert
        (R_Add_Max.Kind = Notice_Maximum_Postings
           and then R_Add_Max.New_Count = Positive'Last
           and then R_Add_Max.Focus = F_Init,
         "Apply_Intent Add_Row_Intent at count=Positive'Last returns Notice_Maximum_Postings with unchanged count and focus");

      Assert
        (R_Drop_Desc.Kind = Notice_Not_Tail_Posting
           and then R_Drop_Desc.New_Count = 3,
         "Apply_Intent Drop_Last_Intent from Description returns Notice_Not_Tail_Posting");

      Assert
        (R_Drop_Min.Kind = Notice_Minimum_Postings
           and then R_Drop_Min.New_Count = 2,
         "Apply_Intent Drop_Last_Intent at count=2 returns Notice_Minimum_Postings");

      Assert
        (R_Drop_Tail.Kind = Row_Dropped
           and then R_Drop_Tail.New_Count = 2
           and then R_Drop_Tail.Focus.Kind = Account_Field
           and then R_Drop_Tail.Focus.Posting_Index = 2,
         "Apply_Intent Drop_Last_Intent at tail returns Row_Dropped");
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
end Test_Household_Actual_Record_Interaction;
