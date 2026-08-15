with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

package body ALedger.Fulfillment_Routing is

   use type ALedger.Plan.Plan_Id;

   function Fulfills
     (Target : ALedger.Envelope.Envelope_Id) return Fulfillment_Route
   is
   begin
      return (Kind => Fulfills_Envelope, Target => Target);
   end Fulfills;

   function Not_Target return Fulfillment_Route is
   begin
      return (Kind => Not_Fulfillment_Target);
   end Not_Target;

   function Empty_History return Fulfillment_Routing_History is
   begin
      return (Decisions => Decision_Vectors.Empty_Vector);
   end Empty_History;

   function Is_Leap (Year : Positive) return Boolean is
     (Year mod 400 = 0 or else (Year mod 4 = 0 and then Year mod 100 /= 0));

   function Valid_Date (Text : String) return Boolean is
      Year, Month, Day, Max_Day : Natural;
   begin
      if Text'Length /= 10
        or else Text (Text'First + 4) /= '-'
        or else Text (Text'First + 7) /= '-'
      then
         return False;
      end if;

      for Offset in 0 .. 9 loop
         if Offset /= 4 and then Offset /= 7
           and then Text (Text'First + Offset) not in '0' .. '9'
         then
            return False;
         end if;
      end loop;

      Year  := Natural'Value (Text (Text'First .. Text'First + 3));
      Month := Natural'Value (Text (Text'First + 5 .. Text'First + 6));
      Day   := Natural'Value (Text (Text'First + 8 .. Text'First + 9));
      if Year = 0 or else Month not in 1 .. 12 then
         return False;
      end if;

      Max_Day :=
        (case Month is
            when 2 => (if Is_Leap (Year) then 29 else 28),
            when 4 | 6 | 9 | 11 => 30,
            when others => 31);
      return Day in 1 .. Max_Day;
   exception
      when Constraint_Error =>
         return False;
   end Valid_Date;

   function Contains_Plan
     (Known_Plans : ALedger.Plan.Plan_Id_Vectors.Vector;
      Plan_ID     : ALedger.Plan.Plan_Id) return Boolean
   is
   begin
      for Known of Known_Plans loop
         if Known = Plan_ID then
            return True;
         end if;
      end loop;
      return False;
   end Contains_Plan;

   function Admit
     (Decisions   : Decision_Vectors.Vector;
      Known_Plans : ALedger.Plan.Plan_Id_Vectors.Vector;
      Registry    : ALedger.Envelope.Envelope_Registry;
      History     : out Fulfillment_Routing_History;
      Status      : out Admission_Status) return Boolean
   is
      Result : Fulfillment_Routing_History := Empty_History;
   begin
      for Decision of Decisions loop
         if not Valid_Date (To_String (Decision.Effective_From)) then
            Status := Invalid_Effective_Date;
            return False;
         elsif not Contains_Plan (Known_Plans, Decision.Plan_ID) then
            Status := Unknown_Plan_Reference;
            return False;
         elsif Decision.Route.Kind = Fulfills_Envelope
           and then not ALedger.Envelope.Contains
             (Registry, ALedger.Envelope.Image (Decision.Route.Target))
         then
            Status := Unknown_Envelope_Reference;
            return False;
         end if;

         for Existing of Result.Decisions loop
            if Existing.Plan_ID = Decision.Plan_ID
              and then Existing.Effective_From = Decision.Effective_From
            then
               Status := Duplicate_Plan_Date_Coordinate;
               return False;
            end if;
         end loop;

         Result.Decisions.Append (Decision);
      end loop;

      History := Result;
      Status := Success;
      return True;
   end Admit;

   function Has_Routing_At
     (History : Fulfillment_Routing_History;
      Plan_ID : ALedger.Plan.Plan_Id;
      Date    : String) return Boolean
   is
   begin
      for Decision of History.Decisions loop
         if Decision.Plan_ID = Plan_ID
           and then To_String (Decision.Effective_From) <= Date
         then
            return True;
         end if;
      end loop;
      return False;
   end Has_Routing_At;

   function Resolve
     (History : Fulfillment_Routing_History;
      Plan_ID : ALedger.Plan.Plan_Id;
      Date    : String) return Fulfillment_Route
   is
      Best_Index : Natural := 0;
   begin
      for I in 1 .. Natural (History.Decisions.Length) loop
         declare
            Decision : constant Fulfillment_Routing_Decision :=
              History.Decisions.Element (I);
         begin
            if Decision.Plan_ID = Plan_ID
              and then To_String (Decision.Effective_From) <= Date
              and then
                (Best_Index = 0
                 or else To_String (Decision.Effective_From) >
                   To_String
                     (History.Decisions.Element (Best_Index).Effective_From))
            then
               Best_Index := I;
            end if;
         end;
      end loop;

      if Best_Index = 0 then
         return Not_Target;
      else
         return History.Decisions.Element (Best_Index).Route;
      end if;
   end Resolve;

   function Length (History : Fulfillment_Routing_History) return Natural is
   begin
      return Natural (History.Decisions.Length);
   end Length;

end ALedger.Fulfillment_Routing;
