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

   Failed : Boolean := False;

   procedure Check (Condition : Boolean; Message : String) is
   begin
      if Condition then
         Put_Line ("[PASS] " & Message);
      else
         Put_Line ("[FAIL] " & Message);
         Failed := True;
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

   IDs : HRA.Config_Support.String_Vectors.Vector;
   Registry : Envelope_Registry;
   Registry_Diag : HRA.Config_Support.Config_Diagnostic;
   History : Entitlement_History;
   Diag : Admission_Diagnostic;
   JPY : constant Commodity := Make_Commodity ("JPY");
   Food : Envelope_Id;
   Food_Status : Envelope_Id_Status;
   Text : constant String :=
     "2026-08-17 origin JPY ; clean epoch" & ASCII.LF &
     "2026-08-17 transfer unallocated -> food 100 JPY" & ASCII.LF &
     "2026-08-18 transfer food -> unallocated 25 JPY" & ASCII.LF;
begin
   IDs.Append ("food");
   Check
     (Admit_Registry (IDs, Registry, Registry_Diag),
      "admit stable Envelope registry");
   Check
     (Admit (Text, Registry, History, Diag),
      "admit native entitlement.journal");
   Check (Movement_Count (History) = 2, "retain two native movements");
   Check
     (Create_Envelope_Id ("food", Food, Food_Status),
      "construct admitted Envelope id");

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

   declare
      Bad_History : Entitlement_History;
      Bad_Diag : Admission_Diagnostic;
      Bad_Text : constant String :=
        "2026-08-17 origin JPY" & ASCII.LF &
        "2026-08-17 transfer unallocated -> missing 1 JPY" & ASCII.LF;
   begin
      Check
        (not Admit (Bad_Text, Registry, Bad_History, Bad_Diag)
         and then Bad_Diag.Status = Unknown_Envelope,
         "reject unknown Envelope endpoint");
   end;

   if Failed then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Test_Entitlement_Journal;
