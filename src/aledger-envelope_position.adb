with Ada.Containers.Vectors;
with ALedger.Proof_Core;
with ALedger.Proof_Money_Bridge;

package body ALedger.Envelope_Position is

   use type ALedger.Money.Quantity;
   use type ALedger.Proof_Core.Atomic_Quanta;

   package Commodity_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => ALedger.Money.Commodity,
      "="          => ALedger.Money."=");

   function "=" (Left, Right : Position) return Boolean is
   begin
      return Left.Env_Id = Right.Env_Id
        and then Is_Zero_Balance
          (Subtract_Balance (Left.Remaining, Right.Remaining))
        and then Is_Zero_Balance
          (Subtract_Balance (Left.Headroom, Right.Headroom));
   end "=";

   function Empty_Observation return Observation is
   begin
      return (Positions => Position_Maps.Empty_Map);
   end Empty_Observation;

   procedure Set_Diagnostic
     (Diag             : out Observe_Diagnostic;
      Status           : Observe_Status;
      Env_Text         : String;
      Commodity_Code   : String;
      Role             : Value_Role)
   is
   begin
      Diag :=
        (Status           => Status,
         Envelope_Id_Text => To_Unbounded_String (Env_Text),
         Commodity_Code   => To_Unbounded_String (Commodity_Code),
         Role             => Role);
   end Set_Diagnostic;

   function Status_For
     (Status : ALedger.Proof_Money_Bridge.Bridge_Status;
      Output : Boolean) return Observe_Status
   is
   begin
      case Status is
         when ALedger.Proof_Money_Bridge.Success =>
            return Success;
         when ALedger.Proof_Money_Bridge.Out_Of_Proof_Input_Range =>
            return Proof_Input_Out_Of_Range;
         when ALedger.Proof_Money_Bridge.Out_Of_Money_Output_Range =>
            return Proof_Output_Out_Of_Range;
         when ALedger.Proof_Money_Bridge.Non_Exact_Conversion =>
            return Non_Exact_Proof_Conversion;
      end case;
   end Status_For;

   procedure Include_Balance
     (Coordinates : in out Commodity_Vectors.Vector;
      Value       : Balance)
   is
      Arr : constant Balance_Entry_Array := Entries (Value);
   begin
      for E of Arr loop
         if not Coordinates.Contains (E.Comm) then
            Coordinates.Append (E.Comm);
         end if;
      end loop;
   end Include_Balance;

   function Evaluate_One
     (Env             : ALedger.Envelope.Envelope_Id;
      Entitlement     : Balance;
      Net_Consumption : Balance;
      Net_Fulfillment : Balance;
      Plan_Commitment : Balance;
      Result          : out Position;
      Diag            : out Observe_Diagnostic) return Boolean
   is
      Coordinates : Commodity_Vectors.Vector;
      Env_Text    : constant String := ALedger.Envelope.Image (Env);

      function Admit_Input
        (Value     : Balance;
         Commodity : ALedger.Money.Commodity;
         Role      : Value_Role;
         Quanta    : out ALedger.Proof_Core.Atomic_Quanta) return Boolean
      is
         Bridge_Status : ALedger.Proof_Money_Bridge.Bridge_Status;
      begin
         if ALedger.Proof_Money_Bridge.Balance_To_Atomic_Quanta
           (Value, Commodity, Quanta, Bridge_Status)
         then
            return True;
         end if;

         Set_Diagnostic
           (Diag,
            Status_For (Bridge_Status, False),
            Env_Text,
            ALedger.Money.Code (Commodity),
            Role);
         return False;
      end Admit_Input;

      function Append_Output
        (Target    : in out Balance;
         Commodity : ALedger.Money.Commodity;
         Value     : Long_Long_Integer;
         Role      : Value_Role) return Boolean
      is
         Bridge_Status : ALedger.Proof_Money_Bridge.Bridge_Status;
         Singleton     : Balance;
      begin
         if not ALedger.Proof_Money_Bridge.To_Singleton_Balance
           (Commodity, Value, Singleton, Bridge_Status)
         then
            Set_Diagnostic
              (Diag,
               Status_For (Bridge_Status, True),
               Env_Text,
               ALedger.Money.Code (Commodity),
               Role);
            return False;
         end if;

         Target := Add_Balance (Target, Singleton);
         return True;
      end Append_Output;

   begin
      Result :=
        (Env_Id    => Env,
         Remaining => Empty_Balance,
         Headroom  => Empty_Balance);
      Diag :=
        (Status           => Success,
         Envelope_Id_Text => Null_Unbounded_String,
         Commodity_Code   => Null_Unbounded_String,
         Role             => Entitlement_Value);

      --  Build the coordinate union from each input independently. Never add
      --  the inputs first: cancellation must not erase a Commodity coordinate
      --  before proof evaluation.
      Include_Balance (Coordinates, Entitlement);
      Include_Balance (Coordinates, Net_Consumption);
      Include_Balance (Coordinates, Net_Fulfillment);
      Include_Balance (Coordinates, Plan_Commitment);

      for Commodity of Coordinates loop
         declare
            Ent_Q   : ALedger.Proof_Core.Atomic_Quanta;
            Cons_Q  : ALedger.Proof_Core.Atomic_Quanta;
            Ful_Q   : ALedger.Proof_Core.Atomic_Quanta;
            Plan_Q  : ALedger.Proof_Core.Atomic_Quanta;
         begin
            if not Admit_Input
              (Entitlement, Commodity, Entitlement_Value, Ent_Q)
              or else not Admit_Input
                (Net_Consumption, Commodity, Net_Consumption_Value, Cons_Q)
              or else not Admit_Input
                (Net_Fulfillment, Commodity, Net_Fulfillment_Value, Ful_Q)
              or else not Admit_Input
                (Plan_Commitment, Commodity, Plan_Commitment_Value, Plan_Q)
            then
               return False;
            end if;

            if Plan_Q < 0 then
               Set_Diagnostic
                 (Diag,
                  Negative_Plan_Commitment,
                  Env_Text,
                  ALedger.Money.Code (Commodity),
                  Plan_Commitment_Value);
               return False;
            end if;

            declare
               Proof_Result : constant ALedger.Proof_Core.Envelope_Result :=
                 ALedger.Proof_Core.Evaluate_Envelope
                   ((Entitlement     => Ent_Q,
                     Net_Consumption => Cons_Q,
                     Net_Fulfillment => Ful_Q,
                     Plan_Commitment => Plan_Q));
            begin
               if not Append_Output
                 (Result.Remaining,
                  Commodity,
                  Long_Long_Integer (Proof_Result.Remaining),
                  Remaining_Result)
                 or else not Append_Output
                   (Result.Headroom,
                    Commodity,
                    Long_Long_Integer (Proof_Result.Post_Plan_Headroom),
                    Headroom_Result)
               then
                  return False;
               end if;
            end;
         end;
      end loop;

      return True;
   end Evaluate_One;

   function Add_Current_Position
     (Output          : in out Observation;
      Registry        : ALedger.Envelope.Envelope_Registry;
      Env_Text        : String;
      Entitlement     : Balance;
      Net_Consumption : Balance;
      Net_Fulfillment : Balance;
      Plan_Commitment : Balance;
      Diag            : out Observe_Diagnostic) return Boolean
   is
      Env : ALedger.Envelope.Envelope_Id;
      Pos : Position;
   begin
      if not ALedger.Envelope.Lookup (Registry, Env_Text, Env) then
         Set_Diagnostic
           (Diag,
            Unknown_Current_Envelope,
            Env_Text,
            "",
            Entitlement_Value);
         return False;
      end if;

      if Output.Positions.Contains (Env_Text) then
         Set_Diagnostic
           (Diag,
            Duplicate_Current_Envelope,
            Env_Text,
            "",
            Entitlement_Value);
         return False;
      end if;

      if not Evaluate_One
        (Env,
         Entitlement,
         Net_Consumption,
         Net_Fulfillment,
         Plan_Commitment,
         Pos,
         Diag)
      then
         return False;
      end if;

      Output.Positions.Insert (Env_Text, Pos);
      return True;
   end Add_Current_Position;

   function Observe_Base
     (Policy      : ALedger.Budget_Config.Budget_Policy;
      Registry    : ALedger.Envelope.Envelope_Registry;
      Entitlement : ALedger.Envelope_Entitlement.Entitlement_Observation;
      Consumption : ALedger.Envelope_Consumption.Envelope_Consumption;
      Result      : out Observation;
      Diag        : out Observe_Diagnostic) return Boolean
   is
      Output : Observation := Empty_Observation;
   begin
      for Def of Policy.Envelopes loop
         declare
            Env_Text : constant String := To_String (Def.ID);
            Env      : ALedger.Envelope.Envelope_Id;
         begin
            if not ALedger.Envelope.Lookup (Registry, Env_Text, Env) then
               Set_Diagnostic
                 (Diag,
                  Unknown_Current_Envelope,
                  Env_Text,
                  "",
                  Entitlement_Value);
               Result := Output;
               return False;
            end if;

            if not Add_Current_Position
              (Output,
               Registry,
               Env_Text,
               ALedger.Envelope_Entitlement.Entitlement_For
                 (Entitlement, Env),
               ALedger.Envelope_Consumption.Net_For (Consumption, Env),
               Empty_Balance,
               Empty_Balance,
               Diag)
            then
               Result := Output;
               return False;
            end if;
         end;
      end loop;

      Result := Output;
      Diag :=
        (Status           => Success,
         Envelope_Id_Text => Null_Unbounded_String,
         Commodity_Code   => Null_Unbounded_String,
         Role             => Entitlement_Value);
      return True;
   end Observe_Base;

   function Observe
     (Policy      : ALedger.Budget_Config.Budget_Policy;
      Registry    : ALedger.Envelope.Envelope_Registry;
      Entitlement : ALedger.Envelope_Entitlement.Entitlement_Observation;
      Consumption : ALedger.Envelope_Consumption.Envelope_Consumption;
      Fulfillment : ALedger.Envelope_Fulfillment.Envelope_Fulfillment;
      Commitment  : ALedger.Envelope_Commitment.Commitment_Observation;
      Result      : out Observation;
      Diag        : out Observe_Diagnostic) return Boolean
   is
      Output : Observation := Empty_Observation;
   begin
      for Def of Policy.Envelopes loop
         declare
            Env_Text : constant String := To_String (Def.ID);
            Env      : ALedger.Envelope.Envelope_Id;
         begin
            if not ALedger.Envelope.Lookup (Registry, Env_Text, Env) then
               Set_Diagnostic
                 (Diag,
                  Unknown_Current_Envelope,
                  Env_Text,
                  "",
                  Entitlement_Value);
               Result := Output;
               return False;
            end if;

            if not Add_Current_Position
              (Output,
               Registry,
               Env_Text,
               ALedger.Envelope_Entitlement.Entitlement_For
                 (Entitlement, Env),
               ALedger.Envelope_Consumption.Net_For (Consumption, Env),
               ALedger.Envelope_Fulfillment.Net_For (Fulfillment, Env),
               ALedger.Envelope_Commitment.Commitment_For (Commitment, Env),
               Diag)
            then
               Result := Output;
               return False;
            end if;
         end;
      end loop;

      Result := Output;
      Diag :=
        (Status           => Success,
         Envelope_Id_Text => Null_Unbounded_String,
         Commodity_Code   => Null_Unbounded_String,
         Role             => Entitlement_Value);
      return True;
   end Observe;

   function Has_Position
     (Obs : Observation;
      Env : ALedger.Envelope.Envelope_Id) return Boolean
   is
   begin
      return Obs.Positions.Contains (ALedger.Envelope.Image (Env));
   end Has_Position;

   function Position_For
     (Obs : Observation;
      Env : ALedger.Envelope.Envelope_Id) return Position
   is
   begin
      return Obs.Positions.Element (ALedger.Envelope.Image (Env));
   end Position_For;

end ALedger.Envelope_Position;
