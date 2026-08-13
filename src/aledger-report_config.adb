with TOML;

package body ALedger.Report_Config is

   use type TOML.Any_Integer;

   Source_Name : constant String := "report.toml";

   function Is_Leap (Year : Positive) return Boolean is
     (Year mod 400 = 0 or else (Year mod 4 = 0 and then Year mod 100 /= 0));

   function Valid_Date (Text : String) return Boolean is
      Year, Month, Day, Max_Day : Natural;
   begin
      if Text'Length /= 10
        or else Text (Text'First + 4) /= '-'
        or else Text (Text'First + 7) /= '-'
      then return False; end if;
      for Offset in 0 .. 9 loop
         if Offset /= 4 and then Offset /= 7
           and then Text (Text'First + Offset) not in '0' .. '9'
         then return False; end if;
      end loop;
      Year := Natural'Value (Text (Text'First .. Text'First + 3));
      Month := Natural'Value (Text (Text'First + 5 .. Text'First + 6));
      Day := Natural'Value (Text (Text'First + 8 .. Text'First + 9));
      if Year = 0 or else Month not in 1 .. 12 then return False; end if;
      Max_Day := (case Month is
         when 2 => (if Is_Leap (Year) then 29 else 28),
         when 4 | 6 | 9 | 11 => 30,
         when others => 31);
      return Day in 1 .. Max_Day;
   exception
      when Constraint_Error => return False;
   end Valid_Date;

   function Parse_Boundary
     (Value : TOML.TOML_Value; Path : String; Allow_Beginning : Boolean;
      Result : out Date_Boundary; Diag : out Config_Diagnostic) return Boolean
   is
      Text : constant String := Value.As_String;
   begin
      if Text = "latest" then Result := (Kind => Latest, Date => Null_Unbounded_String);
      elsif Text = "beginning" and then Allow_Beginning then Result := (Kind => Beginning, Date => Null_Unbounded_String);
      elsif Valid_Date (Text) then Result := (Kind => Exact_Date, Date => To_Unbounded_String (Text));
      else
         Set_Error (Diag, Source_Name, Path,
           (if Allow_Beginning then "expected latest, beginning, or YYYY-MM-DD" else "expected latest or YYYY-MM-DD"), Value);
         return False;
      end if;
      return True;
   end Parse_Boundary;

   function Parse_Color
     (Value : TOML.TOML_Value; Path : String;
      Result : out Presentation_Color; Diag : out Config_Diagnostic) return Boolean
   is
      Text : constant String := Value.As_String;
   begin
      if Text = "red" then Result := Red;
      elsif Text = "bright-red" then Result := Bright_Red;
      elsif Text = "green" then Result := Green;
      elsif Text = "yellow" then Result := Yellow;
      elsif Text = "blue" then Result := Blue;
      elsif Text = "magenta" then Result := Magenta;
      elsif Text = "cyan" then Result := Cyan;
      elsif Text = "white" then Result := White;
      else Set_Error (Diag, Source_Name, Path, "unsupported presentation color", Value); return False;
      end if;
      return True;
   end Parse_Color;

   function Parse_Marker
     (Value : TOML.TOML_Value; Path : String;
      Result : out Character; Diag : out Config_Diagnostic) return Boolean
   is
      Text : constant String := Value.As_String;
   begin
      if Text'Length /= 1 or else Text (Text'First) not in '!' .. '~' then
         Set_Error (Diag, Source_Name, Path, "expected one printable non-space ASCII character", Value);
         return False;
      end if;
      Result := Text (Text'First);
      return True;
   end Parse_Marker;

   function Parse_As_Of
     (Table : TOML.TOML_Value; Path : String; Spec : out As_Of_Spec;
      Diag : out Config_Diagnostic) return Boolean
   is Value : TOML.TOML_Value;
   begin
      return Check_Keys (Table, "as-of", Source_Name, Path, Diag)
        and then Require (Table, "as-of", TOML.TOML_String, Source_Name, Path, Value, Diag)
        and then Parse_Boundary (Value, Path & ".as-of", False, Spec.Value, Diag);
   end Parse_As_Of;

   function Parse_Range
     (Table : TOML.TOML_Value; Path : String; Extra_Key : String;
      Spec : out Range_Spec; Diag : out Config_Diagnostic) return Boolean
   is From_Value, Through_Value : TOML.TOML_Value;
      Allowed : constant String := (if Extra_Key'Length = 0 then "from|through" else "from|through|" & Extra_Key);
   begin
      return Check_Keys (Table, Allowed, Source_Name, Path, Diag)
        and then Require (Table, "from", TOML.TOML_String, Source_Name, Path, From_Value, Diag)
        and then Require (Table, "through", TOML.TOML_String, Source_Name, Path, Through_Value, Diag)
        and then Parse_Boundary (From_Value, Path & ".from", True, Spec.From, Diag)
        and then Parse_Boundary (Through_Value, Path & ".through", False, Spec.Through, Diag);
   end Parse_Range;

   function Parse_Report_Configuration
     (Text   : String;
      Config : out Report_Configuration;
      Diag   : out Config_Diagnostic) return Boolean
   is
      Root, Presentation, Reports, Hierarchy, Amounts, Calendar : TOML.TOML_Value;
      Trial, Balance, Profit, Daily, Monthly, Recent : TOML.TOML_Value;
      Value, Through_Value, Count_Value, Columns_Value : TOML.TOML_Value;
      Has_Presentation, Has_Hierarchy, Has_Amounts, Has_Calendar, Has_Value : Boolean;
      Result : Report_Configuration;
   begin
      if not Parse_Root (Text, Source_Name, Root, Diag)
        or else not Check_Keys (Root, "presentation|reports", Source_Name, "", Diag)
        or else not Require (Root, "reports", TOML.TOML_Table, Source_Name, "", Reports, Diag)
        or else not Optional (Root, "presentation", TOML.TOML_Table, Source_Name, "", Presentation, Has_Presentation, Diag)
      then return False; end if;

      if Has_Presentation then
         if not Check_Keys (Presentation, "hierarchy|amounts|calendar", Source_Name, "presentation", Diag)
           or else not Optional (Presentation, "hierarchy", TOML.TOML_Table, Source_Name, "presentation", Hierarchy, Has_Hierarchy, Diag)
           or else not Optional (Presentation, "amounts", TOML.TOML_Table, Source_Name, "presentation", Amounts, Has_Amounts, Diag)
           or else not Optional (Presentation, "calendar", TOML.TOML_Table, Source_Name, "presentation", Calendar, Has_Calendar, Diag)
         then return False; end if;

         if Has_Hierarchy then
            if not Check_Keys (Hierarchy, "heading-color|section-color", Source_Name, "presentation.hierarchy", Diag) then return False; end if;
            if not Optional (Hierarchy, "heading-color", TOML.TOML_String, Source_Name, "presentation.hierarchy", Value, Has_Value, Diag) then return False; end if;
            if Has_Value and then not Parse_Color (Value, "presentation.hierarchy.heading-color", Result.Presentation.Heading_Color, Diag) then return False; end if;
            if not Optional (Hierarchy, "section-color", TOML.TOML_String, Source_Name, "presentation.hierarchy", Value, Has_Value, Diag) then return False; end if;
            if Has_Value and then not Parse_Color (Value, "presentation.hierarchy.section-color", Result.Presentation.Section_Color, Diag) then return False; end if;
         end if;

         if Has_Amounts then
            if not Check_Keys (Amounts, "negative-style|positive-color|negative-color", Source_Name, "presentation.amounts", Diag)
              or else not Require (Amounts, "negative-style", TOML.TOML_String, Source_Name, "presentation.amounts", Value, Diag)
            then return False; end if;
            if Value.As_String = "parentheses" then Result.Presentation.Negative := Parentheses;
            elsif Value.As_String = "minus" then Result.Presentation.Negative := Minus;
            else Set_Error (Diag, Source_Name, "presentation.amounts.negative-style", "expected parentheses or minus", Value); return False; end if;
            if not Optional (Amounts, "positive-color", TOML.TOML_String, Source_Name, "presentation.amounts", Value, Has_Value, Diag) then return False; end if;
            if Has_Value and then not Parse_Color (Value, "presentation.amounts.positive-color", Result.Presentation.Positive_Color, Diag) then return False; end if;
            if not Optional (Amounts, "negative-color", TOML.TOML_String, Source_Name, "presentation.amounts", Value, Has_Value, Diag) then return False; end if;
            if Has_Value and then not Parse_Color (Value, "presentation.amounts.negative-color", Result.Presentation.Negative_Color, Diag) then return False; end if;
         end if;

         if Has_Calendar then
            if not Check_Keys (Calendar, "cycle-end-marker|plan-due-marker|issue-due-marker|multiple-marker", Source_Name, "presentation.calendar", Diag) then return False; end if;
            if not Optional (Calendar, "cycle-end-marker", TOML.TOML_String, Source_Name, "presentation.calendar", Value, Has_Value, Diag) then return False; end if;
            if Has_Value and then not Parse_Marker (Value, "presentation.calendar.cycle-end-marker", Result.Presentation.Calendar.Cycle_End, Diag) then return False; end if;
            if not Optional (Calendar, "plan-due-marker", TOML.TOML_String, Source_Name, "presentation.calendar", Value, Has_Value, Diag) then return False; end if;
            if Has_Value and then not Parse_Marker (Value, "presentation.calendar.plan-due-marker", Result.Presentation.Calendar.Plan_Due, Diag) then return False; end if;
            if not Optional (Calendar, "issue-due-marker", TOML.TOML_String, Source_Name, "presentation.calendar", Value, Has_Value, Diag) then return False; end if;
            if Has_Value and then not Parse_Marker (Value, "presentation.calendar.issue-due-marker", Result.Presentation.Calendar.Issue_Due, Diag) then return False; end if;
            if not Optional (Calendar, "multiple-marker", TOML.TOML_String, Source_Name, "presentation.calendar", Value, Has_Value, Diag) then return False; end if;
            if Has_Value and then not Parse_Marker (Value, "presentation.calendar.multiple-marker", Result.Presentation.Calendar.Multiple, Diag) then return False; end if;
         end if;
      end if;

      if not Check_Keys (Reports, "trial-balance|balance-sheet|profit-and-loss|daily-flow|monthly-accounts|recent-transactions", Source_Name, "reports", Diag)
        or else not Require (Reports, "trial-balance", TOML.TOML_Table, Source_Name, "reports", Trial, Diag)
        or else not Require (Reports, "balance-sheet", TOML.TOML_Table, Source_Name, "reports", Balance, Diag)
        or else not Require (Reports, "profit-and-loss", TOML.TOML_Table, Source_Name, "reports", Profit, Diag)
        or else not Require (Reports, "daily-flow", TOML.TOML_Table, Source_Name, "reports", Daily, Diag)
        or else not Require (Reports, "monthly-accounts", TOML.TOML_Table, Source_Name, "reports", Monthly, Diag)
        or else not Require (Reports, "recent-transactions", TOML.TOML_Table, Source_Name, "reports", Recent, Diag)
        or else not Parse_As_Of (Trial, "reports.trial-balance", Result.Plan.Trial_Balance, Diag)
        or else not Parse_As_Of (Balance, "reports.balance-sheet", Result.Plan.Balance_Sheet, Diag)
        or else not Parse_Range (Profit, "reports.profit-and-loss", "", Result.Plan.Profit_And_Loss, Diag)
        or else not Parse_Range (Daily, "reports.daily-flow", "max-date-columns", Result.Plan.Daily_Flow, Diag)
        or else not Parse_Range (Monthly, "reports.monthly-accounts", "", Result.Plan.Monthly_Accounts, Diag)
      then return False; end if;

      if not Optional (Daily, "max-date-columns", TOML.TOML_Integer, Source_Name, "reports.daily-flow", Columns_Value, Has_Value, Diag) then return False; end if;
      if Has_Value then
         if Columns_Value.As_Integer <= 0 or else Columns_Value.As_Integer > TOML.Any_Integer (Positive'Last) then
            Set_Error (Diag, Source_Name, "reports.daily-flow.max-date-columns", "expected positive representable integer", Columns_Value); return False;
         end if;
         Result.Presentation.Daily_Date_Columns := Positive (Columns_Value.As_Integer);
      end if;

      if not Check_Keys (Recent, "through|count", Source_Name, "reports.recent-transactions", Diag)
        or else not Require (Recent, "through", TOML.TOML_String, Source_Name, "reports.recent-transactions", Through_Value, Diag)
        or else not Require (Recent, "count", TOML.TOML_Integer, Source_Name, "reports.recent-transactions", Count_Value, Diag)
        or else not Parse_Boundary (Through_Value, "reports.recent-transactions.through", False, Result.Plan.Recent_Transactions.Through, Diag)
      then return False; end if;
      if Count_Value.As_Integer <= 0 or else Count_Value.As_Integer > TOML.Any_Integer (Positive'Last) then
         Set_Error (Diag, Source_Name, "reports.recent-transactions.count", "expected positive representable integer", Count_Value); return False;
      end if;
      Result.Plan.Recent_Transactions.Count := Positive (Count_Value.As_Integer);

      Config := Result;
      return True;
   end Parse_Report_Configuration;

end ALedger.Report_Config;
