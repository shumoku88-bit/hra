with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with ALedger.Backing_Policy;
with ALedger.Envelope;
with ALedger.Envelope_Commitment;
with ALedger.Envelope_Consumption;
with ALedger.Envelope_Entitlement;
with ALedger.Money; use ALedger.Money;

package body ALedger.Envelope_Report_Render is

   function Render_Amount (Q : Quantity; Commodity_Code : String) return String is
   begin
      if Q < Zero_Quantity then
         return "(" & Render_Quantity (-Q) & " " & Commodity_Code & ")";
      elsif Is_Zero (Q) then
         return "0";
      else
         return Render_Quantity (Q) & " " & Commodity_Code;
      end if;
   end Render_Amount;

   function Render
     (State       : ALedger.Household.Household_State;
      Observation : ALedger.Household_Report_Observation.Report_Observation)
      return String
   is
      use ALedger.Backing_Policy;
      use ALedger.Envelope;
      use ALedger.Envelope_Commitment;
      use ALedger.Envelope_Consumption;
      use ALedger.Envelope_Entitlement;

      Buf : Unbounded_String;
      JPY : constant Commodity := Make_Commodity ("JPY");
      All_Envs : constant Envelope_Id_Array := All_Ids (State.Envelope_Registry);
      Total_Entitlement : Balance := Empty_Balance;
      All_Fully_Backed : Boolean := True;
   begin
      Append (Buf, "== Envelope & Backing ==" & ASCII.LF);
      Append
        (Buf,
         "Observed through: " & To_String (Observation.Observed_Through) & ASCII.LF);
      Append
        (Buf,
         "Current cycle: [" &
         To_String (Observation.Current_Cycle.Start_Date) & ", " &
         To_String (Observation.Current_Cycle.End_Exclusive) & ")" & ASCII.LF);
      Append (Buf, ASCII.LF);
      Append
        (Buf,
         "Envelope      | Entitlement | Consumption |   Refunds |   Remaining | Plan reserve |    Headroom" & ASCII.LF);
      Append
        (Buf,
         "------------------------------------------------------------------------------------------------" & ASCII.LF);

      for Env_Id of All_Envs loop
         declare
            Env_Name : constant String := Image (Env_Id);
            Ent_Bal  : constant Balance := Entitlement_For (State.Entitlement, Env_Id);
            Amts     : constant Consumption_Amounts :=
              Consumption_For (Observation.Consumption, Env_Id);
            Claim    : constant Backed_Envelope_Claim :=
              Claim_For (Observation.Backing, Env_Id);
            Reserve  : constant Balance :=
              Commitment_For (Observation.Commitment, Env_Id);
            Ent_Q : constant Quantity := Lookup_Balance (Ent_Bal, JPY);
            Con_Q : constant Quantity := Lookup_Balance (Amts.Charges, JPY);
            Ref_Q : constant Quantity := Lookup_Balance (Amts.Refunds, JPY);
            Rem_Q : constant Quantity := Lookup_Balance (Claim.Remaining, JPY);
            Res_Q : constant Quantity := Lookup_Balance (Reserve, JPY);
            Hdr_Q : constant Quantity := Lookup_Balance (Claim.Headroom, JPY);
         begin
            Total_Entitlement := Add_Balance (Total_Entitlement, Ent_Bal);
            Append (Buf, Env_Name & " | ");
            Append (Buf, Render_Amount (Ent_Q, "JPY") & " | ");
            Append (Buf, Render_Amount (Con_Q, "JPY") & " | ");
            Append (Buf, Render_Amount (Ref_Q, "JPY") & " | ");
            Append (Buf, Render_Amount (Rem_Q, "JPY") & " | ");
            Append (Buf, Render_Amount (Res_Q, "JPY") & " | ");
            Append (Buf, Render_Amount (Hdr_Q, "JPY") & ASCII.LF);
         end;
      end loop;

      if not Observation.Consumption.Unmanaged.Is_Empty
        or else not Observation.Consumption.Unrouted.Is_Empty
      then
         Append (Buf, ASCII.LF);
         Append (Buf, "Expense activity outside an envelope" & ASCII.LF);
         Append (Buf, "Account             |   Movement" & ASCII.LF);
         Append (Buf, "--------------------------------" & ASCII.LF);

         for Cursor in Observation.Consumption.Unmanaged.Iterate loop
            declare
               Name : constant String := Account_Amounts_Maps.Key (Cursor);
               Amts : constant Consumption_Amounts :=
                 Account_Amounts_Maps.Element (Cursor);
               Net_Q : constant Quantity :=
                 Lookup_Balance (Net_Consumption (Amts), JPY);
            begin
               if not Is_Zero (Net_Q) then
                  Append
                    (Buf,
                     Name & " | " & Render_Amount (Net_Q, "JPY") & ASCII.LF);
               end if;
            end;
         end loop;

         for Cursor in Observation.Consumption.Unrouted.Iterate loop
            declare
               Name : constant String := Account_Amounts_Maps.Key (Cursor);
               Amts : constant Consumption_Amounts :=
                 Account_Amounts_Maps.Element (Cursor);
               Net_Q : constant Quantity :=
                 Lookup_Balance (Net_Consumption (Amts), JPY);
            begin
               if not Is_Zero (Net_Q) then
                  Append
                    (Buf,
                     Name & " (unrouted) | " &
                     Render_Amount (Net_Q, "JPY") & ASCII.LF);
               end if;
            end;
         end loop;
      end if;

      if not Observation.Commitment.Unmanaged.Is_Empty
        or else not Observation.Commitment.Unrouted.Is_Empty
      then
         Append (Buf, ASCII.LF);
         Append (Buf, "Plan commitments outside an envelope" & ASCII.LF);
         Append (Buf, "Account             |   Commitment" & ASCII.LF);
         Append (Buf, "----------------------------------" & ASCII.LF);

         for Cursor in Observation.Commitment.Unmanaged.Iterate loop
            declare
               Name : constant String := Account_Balance_Maps.Key (Cursor);
               Q    : constant Quantity :=
                 Lookup_Balance (Account_Balance_Maps.Element (Cursor), JPY);
            begin
               if not Is_Zero (Q) then
                  Append
                    (Buf,
                     Name & " | " & Render_Amount (Q, "JPY") & ASCII.LF);
               end if;
            end;
         end loop;

         for Cursor in Observation.Commitment.Unrouted.Iterate loop
            declare
               Name : constant String := Account_Balance_Maps.Key (Cursor);
               Q    : constant Quantity :=
                 Lookup_Balance (Account_Balance_Maps.Element (Cursor), JPY);
            begin
               if not Is_Zero (Q) then
                  Append
                    (Buf,
                     Name & " (unrouted) | " &
                     Render_Amount (Q, "JPY") & ASCII.LF);
               end if;
            end;
         end loop;
      end if;

      Append (Buf, ASCII.LF);
      Append (Buf, "Backing evidence" & ASCII.LF);
      Append (Buf, "Coordinate                |       Amount" & ASCII.LF);
      Append (Buf, "----------------------------------------" & ASCII.LF);

      for Cursor in Observation.Backing.Positions.Iterate loop
         declare
            Pool_Name : constant String := Pool_Position_Maps.Key (Cursor);
            Pos       : constant Backing_Pool_Position :=
              Pool_Position_Maps.Element (Cursor);
            Gross_Q : constant Quantity :=
              Lookup_Balance (Gross_Surplus (Pos), JPY);
            Available_Q : constant Quantity :=
              Lookup_Balance (Available_Surplus (Pos), JPY);
         begin
            if Gross_Q < Zero_Quantity then
               All_Fully_Backed := False;
            end if;
            Append
              (Buf,
               "Funding balance (" & Pool_Name & ") | " &
               Render_Amount (Lookup_Balance (Pos.Funding_Balance, JPY), "JPY") &
               ASCII.LF);
            Append
              (Buf,
               "Funding commitment (" & Pool_Name & ") | " &
               Render_Amount
                 (Lookup_Balance (Pos.Funding_Commitment, JPY), "JPY") &
               ASCII.LF);
            Append
              (Buf,
               "Available funding (" & Pool_Name & ") | " &
               Render_Amount
                 (Lookup_Balance (Available_Funding (Pos), JPY), "JPY") &
               ASCII.LF);
            Append
              (Buf,
               "Positive backing required (" & Pool_Name & ") | " &
               Render_Amount
                 (Lookup_Balance (Pos.Gross_Envelope_Required, JPY), "JPY") &
               ASCII.LF);
            Append
              (Buf,
               "Available headroom required (" & Pool_Name & ") | " &
               Render_Amount
                 (Lookup_Balance (Pos.Available_Envelope_Required, JPY), "JPY") &
               ASCII.LF);
            Append
              (Buf,
               "Gross backing surplus (" & Pool_Name & ") | " &
               Render_Amount (Gross_Q, "JPY") & ASCII.LF);
            Append
              (Buf,
               "Available backing surplus (" & Pool_Name & ") | " &
               Render_Amount (Available_Q, "JPY") & ASCII.LF);
         end;
      end loop;

      Append
        (Buf,
         "Signed envelope total     | " &
         Render_Amount (Lookup_Balance (Total_Entitlement, JPY), "JPY") &
         ASCII.LF & ASCII.LF);
      Append
        (Buf,
         (if All_Fully_Backed then "Status: fully_backed" else "Status: under_backed") &
         ASCII.LF);

      return To_String (Buf);
   end Render;

end ALedger.Envelope_Report_Render;
