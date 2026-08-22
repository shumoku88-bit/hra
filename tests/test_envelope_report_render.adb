with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with Ada.Text_IO; use Ada.Text_IO;
with HRA.Backing_Policy;
with HRA.Cycle_Observation;
with HRA.Dates;
with HRA.Envelope; use HRA.Envelope;
with HRA.Envelope_Consumption;
with HRA.Envelope_Report_Render;
with HRA.Household_Envelope_Change;
with HRA.Household_Envelope_Cycle_Comparison;
with HRA.Household_Report_Observation;
with HRA.Money; use HRA.Money;
with HRA.Terminal_Layout;
with HRA.Terminal_UTF8;

procedure Test_Envelope_Report_Render is
   package Change renames HRA.Household_Envelope_Change;
   package Comparison renames HRA.Household_Envelope_Cycle_Comparison;

   Passed_Count : Natural := 0;
   Failed_Count : Natural := 0;

   procedure Assert (Condition : Boolean; Test_Name : String) is
   begin
      if Condition then
         Put_Line ("[PASS] " & Test_Name);
         Passed_Count := Passed_Count + 1;
      else
         Put_Line ("[FAIL] " & Test_Name);
         Failed_Count := Failed_Count + 1;
      end if;
   end Assert;

   function U
     (Text : String;
      Code : HRA.Terminal_UTF8.Unicode_Code_Point) return String is
     (HRA.Terminal_UTF8.Append_Code_Point (Text, Code));

   function Line_Containing (Text, Needle : String) return String is
      Match_At : constant Natural := Index (Text, Needle);
      Start_At : Natural := Match_At;
      Stop_At  : Natural;
   begin
      if Match_At = 0 then
         raise Program_Error with "missing rendered test line: " & Needle;
      end if;
      while Start_At > Text'First
        and then Text (Start_At - 1) /= ASCII.LF
      loop
         Start_At := Start_At - 1;
      end loop;
      Stop_At := Index (Text (Start_At .. Text'Last), String'(1 => ASCII.LF));
      if Stop_At = 0 then
         return Text (Start_At .. Text'Last);
      end if;
      return Text (Start_At .. Stop_At - 1);
   end Line_Containing;

   function Separator_Column
     (Text : String; Occurrence : Positive) return Natural
   is
      Seen : Natural := 0;
   begin
      for Index in Text'Range loop
         if Text (Index) = '|' then
            Seen := Seen + 1;
            if Seen = Occurrence then
               return HRA.Terminal_Layout.Display_Width
                 (Text (Text'First .. Index - 1));
            end if;
         end if;
      end loop;
      raise Program_Error with "missing rendered separator";
   end Separator_Column;

   function D (Text : String) return HRA.Dates.Date is
      Result : HRA.Dates.Date;
      Status : HRA.Dates.Date_Status;
   begin
      if not HRA.Dates.Parse (Text, Result, Status) then
         raise Program_Error with "invalid test date: " & Text;
      end if;
      return Result;
   end D;

   function W
     (First_Day, Limit_Day : String) return HRA.Cycle_Observation.Cycle_Window
   is
      Result : HRA.Dates.Half_Open_Period;
   begin
      if not HRA.Dates.Make_Half_Open_Period
        (D (First_Day), D (Limit_Day), Result)
      then
         raise Program_Error with "invalid test window";
      end if;
      return Result;
   end W;

   JPY : constant Commodity := Make_Commodity ("JPY");
   Food : constant Envelope_Id := Make_Envelope_Id ("food");
   Mixed_Food : constant Envelope_Id := Make_Envelope_Id
     ("food-" & U (U ("", 16#98DF#), 16#8CBB#));

   function B (Value : Quantity) return Balance is
     (Singleton_Balance (Make_Amount (JPY, Value)));

begin
   HRA.Terminal_UTF8.Initialize;
   Put_Line ("--- Testing temporal Envelope report rendering ---");

   declare
      package Report renames HRA.Household_Report_Observation;
      Observation : Report.Envelope_Report_Observation :=
        (Observed_Through      => D ("2026-08-15"),
         Current_Cycle         => W ("2026-08-01", "2026-09-01"),
         Lines                 => Report.Envelope_Report_Line_Vectors.Empty_Vector,
         Unmanaged_Consumption =>
           Report.Account_Consumption_Line_Vectors.Empty_Vector,
         Unrouted_Consumption =>
           Report.Account_Consumption_Line_Vectors.Empty_Vector,
         Unmanaged_Commitment =>
           Report.Account_Commitment_Line_Vectors.Empty_Vector,
         Unrouted_Commitment  =>
           Report.Account_Commitment_Line_Vectors.Empty_Vector,
         Backing_Lines         => Report.Backing_Report_Line_Vectors.Empty_Vector,
         Signed_Envelope_Total => B (1_255.0),
         Unallocated           => Empty_Balance,
         Total_Funding_Assets  => B (1_255.0),
         Backing_Status        => HRA.Backing_Policy.Fully_Backed);
   begin
      Observation.Lines.Append
        (Report.Envelope_Report_Line'
           (Env_Id => Food, Entitlement => B (5.0),
          Consumption_Charges => B (1.0), Consumption_Refunds => Empty_Balance,
          Net_Consumption => B (1.0), Fulfillment_Applied => Empty_Balance,
          Fulfillment_Reversed => Empty_Balance,
          Net_Fulfillment => Empty_Balance, Remaining => B (4.0),
          Plan_Commitment => Empty_Balance, Headroom => B (4.0)));
      Observation.Lines.Append
        (Report.Envelope_Report_Line'
           (Env_Id => Mixed_Food, Entitlement => B (1_250.0),
          Consumption_Charges => B (10.0), Consumption_Refunds => B (5.0),
          Net_Consumption => B (5.0), Fulfillment_Applied => Empty_Balance,
          Fulfillment_Reversed => Empty_Balance,
          Net_Fulfillment => Empty_Balance, Remaining => B (1_245.0),
          Plan_Commitment => B (-200.0), Headroom => B (1_045.0)));

      declare
         Text : constant String := HRA.Envelope_Report_Render.Render (Observation);
         Header : constant String := Line_Containing (Text, "Entitlement");
         ASCII_Row : constant String := Line_Containing (Text, "food ");
         Mixed_Row : constant String :=
           Line_Containing (Text, HRA.Envelope.Image (Mixed_Food));
      begin
         for Separator in 1 .. 7 loop
            Assert
              (Separator_Column (Header, Separator) =
                 Separator_Column (ASCII_Row, Separator)
               and then Separator_Column (Header, Separator) =
                 Separator_Column (Mixed_Row, Separator),
               "ASCII and mixed UTF-8 Envelope rows keep separator" &
               Separator'Image & " in the header column");
         end loop;
         Assert
           (Index (ASCII_Row, "|       5 JPY |") > 0,
            "Envelope numeric cells are right aligned");
         Assert
           (HRA.Terminal_Layout.Display_Width (Header) =
              HRA.Terminal_Layout.Display_Width (Mixed_Row),
            "Envelope header and mixed UTF-8 body have one display width");
      end;
   end;

   declare
      Observation : Change.Change_Observation :=
        (Window       => W ("2026-08-01", "2026-09-01"),
         From_Date    => D ("2026-08-10"),
         Through_Date => D ("2026-08-15"),
         Lines        => Change.Change_Line_Vectors.Empty_Vector);
   begin
      Observation.Lines.Append
        (Change.Change_Line'
           (Env_Id                 => Food,
            Entitlement            => B (50.0),
            Consumption_Charges    => B (50.0),
            Consumption_Refunds    => B (20.0),
            Net_Consumption        => B (30.0),
            Fulfillment_Applied    => B (30.0),
            Fulfillment_Reversed   => B (10.0),
            Net_Fulfillment        => B (20.0),
            Remaining              => Empty_Balance,
            Plan_Commitment        => B (-50.0),
            Headroom               => B (50.0)));

      declare
         Text : constant String := HRA.Envelope_Report_Render.Render (Observation);
      begin
         Assert
           (Index (Text, "== Envelope Change ==") > 0,
            "Change renderer names the temporal question");
         Assert
           (Index (Text, "From: 2026-08-10") > 0
              and then Index (Text, "Through: 2026-08-15") > 0,
            "Change renderer retains explicit observation interval");
         Assert
           (Index (Text, "Envelope: food") > 0
              and then Index (Text, "Consumption charges change : 50 JPY") > 0
              and then Index (Text, "Plan commitment change     : (50 JPY)") > 0,
            "Change renderer exposes typed gross and signed differences");
      end;
   end;

   declare
      Observation : Comparison.Comparison_Observation :=
        (Current_Window   => W ("2026-08-01", "2026-09-01"),
         Baseline_Window  => W ("2026-07-01", "2026-08-01"),
         Current_Through  => D ("2026-08-10"),
         Baseline_Through => D ("2026-07-10"),
         Lines            => Comparison.Comparison_Line_Vectors.Empty_Vector);
   begin
      Observation.Lines.Append
        (Comparison.Comparison_Line'
           (Env_Id               => Food,
            Current_Consumption  =>
              HRA.Envelope_Consumption.Make_Amounts
                (Charges => B (40.0), Refunds => B (10.0)),
            Baseline_Consumption =>
              HRA.Envelope_Consumption.Make_Amounts
                (Charges => B (10.0), Refunds => Empty_Balance),
            Current_Fulfillment  =>
              (Applied => Empty_Balance, Reversed => Empty_Balance),
            Baseline_Fulfillment =>
              (Applied => Empty_Balance, Reversed => Empty_Balance),
            Current_Entitlement  => B (150.0),
            Baseline_Entitlement => B (50.0),
            Current_Remaining    => B (105.0),
            Baseline_Remaining   => B (35.0),
            Current_Commitment   => Empty_Balance,
            Baseline_Commitment  => Empty_Balance,
            Current_Headroom     => B (105.0),
            Baseline_Headroom    => B (35.0)));

      declare
         Text : constant String := HRA.Envelope_Report_Render.Render (Observation);
      begin
         Assert
           (Index (Text, "== Envelope Aligned Previous Cycle ==") > 0,
            "Cycle comparison renderer keeps a distinct report identity");
         Assert
           (Index (Text, "Current through: 2026-08-10") > 0
              and then Index (Text, "Baseline through: 2026-07-10") > 0,
            "Cycle comparison renderer retains aligned temporal coordinates");
         Assert
           (Index
              (Text,
               "Consumption net          : 30 JPY current | 10 JPY baseline | 20 JPY difference") > 0
              and then Index
                (Text,
                 "Remaining                : 105 JPY current | 35 JPY baseline | 70 JPY difference") > 0,
            "Cycle comparison renderer delegates differences to typed comparison owner");
      end;
   end;

   Put_Line
     (Natural'Image (Passed_Count) & " passed, " &
      Natural'Image (Failed_Count) & " failed");

   if Failed_Count > 0 then
      raise Program_Error with "temporal Envelope report render tests failed";
   end if;
end Test_Envelope_Report_Render;
