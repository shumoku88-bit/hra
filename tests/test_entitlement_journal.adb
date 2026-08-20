with Ada.Command_Line;
with Ada.Text_IO; use Ada.Text_IO;
with HRA.Config_Support;
with HRA.Dates;
with HRA.Envelope;
with HRA.Entitlement_Journal;
with HRA.Envelope_Entitlement;
with HRA.Money; use HRA.Money;

procedure Test_Entitlement_Journal is
   use HRA.Envelope;
   use HRA.Entitlement_Journal;

   Passed_Count : Natural := 0;
   Failed_Count : Natural := 0;

   procedure Check (Condition : Boolean; Message : String) is
   begin
      if Condition then
         Put_Line ("[PASS] " & Message);
         Passed_Count := Passed_Count + 1;
      else
         Put_Line ("[FAIL] " & Message);
         Failed_Count := Failed_Count + 1;
      end if;
   end Check;

   function D (Text : String) return HRA.Dates.Date is
      Value  : HRA.Dates.Date;
      Status : HRA.Dates.Date_Status;
   begin
      if not HRA.Dates.Parse (Text, Value, Status) then
         raise Program_Error with "invalid test date: " & Text;
      end if;
      return Value;
   end D;

   procedure Check_Rejected
     (Text     : String;
      Expected : Admission_Status;
      Message  : String;
      Registry : Envelope_Registry)
   is
      History : Entitlement_History;
      Diag    : Admission_Diagnostic;
   begin
      Check
        (not Admit (Text, Registry, History, Diag)
         and then Diag.Status = Expected,
         Message);
   end Check_Rejected;

   IDs           : HRA.Config_Support.String_Vectors.Vector;
   Registry      : Envelope_Registry;
   Registry_Diag : HRA.Config_Support.Config_Diagnostic;
   History       : Entitlement_History;
   Diag          : Admission_Diagnostic;
   JPY           : constant Commodity := Make_Commodity ("JPY");
   Food          : Envelope_Id;
   Daily         : Envelope_Id;
   Food_Status   : Envelope_Id_Status;
   Daily_Status  : Envelope_Id_Status;
   Text          : constant String :=
     "2026-08-17 origin JPY ; clean epoch" & ASCII.LF &
     "2026-08-17 transfer unallocated -> food 100 JPY" & ASCII.LF &
     "2026-08-18 transfer food -> unallocated 25 JPY" & ASCII.LF;

begin
   Put_Line ("--- Testing HRA.Entitlement_Journal ---");

   IDs.Append ("food");
   IDs.Append ("daily");
   Check
     (Admit_Registry (IDs, Registry, Registry_Diag),
      "admit stable Envelope registry");
   Check
     (Admit (Text, Registry, History, Diag),
      "admit native entitlement.journal");
   Check (Movement_Count (History) = 2, "retain two native movements");
   Check
     (Create_Envelope_Id ("food", Food, Food_Status),
      "construct admitted food Envelope id");
   Check
     (Create_Envelope_Id ("daily", Daily, Daily_Status),
      "construct admitted daily Envelope id");

   declare
      At_Origin : constant HRA.Envelope_Entitlement.Entitlement_Observation :=
        Observe (History, D ("2026-08-17"));
      After_Return : constant HRA.Envelope_Entitlement.Entitlement_Observation :=
        Observe (History, D ("2026-08-18"));
   begin
      Check
        (Lookup_Balance
           (HRA.Envelope_Entitlement.Entitlement_For (At_Origin, Food), JPY) = 100.0,
         "observe grant at origin day");
      Check
        (Lookup_Balance
           (HRA.Envelope_Entitlement.Entitlement_For (After_Return, Food), JPY) = 75.0,
         "observe later return");
   end;

   Check_Rejected
     ("2026-08-17 origin JPY" & ASCII.LF &
      "2026-08-17 transfer unallocated -> missing 1 JPY" & ASCII.LF,
      Unknown_Envelope,
      "reject unknown Envelope endpoint",
      Registry);

   Check_Rejected
     ("2026-08-17 transfer unallocated -> food 1 JPY" & ASCII.LF,
      Missing_Origin,
      "require explicit stock origin for every transferred Commodity",
      Registry);

   Check_Rejected
     ("2026-08-17 transfer unallocated -> food 1 JPY" & ASCII.LF &
      "2026-08-18 origin JPY" & ASCII.LF,
      Origin_After_Transfer,
      "reject origin later than a transfer",
      Registry);

   Check_Rejected
     ("2026-08-17 origin JPY" & ASCII.LF &
      "2026-08-18 origin JPY" & ASCII.LF,
      Duplicate_Origin,
      "reject duplicate Commodity origin",
      Registry);

   Check_Rejected
     ("2026-08-17 origin JPY" & ASCII.LF &
      "2026-08-18 transfer food -> food 1 JPY" & ASCII.LF,
      Same_Endpoint,
      "reject transfer with identical endpoints",
      Registry);

   Check_Rejected
     ("2026-08-17 origin JPY" & ASCII.LF &
      "2026-08-18 transfer unallocated -> food 0 JPY" & ASCII.LF,
      Non_Positive_Quantity,
      "reject zero transfer Quantity",
      Registry);

   Check_Rejected
     ("2026-08-17 origin JPY" & ASCII.LF &
      "2026-08-18 transfer unallocated -> food 50 JPY" & ASCII.LF &
      "2026-08-19 transfer food -> daily 60 JPY" & ASCII.LF,
      Negative_Envelope_Stock,
      "reject cumulative negative spendable Envelope stock",
      Registry);

   declare
      Same_Day_History : Entitlement_History;
      Same_Day_Diag    : Admission_Diagnostic;
      Same_Day_Text    : constant String :=
        "2026-08-17 origin JPY" & ASCII.LF &
        "2026-08-18 transfer food -> daily 100 JPY" & ASCII.LF &
        "2026-08-18 transfer unallocated -> food 100 JPY" & ASCII.LF;
   begin
      Check
        (Admit (Same_Day_Text, Registry, Same_Day_History, Same_Day_Diag),
         "combine same-day effects before nonnegative stock validation");
      if Same_Day_Diag.Status = Success then
         declare
            Obs : constant HRA.Envelope_Entitlement.Entitlement_Observation :=
              Observe (Same_Day_History, D ("2026-08-18"));
         begin
            Check
              (Is_Zero_Balance
                 (HRA.Envelope_Entitlement.Entitlement_For (Obs, Food))
               and then Lookup_Balance
                 (HRA.Envelope_Entitlement.Entitlement_For (Obs, Daily), JPY) = 100.0,
               "same-day source order does not invent transient negative stock");
         end;
      end if;
   end;

   New_Line;
   Put_Line
     ("Summary: Passed =" & Natural'Image (Passed_Count) &
      ", Failed =" & Natural'Image (Failed_Count));

   if Failed_Count > 0 then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   else
      Put_Line ("RESULT: SUCCESS");
   end if;
end Test_Entitlement_Journal;
