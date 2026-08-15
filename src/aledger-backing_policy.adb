with ALedger.Account;

package body ALedger.Backing_Policy is

   function Positive_Balance (B : Balance) return Balance is
      Result : Balance := Empty_Balance;
      Arr    : constant Balance_Entry_Array := Entries (B);
   begin
      for E of Arr loop
         if E.Val > Zero_Quantity then
            Result := Add_Balance
              (Result, Singleton_Balance (Make_Amount (E.Comm, E.Val)));
         end if;
      end loop;
      return Result;
   end Positive_Balance;

   function Available_Funding (Pos : Backing_Pool_Position) return Balance is
   begin
      return Subtract_Balance (Pos.Funding_Balance, Pos.Funding_Commitment);
   end Available_Funding;

   function Gross_Surplus (Pos : Backing_Pool_Position) return Balance is
   begin
      return Subtract_Balance
        (Pos.Funding_Balance, Pos.Gross_Envelope_Required);
   end Gross_Surplus;

   function Available_Surplus (Pos : Backing_Pool_Position) return Balance is
   begin
      return Subtract_Balance
        (Available_Funding (Pos), Pos.Available_Envelope_Required);
   end Available_Surplus;

   function Admit_Backing_Policy
     (Config   : Budget_Config.Budget_Policy;
      Registry : Envelope.Envelope_Registry;
      Policy   : out Backing_Policy;
      Status   : out Policy_Status) return Boolean
   is
      P : Backing_Policy;
   begin
      for Pool_Def of Config.Backing_Pools loop
         declare
            Pool_Name : constant String := To_String (Pool_Def.ID);
         begin
            if P.Assets_By_Pool.Contains (Pool_Name) then
               Status := Duplicate_Pool_Definition;
               return False;
            end if;

            if Pool_Def.Asset_Accounts.Is_Empty then
               Status := Empty_Pool_Assets;
               return False;
            end if;

            P.Pool_Ids.Append (Pool_Name);
            P.Assets_By_Pool.Insert (Pool_Name, Pool_Def.Asset_Accounts);
            P.Envelopes_By_Pool.Insert
              (Pool_Name, Config_Support.String_Vectors.Empty_Vector);

            for Acc_Name of Pool_Def.Asset_Accounts loop
               if P.Pool_By_Asset.Contains (Acc_Name) then
                  Status := Duplicate_Asset_Membership;
                  return False;
               end if;
               P.Pool_By_Asset.Insert (Acc_Name, Pool_Name);
            end loop;
         end;
      end loop;

      for Env_Def of Config.Envelopes loop
         declare
            Env_Name  : constant String := To_String (Env_Def.ID);
            Pool_Name : constant String := To_String (Env_Def.Backing_Pool);
         begin
            if not P.Assets_By_Pool.Contains (Pool_Name) then
               Status := Unknown_Pool_Reference;
               return False;
            end if;

            if not Envelope.Contains (Registry, Env_Name) then
               Status := Unknown_Pool_Reference;
               return False;
            end if;

            if P.Pool_By_Envelope.Contains (Env_Name) then
               Status := Duplicate_Envelope_Assignment;
               return False;
            end if;

            P.Pool_By_Envelope.Insert (Env_Name, Pool_Name);
            declare
               Vec : Config_Support.String_Vectors.Vector :=
                 P.Envelopes_By_Pool.Element (Pool_Name);
            begin
               Vec.Append (Env_Name);
               P.Envelopes_By_Pool.Replace (Pool_Name, Vec);
            end;
         end;
      end loop;

      Policy := P;
      Status := Success;
      return True;
   end Admit_Backing_Policy;

   function Observe_Backing
     (Policy      : Backing_Policy;
      L           : Ledger.Ledger;
      Entitlement : Envelope_Entitlement.Entitlement_Observation;
      Consumption : Envelope_Consumption.Envelope_Consumption;
      Commitment  : Envelope_Commitment.Commitment_Observation)
      return Backing_Observation
   is
      Result : Backing_Observation;
   begin
      Result.Total_Assets := Empty_Balance;

      for Pool_Name of Policy.Pool_Ids loop
         declare
            Assets : constant Config_Support.String_Vectors.Vector :=
              Policy.Assets_By_Pool.Element (Pool_Name);
            Envs : constant Config_Support.String_Vectors.Vector :=
              Policy.Envelopes_By_Pool.Element (Pool_Name);

            Funding_Bal : Balance := Empty_Balance;
            Gross_Req   : Balance := Empty_Balance;
            Avail_Req   : Balance := Empty_Balance;
            Claims_List : Claim_Vectors.Vector;
         begin
            for Acc_Str of Assets loop
               declare
                  Acc_Obj : constant Account.Account :=
                    Account.Make_Account (Acc_Str);
                  Bal : constant Balance :=
                    Ledger.Compute_Account_Balance (L, Acc_Obj);
               begin
                  Funding_Bal := Add_Balance (Funding_Bal, Bal);
               end;
            end loop;
            Result.Total_Assets := Add_Balance
              (Result.Total_Assets, Funding_Bal);

            for Env_Str of Envs loop
               declare
                  Env_Id : constant Envelope.Envelope_Id :=
                    Envelope.Make_Envelope_Id (Env_Str);
                  Ent_Bal : constant Balance :=
                    Envelope_Entitlement.Entitlement_For
                      (Entitlement, Env_Id);
                  Net_Cons : constant Balance :=
                    Envelope_Consumption.Net_For (Consumption, Env_Id);
                  Remaining_Bal : constant Balance :=
                    Subtract_Balance (Ent_Bal, Net_Cons);
                  Plan_Reserve : constant Balance :=
                    Envelope_Commitment.Commitment_For
                      (Commitment, Env_Id);
                  Headroom : constant Balance :=
                    Subtract_Balance (Remaining_Bal, Plan_Reserve);
                  Claim : constant Backed_Envelope_Claim :=
                    (Env_Id    => Env_Id,
                     Remaining => Remaining_Bal,
                     Headroom  => Headroom);
               begin
                  Claims_List.Append (Claim);
                  Gross_Req := Add_Balance
                    (Gross_Req, Positive_Balance (Remaining_Bal));
                  Avail_Req := Add_Balance
                    (Avail_Req, Positive_Balance (Headroom));
               end;
            end loop;

            declare
               Pos : constant Backing_Pool_Position :=
                 (Pool_Id                     => To_Unbounded_String (Pool_Name),
                  Claims                      => Claims_List,
                  Funding_Balance             => Funding_Bal,
                  Funding_Commitment          => Empty_Balance,
                  Gross_Envelope_Required     => Gross_Req,
                  Available_Envelope_Required => Avail_Req);
            begin
               Result.Positions.Insert (Pool_Name, Pos);
            end;
         end;
      end loop;

      return Result;
   end Observe_Backing;

   function Position_For
     (Obs     : Backing_Observation;
      Pool_Id : String) return Backing_Pool_Position
   is
   begin
      if Obs.Positions.Contains (Pool_Id) then
         return Obs.Positions.Element (Pool_Id);
      else
         return
           (Pool_Id                     => To_Unbounded_String (Pool_Id),
            Claims                      => Claim_Vectors.Empty_Vector,
            Funding_Balance             => Empty_Balance,
            Funding_Commitment          => Empty_Balance,
            Gross_Envelope_Required     => Empty_Balance,
            Available_Envelope_Required => Empty_Balance);
      end if;
   end Position_For;

   function Claim_For
     (Obs : Backing_Observation;
      Env : Envelope.Envelope_Id) return Backed_Envelope_Claim
   is
   begin
      for Position_Cursor in Obs.Positions.Iterate loop
         declare
            Pos : constant Backing_Pool_Position :=
              Pool_Position_Maps.Element (Position_Cursor);
         begin
            for Claim of Pos.Claims loop
               if Claim.Env_Id = Env then
                  return Claim;
               end if;
            end loop;
         end;
      end loop;

      return
        (Env_Id    => Env,
         Remaining => Empty_Balance,
         Headroom  => Empty_Balance);
   end Claim_For;

   function "=" (Left, Right : Backed_Envelope_Claim) return Boolean is
   begin
      return Left.Env_Id = Right.Env_Id
        and then Is_Zero_Balance
          (Subtract_Balance (Left.Remaining, Right.Remaining))
        and then Is_Zero_Balance
          (Subtract_Balance (Left.Headroom, Right.Headroom));
   end "=";

   function "=" (Left, Right : Backing_Pool_Position) return Boolean is
   begin
      return Left.Pool_Id = Right.Pool_Id
        and then Is_Zero_Balance
          (Subtract_Balance (Left.Funding_Balance, Right.Funding_Balance))
        and then Is_Zero_Balance
          (Subtract_Balance
             (Left.Funding_Commitment, Right.Funding_Commitment))
        and then Is_Zero_Balance
          (Subtract_Balance
             (Left.Gross_Envelope_Required,
              Right.Gross_Envelope_Required))
        and then Is_Zero_Balance
          (Subtract_Balance
             (Left.Available_Envelope_Required,
              Right.Available_Envelope_Required));
   end "=";

end ALedger.Backing_Policy;
