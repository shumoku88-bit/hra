with Ada.Text_IO; use Ada.Text_IO;
with HRA.Config_Support;
with HRA.Dates;
with HRA.Envelope;
with HRA.Entitlement_Journal;
with HRA.Envelope_Entitlement;
with HRA.Money; use HRA.Money;

procedure Test_Entitlement_Observation_Horizon is
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
      Result : HRA.Dates.Date;
      Status : HRA.Dates.Date_Status;
   begin
      if not HRA.Dates.Parse (S, Result, Status) then
         raise Program_Error with "invalid test date: " & S;
      end if;
      return Result;
   end D;

   Source : constant String :=
     "2026-07-31 origin JPY ; clean epoch" & ASCII.LF &
     "2026-08-01 transfer unallocated -> food 10000 JPY" & ASCII.LF &
     "2026-08-02 transfer food -> daily 2000 JPY" & ASCII.LF;

   Names        : HRA.Config_Support.String_Vectors.Vector;
   Registry     : HRA.Envelope.Envelope_Registry;
   Registry_Diag : HRA.Config_Support.Config_Diagnostic;
   History      : HRA.Entitlement_Journal.Entitlement_History;
   Diag         : HRA.Entitlement_Journal.Admission_Diagnostic;
   Food         : HRA.Envelope.Envelope_Id;
   Daily        : HRA.Envelope.Envelope_Id;
   JPY          : constant Commodity := Make_Commodity ("JPY");

begin
   Put_Line ("--- Testing native Entitlement observation horizon ---");

   Names.Append ("food");
   Names.Append ("daily");
   Assert
     (HRA.Envelope.Admit_Registry (Names, Registry, Registry_Diag),
      "admit stable Envelope registry");
   Assert
     (HRA.Envelope.Lookup (Registry, "food", Food)
      and then HRA.Envelope.Lookup (Registry, "daily", Daily),
      "resolve Envelope identities");
   Assert
     (HRA.Entitlement_Journal.Admit (Source, Registry, History, Diag),
      "admit native entitlement.journal history");

   declare
      Obs : constant HRA.Envelope_Entitlement.Entitlement_Observation :=
        HRA.Entitlement_Journal.Observe (History, D ("2026-07-30"));
   begin
      Assert
        (not HRA.Envelope_Entitlement.Has_Origin (Obs, JPY)
         and then Is_Zero_Balance
           (HRA.Envelope_Entitlement.Entitlement_For (Obs, Food))
         and then Is_Zero_Balance
           (HRA.Envelope_Entitlement.Entitlement_For (Obs, Daily)),
         "origin and stock are absent before the source epoch");
   end;

   declare
      Obs : constant HRA.Envelope_Entitlement.Entitlement_Observation :=
        HRA.Entitlement_Journal.Observe (History, D ("2026-08-01"));
   begin
      Assert
        (HRA.Envelope_Entitlement.Has_Origin (Obs, JPY)
         and then HRA.Dates.Image
           (HRA.Envelope_Entitlement.Origin_For (Obs, JPY)) = "2026-07-31",
         "explicit origin becomes visible at and after its date");
      Assert
        (Lookup_Balance
           (HRA.Envelope_Entitlement.Entitlement_For (Obs, Food), JPY) = 10000.0
         and then Is_Zero_Balance
           (HRA.Envelope_Entitlement.Entitlement_For (Obs, Daily))
         and then Lookup_Balance
           (HRA.Envelope_Entitlement.Unallocated_Balance (Obs), JPY) = -10000.0,
         "future transfer does not leak into an earlier observation");
   end;

   declare
      Obs : constant HRA.Envelope_Entitlement.Entitlement_Observation :=
        HRA.Entitlement_Journal.Observe (History, D ("2026-08-02"));
   begin
      Assert
        (Lookup_Balance
           (HRA.Envelope_Entitlement.Entitlement_For (Obs, Food), JPY) = 8000.0
         and then Lookup_Balance
           (HRA.Envelope_Entitlement.Entitlement_For (Obs, Daily), JPY) = 2000.0,
         "transfer becomes visible on its own observation day");
   end;

   Put_Line
     (Natural'Image (Passed_Count) & " passed, " &
      Natural'Image (Failed_Count) & " failed");

   if Failed_Count > 0 then
      raise Program_Error with "native Entitlement horizon tests failed";
   end if;
end Test_Entitlement_Observation_Horizon;
