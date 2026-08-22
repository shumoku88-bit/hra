--  Pure UI-neutral interaction semantics for Household Actual draft editing.
--  Maps user navigation and row editing intents to pure coordinate transitions over:
--    Focus         : mutable focus location (Description, Account, or Amount field)
--    Posting_Count : number of posting rows (invariant: >= 2)
package HRA.Household_Actual_Record_Interaction
  with Pure, SPARK_Mode => On
is

   --  ========================================================================
   --  Focus Coordinates
   --  ========================================================================

   type Focus_Kind is
     (Description_Field,
      Account_Field,
      Amount_Field);

   type Editor_Focus is record
      Kind          : Focus_Kind := Description_Field;
      Posting_Index : Positive   := 1;
   end record;

   --  Default initial focus for a newly started draft.
   function Initial_Focus return Editor_Focus is
     ((Kind => Description_Field, Posting_Index => 1));

   --  Ensure focus is within valid range for the given posting count.
   function Clamp_Focus
     (Focus         : Editor_Focus;
      Posting_Count : Positive) return Editor_Focus
   is
     ((Kind          => Focus.Kind,
       Posting_Index =>
         (if Focus.Kind = Description_Field then 1
          else Positive'Min (Focus.Posting_Index, Posting_Count))));

   --  ========================================================================
   --  Navigation Cycles
   --  ========================================================================

   --  Cycle forward:
   --  Description -> P1 Account -> P1 Amount -> ... -> PN Account -> PN Amount -> Description
   function Next_Field
     (Focus         : Editor_Focus;
      Posting_Count : Positive) return Editor_Focus;

   --  Cycle backward:
   --  Description -> PN Amount -> PN Account -> ... -> P1 Amount -> P1 Account -> Description
   function Previous_Field
     (Focus         : Editor_Focus;
      Posting_Count : Positive) return Editor_Focus;

   --  ========================================================================
   --  Row Operations
   --  ========================================================================

   type Add_Row_Result is record
      New_Count : Positive;
      Focus     : Editor_Focus;
   end record;

   --  Appends a new posting row at the end and moves focus to its Account field.
   function Add_Posting_Row
     (Current_Count : Positive) return Add_Row_Result
     with Pre => Current_Count < Positive'Last,
          Post =>
            Add_Posting_Row'Result.New_Count = Current_Count + 1
            and then Add_Posting_Row'Result.Focus.Kind = Account_Field
            and then Add_Posting_Row'Result.Focus.Posting_Index = Current_Count + 1;

   type Drop_Status is
     (Applied,
      Minimum_Postings_Reached,
      Not_Tail_Posting);

   type Drop_Row_Result is record
      Status    : Drop_Status;
      New_Count : Positive;
      Focus     : Editor_Focus;
   end record;

   --  Drops the tail posting row.
   --  Fails with Minimum_Postings_Reached if Current_Count <= 2.
   --  Fails with Not_Tail_Posting if Focus is not on the last posting row (Index /= Current_Count or Kind = Description_Field).
   --  On success, New_Count = Current_Count - 1 and focus moves to Account_Field of row Current_Count - 1.
   function Drop_Last_Posting
     (Focus         : Editor_Focus;
      Current_Count : Positive) return Drop_Row_Result;

   --  ========================================================================
   --  High-Level Interaction Intents
   --  ========================================================================

   type Interaction_Intent_Kind is
     (Next_Field_Intent,
      Previous_Field_Intent,
      Add_Row_Intent,
      Drop_Last_Intent);

   type Interaction_Result_Kind is
     (Navigation_Applied,
      Row_Added,
      Row_Dropped,
      Notice_Minimum_Postings,
      Notice_Maximum_Postings,
      Notice_Not_Tail_Posting);

   type Interaction_Result is record
      Kind      : Interaction_Result_Kind;
      New_Count : Positive;
      Focus     : Editor_Focus;
   end record;

   function Apply_Intent
     (Focus         : Editor_Focus;
      Posting_Count : Positive;
      Intent        : Interaction_Intent_Kind) return Interaction_Result;

end HRA.Household_Actual_Record_Interaction;
