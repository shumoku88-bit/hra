with Ada.Text_IO; use Ada.Text_IO;
with HRA.Dates;
with HRA.Household_Envelope_Change;

procedure Test_Envelope_Change_Baseline is
   use type HRA.Dates.Date;
   use type HRA.Household_Envelope_Change.Baseline_Kind;
   use type HRA.Household_Envelope_Change.Baseline_Status;

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

   function D (S : String) return HRA.Dates.Date is
      Value  : HRA.Dates.Date;
      Status : HRA.Dates.Date_Status;
   begin
      if not HRA.Dates.Parse (S, Value, Status) then
         raise Program_Error with "invalid test date: " & S;
      end if;
      return Value;
   end D;

   function W
     (First_Day, Limit_Day : String)
      return HRA.Dates.Half_Open_Period
   is
      Result : HRA.Dates.Half_Open_Period;
   begin
      if not HRA.Dates.Make_Half_Open_Period
        (D (First_Day), D (Limit_Day), Result)
      then
         raise Program_Error with
           "invalid test window: " & First_Day & ".." & Limit_Day;
      end if;
      return Result;
   end W;

   August : constant HRA.Dates.Half_Open_Period :=
     W ("2026-08-01", "2026-09-01");

   No_Previous : constant
     HRA.Household_Envelope_Change.Previous_Observation_Context :=
       (Kind => HRA.Household_Envelope_Change.No_Previous_Observation);

   Previous_8_7 : constant
     HRA.Household_Envelope_Change.Previous_Observation_Context :=
       (Kind             =>
          HRA.Household_Envelope_Change.Previous_Observation_Available,
        Observed_Through => D ("2026-08-07"));

   Resolved : HRA.Household_Envelope_Change.Resolved_Change_Baseline;
   Diag     : HRA.Household_Envelope_Change.Baseline_Diagnostic;

begin
   Put_Line ("--- Testing typed Envelope Change baseline selection ---");

   Assert
     (HRA.Household_Envelope_Change.Resolve_Baseline
        (August,
         D ("2026-08-10"),
         Previous_8_7,
         (Kind => HRA.Household_Envelope_Change.Previous_Observation),
         Resolved,
         Diag)
        and then Diag.Status = HRA.Household_Envelope_Change.Success
        and then HRA.Household_Envelope_Change.Resolved_Day (Resolved) =
          D ("2026-08-07")
        and then
          HRA.Household_Envelope_Change.Resolved_Request (Resolved).Kind =
            HRA.Household_Envelope_Change.Previous_Observation,
      "PreviousObservation uses caller-supplied observation context");

   Assert
     (not HRA.Household_Envelope_Change.Resolve_Baseline
        (August,
         D ("2026-08-10"),
         No_Previous,
         (Kind => HRA.Household_Envelope_Change.Previous_Observation),
         Resolved,
         Diag)
        and then Diag.Status =
          HRA.Household_Envelope_Change.Previous_Observation_Unavailable,
      "PreviousObservation is never inferred when context is absent");

   declare
      Same_Day : constant
        HRA.Household_Envelope_Change.Previous_Observation_Context :=
          (Kind             =>
             HRA.Household_Envelope_Change.Previous_Observation_Available,
           Observed_Through => D ("2026-08-10"));
   begin
      Assert
        (not HRA.Household_Envelope_Change.Resolve_Baseline
           (August,
            D ("2026-08-10"),
            Same_Day,
            (Kind => HRA.Household_Envelope_Change.Previous_Observation),
            Resolved,
            Diag)
           and then Diag.Status =
             HRA.Household_Envelope_Change.Previous_Observation_Not_Before,
         "PreviousObservation must be strictly earlier");
   end;

   declare
      Previous_July : constant
        HRA.Household_Envelope_Change.Previous_Observation_Context :=
          (Kind             =>
             HRA.Household_Envelope_Change.Previous_Observation_Available,
           Observed_Through => D ("2026-07-31"));
   begin
      Assert
        (not HRA.Household_Envelope_Change.Resolve_Baseline
           (August,
            D ("2026-08-10"),
            Previous_July,
            (Kind => HRA.Household_Envelope_Change.Previous_Observation),
            Resolved,
            Diag)
           and then Diag.Status =
             HRA.Household_Envelope_Change.Baseline_Day_Outside_Window,
         "PreviousObservation cannot silently cross the cycle boundary");
   end;

   Assert
     (HRA.Household_Envelope_Change.Resolve_Baseline
        (August,
         D ("2026-08-10"),
         No_Previous,
         (Kind => HRA.Household_Envelope_Change.Previous_Day),
         Resolved,
         Diag)
        and then HRA.Household_Envelope_Change.Resolved_Day (Resolved) =
          D ("2026-08-09"),
      "PreviousDay resolves inside the current cycle");

   Assert
     (not HRA.Household_Envelope_Change.Resolve_Baseline
        (August,
         D ("2026-08-01"),
         No_Previous,
         (Kind => HRA.Household_Envelope_Change.Previous_Day),
         Resolved,
         Diag)
        and then Diag.Status =
          HRA.Household_Envelope_Change.Baseline_Day_Outside_Window,
      "PreviousDay fails closed at the cycle boundary");

   Assert
     (HRA.Household_Envelope_Change.Resolve_Baseline
        (August,
         D ("2026-08-10"),
         No_Previous,
         (Kind => HRA.Household_Envelope_Change.Cycle_Start),
         Resolved,
         Diag)
        and then HRA.Household_Envelope_Change.Resolved_Day (Resolved) =
          D ("2026-08-01"),
      "CycleStart resolves to the current cycle start");

   Assert
     (HRA.Household_Envelope_Change.Resolve_Baseline
        (August,
         D ("2026-08-10"),
         No_Previous,
         (Kind          => HRA.Household_Envelope_Change.Explicit_Day,
          Requested_Day => D ("2026-08-05")),
         Resolved,
         Diag)
        and then HRA.Household_Envelope_Change.Resolved_Day (Resolved) =
          D ("2026-08-05"),
      "ExplicitDay preserves its requested coordinate");

   Assert
     (HRA.Household_Envelope_Change.Resolve_Baseline
        (August,
         D ("2026-08-10"),
         No_Previous,
         (Kind          => HRA.Household_Envelope_Change.Explicit_Day,
          Requested_Day => D ("2026-08-10")),
         Resolved,
         Diag)
        and then HRA.Household_Envelope_Change.Resolved_Day (Resolved) =
          D ("2026-08-10"),
      "ExplicitDay permits an intentional zero-length comparison");

   Assert
     (not HRA.Household_Envelope_Change.Resolve_Baseline
        (August,
         D ("2026-08-10"),
         No_Previous,
         (Kind          => HRA.Household_Envelope_Change.Explicit_Day,
          Requested_Day => D ("2026-08-11")),
         Resolved,
         Diag)
        and then Diag.Status =
          HRA.Household_Envelope_Change.Baseline_Day_After_Observation,
      "ExplicitDay cannot point after the later observation");

   Assert
     (not HRA.Household_Envelope_Change.Resolve_Baseline
        (August,
         D ("2026-09-01"),
         No_Previous,
         (Kind => HRA.Household_Envelope_Change.Cycle_Start),
         Resolved,
         Diag)
        and then Diag.Status =
          HRA.Household_Envelope_Change.Through_Outside_Window,
      "later observation must itself belong to the cycle window");

   declare
      Minimum_Window : constant HRA.Dates.Half_Open_Period :=
        W ("0001-01-01", "0001-01-02");
   begin
      Assert
        (not HRA.Household_Envelope_Change.Resolve_Baseline
           (Minimum_Window,
            D ("0001-01-01"),
            No_Previous,
            (Kind => HRA.Household_Envelope_Change.Previous_Day),
            Resolved,
            Diag)
           and then Diag.Status =
             HRA.Household_Envelope_Change.Previous_Day_Unavailable,
         "PreviousDay exposes the bounded Gregorian lower limit");
   end;

   Put_Line
     (Natural'Image (Passed_Count) & " passed, " &
      Natural'Image (Failed_Count) & " failed");

   if Failed_Count > 0 then
      raise Program_Error with "Envelope Change baseline tests failed";
   end if;
end Test_Envelope_Change_Baseline;
