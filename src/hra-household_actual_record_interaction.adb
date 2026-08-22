package body HRA.Household_Actual_Record_Interaction
  with SPARK_Mode => On
is

   ----------------
   -- Next_Field --
   ----------------

   function Next_Field
     (Focus         : Editor_Focus;
      Posting_Count : Positive) return Editor_Focus
   is
      Clamped : constant Editor_Focus := Clamp_Focus (Focus, Posting_Count);
   begin
      case Clamped.Kind is
         when Description_Field =>
            return (Kind => Account_Field, Posting_Index => 1);
         when Account_Field =>
            return (Kind => Amount_Field, Posting_Index => Clamped.Posting_Index);
         when Amount_Field =>
            if Clamped.Posting_Index >= Posting_Count then
               return (Kind => Description_Field, Posting_Index => 1);
            else
               return
                 (Kind          => Account_Field,
                  Posting_Index => Clamped.Posting_Index + 1);
            end if;
      end case;
   end Next_Field;

   --------------------
   -- Previous_Field --
   --------------------

   function Previous_Field
     (Focus         : Editor_Focus;
      Posting_Count : Positive) return Editor_Focus
   is
      Clamped : constant Editor_Focus := Clamp_Focus (Focus, Posting_Count);
   begin
      case Clamped.Kind is
         when Description_Field =>
            return (Kind => Amount_Field, Posting_Index => Posting_Count);
         when Amount_Field =>
            return (Kind => Account_Field, Posting_Index => Clamped.Posting_Index);
         when Account_Field =>
            if Clamped.Posting_Index = 1 then
               return (Kind => Description_Field, Posting_Index => 1);
            else
               return
                 (Kind          => Amount_Field,
                  Posting_Index => Clamped.Posting_Index - 1);
            end if;
      end case;
   end Previous_Field;

   ---------------------
   -- Add_Posting_Row --
   ---------------------

   function Add_Posting_Row
     (Current_Count : Positive) return Add_Row_Result
   is
   begin
      return
        (New_Count => Current_Count + 1,
         Focus     =>
           (Kind          => Account_Field,
            Posting_Index => Current_Count + 1));
   end Add_Posting_Row;

   -----------------------
   -- Drop_Last_Posting --
   -----------------------

   function Drop_Last_Posting
     (Focus         : Editor_Focus;
      Current_Count : Positive) return Drop_Row_Result
   is
      Clamped : constant Editor_Focus := Clamp_Focus (Focus, Current_Count);
   begin
      if Current_Count <= 2 then
         return
           (Status    => Minimum_Postings_Reached,
            New_Count => Current_Count,
            Focus     => Clamped);
      end if;

      if Clamped.Kind = Description_Field
        or else Clamped.Posting_Index /= Current_Count
      then
         return
           (Status    => Not_Tail_Posting,
            New_Count => Current_Count,
            Focus     => Clamped);
      end if;

      return
        (Status    => Applied,
         New_Count => Current_Count - 1,
         Focus     =>
           (Kind          => Account_Field,
            Posting_Index => Current_Count - 1));
   end Drop_Last_Posting;

   ------------------
   -- Apply_Intent --
   ------------------

   function Apply_Intent
     (Focus         : Editor_Focus;
      Posting_Count : Positive;
      Intent        : Interaction_Intent_Kind) return Interaction_Result
   is
   begin
      case Intent is
         when Next_Field_Intent =>
            return
              (Kind      => Navigation_Applied,
               New_Count => Posting_Count,
               Focus     => Next_Field (Focus, Posting_Count));

         when Previous_Field_Intent =>
            return
              (Kind      => Navigation_Applied,
               New_Count => Posting_Count,
               Focus     => Previous_Field (Focus, Posting_Count));

         when Add_Row_Intent =>
            if Posting_Count < Positive'Last then
               declare
                  Res : constant Add_Row_Result :=
                    Add_Posting_Row (Posting_Count);
               begin
                  return
                    (Kind      => Row_Added,
                     New_Count => Res.New_Count,
                     Focus     => Res.Focus);
               end;
            else
               return
                 (Kind      => Notice_Maximum_Postings,
                  New_Count => Posting_Count,
                  Focus     => Clamp_Focus (Focus, Posting_Count));
            end if;

         when Drop_Last_Intent =>
            declare
               Res : constant Drop_Row_Result :=
                 Drop_Last_Posting (Focus, Posting_Count);
            begin
               case Res.Status is
                  when Applied =>
                     return
                       (Kind      => Row_Dropped,
                        New_Count => Res.New_Count,
                        Focus     => Res.Focus);

                  when Minimum_Postings_Reached =>
                     return
                       (Kind      => Notice_Minimum_Postings,
                        New_Count => Posting_Count,
                        Focus     => Res.Focus);

                  when Not_Tail_Posting =>
                     return
                       (Kind      => Notice_Not_Tail_Posting,
                        New_Count => Posting_Count,
                        Focus     => Res.Focus);
               end case;
            end;
      end case;
   end Apply_Intent;

end HRA.Household_Actual_Record_Interaction;
