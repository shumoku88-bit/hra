with Ada.Characters.Handling; use Ada.Characters.Handling;

package body HRA.Issue_Relation is

   use type HRA.Issues.Issue_Id;

   function Create_Relation_Event_Id
     (Value  : String;
      ID     : out Relation_Event_Id;
      Status : out Relation_Event_Id_Status) return Boolean
   is
   begin
      if Value'Length = 0 then
         Status := Empty_Relation_Event_Id;
         return False;
      end if;

      for C of Value loop
         if Is_Space (C) then
            Status := Relation_Event_Id_Contains_Whitespace;
            return False;
         elsif Character'Pos (C) < 32 or else Character'Pos (C) = 127 then
            Status := Relation_Event_Id_Contains_Control_Character;
            return False;
         end if;
      end loop;

      ID := (ID_Text => To_Unbounded_String (Value));
      Status := Success;
      return True;
   end Create_Relation_Event_Id;

   function Text (ID : Relation_Event_Id) return String is
     (To_String (ID.ID_Text));

   function "=" (Left, Right : Relation_Event_Id) return Boolean is
     (Left.ID_Text = Right.ID_Text);

   function Create_Realized_As
     (Event_ID    : Relation_Event_Id;
      Recorded_On : HRA.Dates.Date;
      Issue_ID    : HRA.Issues.Issue_Id;
      Actual_ID   : HRA.Actual_Admission.Actual_Id;
      Details     : String;
      Event       : out Relation_Event;
      Status      : out Create_Status) return Boolean
   is
   begin
      if Details'Length > 0
        and then (Is_Space (Details (Details'First))
                  or else Is_Space (Details (Details'Last)))
      then
         Status := Details_Have_Surrounding_Whitespace;
         return False;
      end if;

      for C of Details loop
         if Character'Pos (C) < 32 or else Character'Pos (C) = 127 then
            Status := Details_Contain_Control_Character;
            return False;
         end if;
      end loop;

      Event :=
        (Event_Identity => Event_ID,
         Event_Date     => Recorded_On,
         Source_Issue   => Issue_ID,
         Meaning        => Realized_As,
         Target_Actual  => Actual_ID,
         Event_Details  => To_Unbounded_String (Details));
      Status := Create_Success;
      return True;
   end Create_Realized_As;

   function Kind (Event : Relation_Event) return Relation_Kind is
     (Event.Meaning);

   function Event_Id (Event : Relation_Event) return Relation_Event_Id is
     (Event.Event_Identity);

   function Recorded_On (Event : Relation_Event) return HRA.Dates.Date is
     (Event.Event_Date);

   function Issue_Id (Event : Relation_Event) return HRA.Issues.Issue_Id is
     (Event.Source_Issue);

   function Actual_Id
     (Event : Relation_Event) return HRA.Actual_Admission.Actual_Id is
     (Event.Target_Actual);

   function Details (Event : Relation_Event) return String is
     (To_String (Event.Event_Details));

   function Admit_References
     (Event   : Relation_Event;
      Issues  : HRA.Issues.Issues_Inventory;
      Actuals : HRA.Actual_Admission.Actual_Observation;
      Diag    : out Reference_Diagnostic) return Boolean
   is
      Issue_Found : Boolean := False;
   begin
      Diag :=
        (Status  => Reference_Success,
         Message => Null_Unbounded_String);

      for I in 1 .. HRA.Issues.Count (Issues) loop
         if HRA.Issues.Element (Issues, I).ID = Event.Source_Issue then
            Issue_Found := True;
            exit;
         end if;
      end loop;

      if not Issue_Found then
         Diag :=
           (Status  => Unknown_Issue,
            Message => To_Unbounded_String
              ("Issue relation references an unknown Issue: " &
               HRA.Issues.Text (Event.Source_Issue)));
         return False;
      end if;

      if not HRA.Actual_Admission.Has_Source_Durable_Identity
        (Actuals, Event.Target_Actual)
      then
         Diag :=
           (Status  => Unknown_Source_Durable_Actual,
            Message => To_Unbounded_String
              ("Issue relation references an Actual without source-durable event-id: " &
               HRA.Actual_Admission.Text (Event.Target_Actual)));
         return False;
      end if;

      return True;
   end Admit_References;

end HRA.Issue_Relation;
