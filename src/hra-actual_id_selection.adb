with Ada.Strings; use Ada.Strings;
with Ada.Strings.Fixed;

package body HRA.Actual_Id_Selection is

   Prefix : constant String := "hra-actual-";

   type Used_Array is array (Positive range <>) of Boolean;

   procedure Mark_Generated_Identity
     (Text : String;
      Used : in out Used_Array)
   is
      Prefix_Last  : Integer;
      Suffix_First : Integer;
      Number       : Natural := 0;
      Limit        : constant Natural := Natural (Used'Last);
   begin
      if Text'Length <= Prefix'Length then
         return;
      end if;

      Prefix_Last := Text'First + Prefix'Length - 1;
      if Text (Text'First .. Prefix_Last) /= Prefix then
         return;
      end if;

      Suffix_First := Prefix_Last + 1;
      if Text (Suffix_First) = '0' then
         --  The selector emits canonical positive decimal images without
         --  leading zeroes. A differently-spelled external identity therefore
         --  does not occupy that generated identity.
         return;
      end if;

      for Position in Suffix_First .. Text'Last loop
         if Text (Position) not in '0' .. '9' then
            return;
         end if;

         declare
            Digit : constant Natural :=
              Character'Pos (Text (Position)) - Character'Pos ('0');
         begin
            --  Values outside the finite candidate window cannot collide with
            --  any identity this invocation may select. Detect the overflow
            --  before performing the decimal accumulation.
            if Number > Limit / 10
              or else
                (Number = Limit / 10 and then Digit > Limit mod 10)
            then
               return;
            end if;
            Number := Number * 10 + Digit;
         end;
      end loop;

      if Number in Natural (Used'First) .. Natural (Used'Last) then
         Used (Positive (Number)) := True;
      end if;
   end Mark_Generated_Identity;

   function Select_Next
     (Observation : HRA.Actual_Admission.Actual_Observation;
      ID          : out HRA.Actual_Admission.Actual_Id;
      Status      : out Selection_Status) return Boolean
   is
      Count : constant Natural :=
        HRA.Actual_Admission.Transaction_Count (Observation);
   begin
      if Count = Natural'Last then
         Status := Identity_Space_Exhausted;
         return False;
      end if;

      --  With N admitted transactions there are at most N occupied effective
      --  identities, so among canonical candidates 1 .. N+1 at least one is
      --  necessarily free. This bounds selection to one linear observation of
      --  current authority without introducing a second persistent counter.
      declare
         Used : Used_Array (1 .. Positive (Count + 1)) := (others => False);
      begin
         for Index in 1 .. Count loop
            declare
               Actual_Item : constant HRA.Actual_Admission.Actual_Transaction_Entry :=
                 HRA.Actual_Admission.Transaction_At (Observation, Index);
            begin
               if Actual_Item.Identity.Present then
                  Mark_Generated_Identity
                    (HRA.Actual_Admission.Text (Actual_Item.Identity.Value), Used);
               end if;
            end;
         end loop;

         for Number in Used'Range loop
            if not Used (Number) then
               declare
                  Candidate_Status : HRA.Actual_Admission.Actual_Id_Status;
                  Candidate_Text   : constant String :=
                    Prefix & Ada.Strings.Fixed.Trim
                      (Positive'Image (Number), Both);
               begin
                  if not HRA.Actual_Admission.Create_Actual_Id
                    (Candidate_Text, ID, Candidate_Status)
                  then
                     Status := Generated_Identity_Invalid;
                     return False;
                  end if;

                  Status := Success;
                  return True;
               end;
            end if;
         end loop;
      end;

      --  Unreachable for a valid admitted observation by the N / N+1 law, but
      --  retain an explicit fail-closed result rather than relying on it as an
      --  unchecked assumption.
      Status := Identity_Space_Exhausted;
      return False;
   end Select_Next;

end HRA.Actual_Id_Selection;
