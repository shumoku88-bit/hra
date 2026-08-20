package body HRA.Envelope_Entitlement is

   use type HRA.Dates.Date;

   function Empty_Observation return Entitlement_Observation is
   begin
      return
        (Per_Envelope => Envelope_Balance_Maps.Empty_Map,
         Unallocated  => Empty_Balance,
         Origins      => Commodity_Date_Maps.Empty_Map);
   end Empty_Observation;

   function Add_To_Map
     (Map : Envelope_Balance_Maps.Map;
      Key : Envelope.Envelope_Id;
      Val : Balance) return Envelope_Balance_Maps.Map
   is
      Result : Envelope_Balance_Maps.Map := Map;
   begin
      if Result.Contains (Key) then
         Result.Replace (Key, Add_Balance (Result.Element (Key), Val));
      else
         Result.Insert (Key, Val);
      end if;
      return Result;
   end Add_To_Map;

   function Fold_Movement
     (Obs      : Entitlement_Observation;
      Movement : Entitlement_Movement) return Entitlement_Observation
   is
      Result : Entitlement_Observation := Obs;
      Neg    : constant Balance :=
        Negate_Balance (Singleton_Balance (Movement.Amt));
      Pos    : constant Balance := Singleton_Balance (Movement.Amt);
   begin
      case Movement.Kind is
         when Grant_From_Unallocated =>
            Result.Per_Envelope :=
              Add_To_Map (Result.Per_Envelope, Movement.Target, Pos);
            Result.Unallocated := Subtract_Balance (Result.Unallocated, Pos);

         when Transfer_Between_Envelopes =>
            Result.Per_Envelope :=
              Add_To_Map
                (Result.Per_Envelope, Movement.From_Envelope, Neg);
            Result.Per_Envelope :=
              Add_To_Map
                (Result.Per_Envelope, Movement.To_Envelope, Pos);

         when Return_To_Unallocated =>
            Result.Per_Envelope :=
              Add_To_Map (Result.Per_Envelope, Movement.Source, Neg);
            Result.Unallocated := Add_Balance (Result.Unallocated, Pos);
      end case;

      return Result;
   end Fold_Movement;

   function Record_Origin
     (Obs      : Entitlement_Observation;
      Comm     : Commodity;
      Tx_Date  : HRA.Dates.Date) return Entitlement_Observation
   is
      Result : Entitlement_Observation := Obs;
   begin
      if not Result.Origins.Contains (Comm) then
         Result.Origins.Insert (Comm, Tx_Date);
      elsif Tx_Date < Result.Origins.Element (Comm) then
         Result.Origins.Replace (Comm, Tx_Date);
      end if;
      return Result;
   end Record_Origin;

   function Has_Origin
     (Obs  : Entitlement_Observation;
      Comm : Commodity) return Boolean
   is
   begin
      return Obs.Origins.Contains (Comm);
   end Has_Origin;

   function Origin_For
     (Obs  : Entitlement_Observation;
      Comm : Commodity) return HRA.Dates.Date
   is
   begin
      return Obs.Origins.Element (Comm);
   end Origin_For;

   function Entitlement_For
     (Obs : Entitlement_Observation;
      Env : Envelope.Envelope_Id) return Balance
   is
   begin
      if Obs.Per_Envelope.Contains (Env) then
         return Obs.Per_Envelope.Element (Env);
      else
         return Empty_Balance;
      end if;
   end Entitlement_For;

   function Unallocated_Balance
     (Obs : Entitlement_Observation) return Balance
   is
   begin
      return Obs.Unallocated;
   end Unallocated_Balance;

   procedure For_Each_Envelope
     (Obs     : Entitlement_Observation;
      Process : not null access procedure
       (Env_Id : Envelope.Envelope_Id;
        Bal    : Balance))
   is
      Cursor : Envelope_Balance_Maps.Cursor := Obs.Per_Envelope.First;
   begin
      while Envelope_Balance_Maps.Has_Element (Cursor) loop
         Process
           (Envelope_Balance_Maps.Key (Cursor),
            Envelope_Balance_Maps.Element (Cursor));
         Envelope_Balance_Maps.Next (Cursor);
      end loop;
   end For_Each_Envelope;

   function "=" (Left, Right : Entitlement_Movement) return Boolean is
   begin
      if Left.Kind /= Right.Kind
        or else Left.Tx_Date /= Right.Tx_Date
        or else Left.Amt.Val /= Right.Amt.Val
        or else not (Left.Amt.Comm = Right.Amt.Comm)
      then
         return False;
      end if;

      case Left.Kind is
         when Grant_From_Unallocated =>
            return Left.Target = Right.Target;
         when Transfer_Between_Envelopes =>
            return Left.From_Envelope = Right.From_Envelope
              and then Left.To_Envelope = Right.To_Envelope;
         when Return_To_Unallocated =>
            return Left.Source = Right.Source;
      end case;
   end "=";

end HRA.Envelope_Entitlement;
