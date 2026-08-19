with HRA.Account;

package body HRA.Backing_Policy is

   use type HRA.Dates.Date;
   use type Claim_Vectors.Vector;

   type Funding_Observation_Scope_Kind is
     (All_Funding_Dates, Funding_Through_Date);

   type Funding_Observation_Scope
     (Kind : Funding_Observation_Scope_Kind := All_Funding_Dates)
   is record
      case Kind is
         when All_Funding_Dates =>
            null;
         when Funding_Through_Date =>
            Through : HRA.Dates.Date;
      end case;
   end record;

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

   function Backing_Condition_For
     (Obs : Backing_Observation) return Backing_Condition
   is
   begin
      for Cursor in Obs.Positions.Iterate loop
         declare
            Position : constant Backing_Pool_Position :=
              Pool_Position_Maps.Element (Cursor);
         begin
            --  Gross_Surplus remains the arithmetic owner. Classification
            --  observes every retained Commodity coordinate of that result.
            for Item of Entries (Gross_Surplus (Position)) loop
               if Item.Val < Zero_Quantity then
                  return Under_Backed;
               end if;
            end loop;
         end;
      end loop;
      return Fully_Backed;
   end Backing_Condition_For;

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

   function Empty_Funding_Commitment return Funding_Commitment_Observation is
   begin
      return (By_Pool => Pool_Balance_Maps.Empty_Map);
   end Empty_Funding_Commitment;

   procedure Add_Pool_Commitment
     (Obs     : in out Funding_Commitment_Observation;
      Pool_Id : String;
      Amount  : HRA.Money.Amount)
   is
      Added : Balance := Singleton_Balance (Amount);
   begin
      if Obs.By_Pool.Contains (Pool_Id) then
         Added := Add_Balance (Obs.By_Pool.Element (Pool_Id), Added);
         Obs.By_Pool.Replace (Pool_Id, Added);
      else
         Obs.By_Pool.Insert (Pool_Id, Added);
      end if;
   end Add_Pool_Commitment;

   function Observe_Funding_Commitment
     (Policy     : Backing_Policy;
      Open_Plans : HRA.Plan_Observation.Open_Plan_Vectors.Vector;
      Window     : HRA.Cycle_Observation.Cycle_Window)
      return Funding_Commitment_Observation
   is
      Result : Funding_Commitment_Observation := Empty_Funding_Commitment;
   begin
      for P of Open_Plans loop
         if P.Tx.Date < HRA.Cycle_Observation.End_Exclusive (Window) then
            for Posting of P.Tx.Postings loop
               if Posting.Amt.Val < Zero_Quantity then
                  declare
                     Account_Name : constant String :=
                       HRA.Account.Name (Posting.Acc);
                  begin
                     if Policy.Pool_By_Asset.Contains (Account_Name) then
                        Add_Pool_Commitment
                          (Result,
                           Policy.Pool_By_Asset.Element (Account_Name),
                           Negate_Amount (Posting.Amt));
                     end if;
                  end;
               end if;
            end loop;
         end if;
      end loop;
      return Result;
   end Observe_Funding_Commitment;

   function Funding_Commitment_For
     (Obs     : Funding_Commitment_Observation;
      Pool_Id : String) return Balance
   is
   begin
      if Obs.By_Pool.Contains (Pool_Id) then
         return Obs.By_Pool.Element (Pool_Id);
      else
         return Empty_Balance;
      end if;
   end Funding_Commitment_For;

   function Calculate_Backing
     (Policy             : Backing_Policy;
      L                  : Ledger.Ledger;
      Scope              : Funding_Observation_Scope;
      Positions          : HRA.Envelope_Position.Observation;
      Funding_Commitment : Funding_Commitment_Observation) return Backing_Observation
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
                  Bal : Balance;
               begin
                  case Scope.Kind is
                     when All_Funding_Dates =>
                        Bal := Ledger.Compute_Account_Balance (L, Acc_Obj);
                     when Funding_Through_Date =>
                        Bal := Ledger.Compute_Account_Balance_Through
                          (L, Acc_Obj, Scope.Through);
                  end case;
                  Funding_Bal := Add_Balance (Funding_Bal, Bal);
               end;
            end loop;
            Result.Total_Assets := Add_Balance
              (Result.Total_Assets, Funding_Bal);

            for Env_Str of Envs loop
               declare
                  Env_Id : constant Envelope.Envelope_Id :=
                    Envelope.Make_Envelope_Id (Env_Str);
               begin
                  if not HRA.Envelope_Position.Has_Position (Positions, Env_Id) then
                     raise Program_Error with
                       "Backing observation missing required current envelope position: " &
                       Env_Str;
                  end if;

                  declare
                     Pos : constant HRA.Envelope_Position.Position :=
                       HRA.Envelope_Position.Position_For (Positions, Env_Id);
                  begin
                     Claims_List.Append (Pos);
                     Gross_Req := Add_Balance
                       (Gross_Req, Positive_Balance (Pos.Remaining));
                     Avail_Req := Add_Balance
                       (Avail_Req, Positive_Balance (Pos.Headroom));
                  end;
               end;
            end loop;

            declare
               Pos : constant Backing_Pool_Position :=
                 (Pool_Id                     => To_Unbounded_String (Pool_Name),
                  Claims                      => Claims_List,
                  Funding_Balance             => Funding_Bal,
                  Funding_Commitment          =>
                    Funding_Commitment_For (Funding_Commitment, Pool_Name),
                  Gross_Envelope_Required     => Gross_Req,
                  Available_Envelope_Required => Avail_Req);
            begin
               Result.Positions.Insert (Pool_Name, Pos);
            end;
         end;
      end loop;

      return Result;
   end Calculate_Backing;

   function Observe_Backing
     (Policy    : Backing_Policy;
      L         : Ledger.Ledger;
      Positions : HRA.Envelope_Position.Observation)
      return Backing_Observation
   is
   begin
      return Calculate_Backing
        (Policy,
         L,
         (Kind => All_Funding_Dates),
         Positions,
         Empty_Funding_Commitment);
   end Observe_Backing;

   function Observe_Backing
     (Policy             : Backing_Policy;
      L                  : Ledger.Ledger;
      Observed_Through   : HRA.Dates.Date;
      Positions          : HRA.Envelope_Position.Observation;
      Funding_Commitment : Funding_Commitment_Observation)
      return Backing_Observation
   is
   begin
      return Calculate_Backing
        (Policy,
         L,
         (Kind => Funding_Through_Date, Through => Observed_Through),
         Positions,
         Funding_Commitment);
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

   function "=" (Left, Right : Backing_Pool_Position) return Boolean is
   begin
      return Left.Pool_Id = Right.Pool_Id
        and then Left.Claims = Right.Claims
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

end HRA.Backing_Policy;
