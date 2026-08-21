with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA.Daily_Target_Rate;
with HRA.Daily_Target_Scope;
with HRA.Money; use HRA.Money;

package body HRA.Daily_Target_Render is

   function Render_Amount_Or_Paren
     (Q : Quantity; Comm_Code : String) return String
   is
   begin
      if Is_Zero (Q) then
         return "0 " & Comm_Code;
      elsif Q < Zero_Quantity then
         return "(" & Render_Quantity (-Q) & " " & Comm_Code & ")";
      else
         return Render_Quantity (Q) & " " & Comm_Code;
      end if;
   end Render_Amount_Or_Paren;

   function Render_Balance (B : Balance) return String is
      Ents : constant Balance_Entry_Array := Entries (B);
      Buf  : Unbounded_String;
   begin
      if Ents'Length = 0 then
         return "0";
      end if;

      for I in Ents'Range loop
         if I > Ents'First then
            Append (Buf, ", ");
         end if;
         Append
           (Buf,
            Render_Amount_Or_Paren
              (Ents (I).Val, Code (Ents (I).Comm)));
      end loop;
      return To_String (Buf);
   end Render_Balance;

   function Gentle_Scope_Message
     (Diag : HRA.Daily_Target_Scope.Admission_Diagnostic) return String
   is
   begin
      case Diag.Status is
         when HRA.Daily_Target_Scope.Success =>
            return "";
         when HRA.Daily_Target_Scope.Empty_Selection_Id =>
            return "daily target selection identifier is empty";
         when HRA.Daily_Target_Scope.Duplicate_Selection_Id =>
            return "daily target selection identifier is duplicated";
         when HRA.Daily_Target_Scope.Duplicate_Daily_Target_Metadata =>
            return "daily target metadata is specified multiple times";
         when HRA.Daily_Target_Scope.Reservation_Without_Selection =>
            return "reservation is specified without a daily target selection";
         when HRA.Daily_Target_Scope.Incomplete_Reservation =>
            return "reservation details are incomplete";
         when HRA.Daily_Target_Scope.Invalid_Reservation_Id =>
            return "reservation identifier is invalid";
         when HRA.Daily_Target_Scope.Invalid_Reservation_Amount =>
            return "reservation amount is invalid";
         when HRA.Daily_Target_Scope.Invalid_Reservation_Commodity =>
            return "reservation commodity is invalid";
         when HRA.Daily_Target_Scope.Nonpositive_Reservation_Amount =>
            return "reservation amount must be positive";
         when HRA.Daily_Target_Scope.Unsupported_Selected_Plan_Shape =>
            return "selected plan does not match a supported daily target shape (one asset source and one expense/liability destination)";
         when HRA.Daily_Target_Scope.Reservation_Commodity_Mismatch =>
            return "reservation commodity does not match obligation";
         when HRA.Daily_Target_Scope.Reservation_Exceeds_Obligation =>
            return "reservation amount exceeds obligation amount";
         when HRA.Daily_Target_Scope.Duplicate_Reservation_Id =>
            return "reservation identifier is duplicated";
         when HRA.Daily_Target_Scope.Missing_Eligible_Assets =>
            return "daily target obligations are present but no eligible assets are configured";
      end case;
   end Gentle_Scope_Message;

   function Gentle_Observation_Message
     (Diag : HRA.Daily_Target_Observation.Observe_Diagnostic) return String
   is
   begin
      case Diag.Status is
         when HRA.Daily_Target_Observation.Success =>
            return "";
         when HRA.Daily_Target_Observation.Observation_Date_Mismatch =>
            return "observation date does not match cycle accounts date";
         when HRA.Daily_Target_Observation.Account_Observation_Outside_Cycle =>
            return "account observation date is outside the current cycle";
         when HRA.Daily_Target_Observation.Eligible_Asset_Missing_From_Account_State =>
            return "configured eligible asset is not present in cycle account state";
         when HRA.Daily_Target_Observation.Duplicate_Eligible_Asset_Row =>
            return "eligible asset appears multiple times in cycle account state";
      end case;
   end Gentle_Observation_Message;

   function Render
     (Value : HRA.Daily_Target_Observation.Observation) return String
   is
      Rate   : constant HRA.Daily_Target_Rate.Rate :=
        HRA.Daily_Target_Rate.Derive (Value);
      Days   : constant Positive :=
        Positive (HRA.Daily_Target_Rate.Remaining_Days (Rate));
      Cap    : constant Balance :=
        HRA.Daily_Target_Rate.Capacity_Numerator (Rate);
      Result : Unbounded_String;
   begin
      Append (Result, "Daily Target" & ASCII.LF);
      Append (Result, "------------" & ASCII.LF);
      Append
        (Result,
         "  Capacity: " & Render_Balance (Cap) & " over " &
         Days'Image (2 .. Days'Image'Last) &
         (if Days = 1 then " remaining day in cycle" else " remaining days in cycle") &
         ASCII.LF);
      Append (Result, "  Breakdown:" & ASCII.LF);
      Append
        (Result,
         "    Eligible assets:       " &
         Render_Balance (HRA.Daily_Target_Observation.Eligible_Assets (Value)) &
         ASCII.LF);
      Append
        (Result,
         "    Open obligations:      " &
         Render_Balance (HRA.Daily_Target_Observation.Open_Obligations (Value)) &
         ASCII.LF);
      Append
        (Result,
         "    Excluded reservations: " &
         Render_Balance (HRA.Daily_Target_Observation.Already_Excluded (Value)) &
         ASCII.LF);
      Append
        (Result,
         "    Net obligations:       " &
         Render_Balance (HRA.Daily_Target_Observation.Net_Obligations (Value)) &
         ASCII.LF);
      Append
        (Result,
         "    Spending capacity:     " &
         Render_Balance (HRA.Daily_Target_Observation.Capacity (Value)) &
         ASCII.LF);
      Append
        (Result,
         "    Remaining days:        " &
         Days'Image (2 .. Days'Image'Last) & ASCII.LF);
      return To_String (Result);
   end Render;

   function Render
     (Value : HRA.Household_Daily_Target_View.View) return String
   is
   begin
      case Value.Status is
         when HRA.Household_Daily_Target_View.Unconfigured =>
            return "Daily Target" & ASCII.LF &
                   "------------" & ASCII.LF &
                   "  (not configured)" & ASCII.LF;

         when HRA.Household_Daily_Target_View.Available =>
            return Render (Value.Observation);

         when HRA.Household_Daily_Target_View.Scope_Unavailable =>
            declare
               Diag : constant HRA.Daily_Target_Scope.Admission_Diagnostic :=
                 Value.Scope_Diagnostic;
               Result : Unbounded_String :=
                 To_Unbounded_String
                   ("Daily Target" & ASCII.LF &
                    "------------" & ASCII.LF &
                    "  (unavailable: " & Gentle_Scope_Message (Diag));
            begin
               if Length (Diag.Plan_Id) > 0 then
                  Append (Result, ", plan-id=" & To_String (Diag.Plan_Id));
               end if;
               if Length (Diag.Selection) > 0 then
                  Append (Result, ", selection=" & To_String (Diag.Selection));
               end if;
               Append (Result, ")" & ASCII.LF);
               if Length (Diag.Message) > 0 then
                  Append (Result, "  " & To_String (Diag.Message) & ASCII.LF);
               end if;
               return To_String (Result);
            end;

         when HRA.Household_Daily_Target_View.Observation_Unavailable =>
            declare
               Diag : constant HRA.Daily_Target_Observation.Observe_Diagnostic :=
                 Value.Observation_Diagnostic;
               Result : Unbounded_String :=
                 To_Unbounded_String
                   ("Daily Target" & ASCII.LF &
                    "------------" & ASCII.LF &
                    "  (unavailable: " & Gentle_Observation_Message (Diag));
            begin
               if Length (Diag.Account_Name) > 0 then
                  Append (Result, ", account=" & To_String (Diag.Account_Name));
               end if;
               Append (Result, ")" & ASCII.LF);
               if Length (Diag.Message) > 0 then
                  Append (Result, "  " & To_String (Diag.Message) & ASCII.LF);
               end if;
               return To_String (Result);
            end;
      end case;
   end Render;

end HRA.Daily_Target_Render;
