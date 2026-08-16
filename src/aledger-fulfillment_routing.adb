package body ALedger.Fulfillment_Routing is

   use type ALedger.Dates.Date;
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

   function Admit
     (Decisions   : Decision_Vectors.Vector;
      Known_Plans : ALedger.Plan.Plan_Id_Universe;
      Registry    : ALedger.Envelope.Envelope_Registry;
      History     : out Fulfillment_Routing_History;
      Status      : out Admission_Status) return Boolean
   is
      Result : Fulfillment_Routing_History := Empty_History;
   begin
      for Decision of Decisions loop
         if not ALedger.Plan.Contains (Known_Plans, Decision.Plan_ID) then
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

   function Resolve_Decision
     (History  : Fulfillment_Routing_History;
      Plan_ID  : ALedger.Plan.Plan_Id;
      Date     : ALedger.Dates.Date;
      Decision : out Fulfillment_Routing_Decision) return Boolean
   is
      Best_Index : Natural := 0;
   begin
      for I in 1 .. Natural (History.Decisions.Length) loop
         declare
            Candidate : constant Fulfillment_Routing_Decision :=
              History.Decisions.Element (I);
         begin
            if Candidate.Plan_ID = Plan_ID
              and then Candidate.Effective_From <= Date
              and then
                (Best_Index = 0
                 or else Candidate.Effective_From >
                   History.Decisions.Element (Best_Index).Effective_From)
            then
               Best_Index := I;
            end if;
         end;
      end loop;

      if Best_Index = 0 then
         return False;
      end if;

      Decision := History.Decisions.Element (Best_Index);
      return True;
   end Resolve_Decision;

   function Resolve_Decision
     (History  : Fulfillment_Routing_History;
      Plan_ID  : ALedger.Plan.Plan_Id;
      Date     : String;
      Decision : out Fulfillment_Routing_Decision) return Boolean
   is
      Value       : ALedger.Dates.Date;
      Date_Status : ALedger.Dates.Date_Status;
   begin
      if not ALedger.Dates.Parse (Date, Value, Date_Status) then
         raise Constraint_Error with "invalid fulfillment routing date: " & Date;
      end if;
      return Resolve_Decision (History, Plan_ID, Value, Decision);
   end Resolve_Decision;

   function Has_Routing_At
     (History : Fulfillment_Routing_History;
      Plan_ID : ALedger.Plan.Plan_Id;
      Date    : ALedger.Dates.Date) return Boolean
   is
      Decision : Fulfillment_Routing_Decision;
   begin
      return Resolve_Decision (History, Plan_ID, Date, Decision);
   end Has_Routing_At;

   function Has_Routing_At
     (History : Fulfillment_Routing_History;
      Plan_ID : ALedger.Plan.Plan_Id;
      Date    : String) return Boolean
   is
      Decision : Fulfillment_Routing_Decision;
   begin
      return Resolve_Decision (History, Plan_ID, Date, Decision);
   end Has_Routing_At;

   function Resolve
     (History : Fulfillment_Routing_History;
      Plan_ID : ALedger.Plan.Plan_Id;
      Date    : ALedger.Dates.Date) return Fulfillment_Route
   is
      Decision : Fulfillment_Routing_Decision;
   begin
      if Resolve_Decision (History, Plan_ID, Date, Decision) then
         return Decision.Route;
      else
         return Not_Target;
      end if;
   end Resolve;

   function Resolve
     (History : Fulfillment_Routing_History;
      Plan_ID : ALedger.Plan.Plan_Id;
      Date    : String) return Fulfillment_Route
   is
      Decision : Fulfillment_Routing_Decision;
   begin
      if Resolve_Decision (History, Plan_ID, Date, Decision) then
         return Decision.Route;
      else
         return Not_Target;
      end if;
   end Resolve;

   function Length (History : Fulfillment_Routing_History) return Natural is
   begin
      return Natural (History.Decisions.Length);
   end Length;

end ALedger.Fulfillment_Routing;
