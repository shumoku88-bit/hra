with Ada.Command_Line;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO; use Ada.Text_IO;
with HRA.Account;
with HRA.Daily_Target_Scope;
with HRA.Household_Config;
with HRA.Journal;
with HRA.Journal_Evidence;
with HRA.Ledger;
with HRA.Money;
with HRA.Plan;
with HRA.Plan_Admission;

procedure Test_Daily_Target_Scope is
   use type HRA.Daily_Target_Scope.Admission_Status;
   use type HRA.Money.Quantity;

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

   function Make_Registry return HRA.Account.Account_Registry is
      Result : HRA.Account.Account_Registry := HRA.Account.Empty_Registry;
      Status : HRA.Account.Registry_Status;
   begin
      if not HRA.Account.Register_Account
        (Result,
         HRA.Account.Declare_Account
           (HRA.Account.Make_Account ("assets:cash"), HRA.Account.Asset),
         Status)
        or else not HRA.Account.Register_Account
          (Result,
           HRA.Account.Declare_Account
             (HRA.Account.Make_Account ("expenses:rent"), HRA.Account.Expense),
           Status)
        or else not HRA.Account.Register_Account
          (Result,
           HRA.Account.Declare_Account
             (HRA.Account.Make_Account ("expenses:food"), HRA.Account.Expense),
           Status)
        or else not HRA.Account.Register_Account
          (Result,
           HRA.Account.Declare_Account
             (HRA.Account.Make_Account ("expenses:household"),
              HRA.Account.Expense),
           Status)
      then
         raise Program_Error with "registry setup failed";
      end if;
      return Result;
   end Make_Registry;

   function Admit_Plans (Source : String) return HRA.Plan_Admission.Plan_Journal is
      L             : HRA.Ledger.Ledger;
      Parse_Error   : Unbounded_String;
      Evidence      : HRA.Journal_Evidence.Journal_Evidence;
      Evidence_Diag : HRA.Journal_Evidence.Evidence_Diagnostic;
      Result        : HRA.Plan_Admission.Plan_Journal;
      Diag          : HRA.Plan_Admission.Admission_Diagnostic;
   begin
      if not HRA.Journal.Parse_Journal_Text (Source, L, Parse_Error)
        or else not HRA.Journal_Evidence.Extract
          (Source, L, Evidence, Evidence_Diag)
        or else not HRA.Plan_Admission.Admit (L, Evidence, Result, Diag)
      then
         raise Program_Error with "Plan setup admission failed";
      end if;
      return Result;
   end Admit_Plans;

   function Policy_With_Asset
     (ID_Text : String := "cash-scope")
      return HRA.Household_Config.Household_Configuration
   is
      Result : HRA.Household_Config.Household_Configuration;
   begin
      Result.Daily_Target_Assets.Append
        (HRA.Household_Config.Daily_Target_Asset'
           (ID      => To_Unbounded_String (ID_Text),
            Account => To_Unbounded_String ("assets:cash")));
      return Result;
   end Policy_With_Asset;

   Registry : constant HRA.Account.Account_Registry := Make_Registry;

   Good_Source : constant String :=
     "2026-08-25 Rent" & ASCII.LF &
     "    ; plan-id: rent" & ASCII.LF &
     "    ; daily-target-id: rent-obligation" & ASCII.LF &
     "    ; reservation-id: rent-buffer" & ASCII.LF &
     "    ; reservation-amount: 40" & ASCII.LF &
     "    ; reservation-commodity: JPY" & ASCII.LF &
     "    assets:cash       -100 JPY" & ASCII.LF &
     "    expenses:rent      100 JPY" & ASCII.LF & ASCII.LF &
     "2026-08-26 Ordinary split" & ASCII.LF &
     "    ; plan-id: split" & ASCII.LF &
     "    assets:cash       -100 JPY" & ASCII.LF &
     "    expenses:food       60 JPY" & ASCII.LF &
     "    expenses:household  40 JPY" & ASCII.LF;

begin
   Put_Line ("--- Testing HRA.Daily_Target_Scope ---");

   declare
      Scope  : HRA.Daily_Target_Scope.Scope;
      Diag   : HRA.Daily_Target_Scope.Admission_Diagnostic;
      Plans  : constant HRA.Plan_Admission.Plan_Journal :=
        Admit_Plans (Good_Source);
      Policy : constant HRA.Household_Config.Household_Configuration :=
        Policy_With_Asset;
      OK : constant Boolean := HRA.Daily_Target_Scope.Admit
        (Policy, Registry, Plans, Scope, Diag);
   begin
      Assert (OK, "eligible Asset plus selected outgoing Plan admits");
      if OK then
         Assert
           (HRA.Daily_Target_Scope.Is_Configured (Scope)
              and then HRA.Daily_Target_Scope.Eligible_Asset_Count (Scope) = 1,
            "scope retains long-lived eligible Asset policy");

         if HRA.Daily_Target_Scope.Eligible_Asset_Count (Scope) = 1 then
            Assert
              (HRA.Account.Name
                 (HRA.Daily_Target_Scope.Eligible_Asset_At (Scope, 1)) =
                   "assets:cash",
               "eligible Asset is exposed through opaque source-order access");
         end if;

         Assert
           (HRA.Daily_Target_Scope.Obligation_Count (Scope) = 1,
            "unselected multi-post Plan remains outside Daily Target");

         if HRA.Daily_Target_Scope.Obligation_Count (Scope) = 1 then
            declare
               O : constant HRA.Daily_Target_Scope.Obligation :=
                 HRA.Daily_Target_Scope.Obligation_At (Scope, 1);
            begin
               Assert
                 (HRA.Plan.Text (O.Plan_ID) = "rent",
                  "selected Plan identity remains attached to obligation");
               Assert
                 (O.Amount.Val = 100.0
                    and then HRA.Money.Code (O.Amount.Comm) = "JPY",
                  "selected outgoing obligation retains exact positive amount");
               Assert
                 (O.Reservation.Present
                    and then O.Reservation.Value.Amount.Val = 40.0
                    and then HRA.Money.Code
                      (O.Reservation.Value.Amount.Comm) = "JPY",
                  "reservation remains distinct exact evidence");
            end;
         end if;
      end if;
   end;

   declare
      Scope  : HRA.Daily_Target_Scope.Scope;
      Diag   : HRA.Daily_Target_Scope.Admission_Diagnostic;
      Plans  : constant HRA.Plan_Admission.Plan_Journal := Admit_Plans
        ("2026-08-25 Duplicate identity" & ASCII.LF &
         "    ; plan-id: rent" & ASCII.LF &
         "    ; daily-target-id: cash-scope" & ASCII.LF &
         "    assets:cash       -100 JPY" & ASCII.LF &
         "    expenses:rent      100 JPY" & ASCII.LF);
      Policy : constant HRA.Household_Config.Household_Configuration :=
        Policy_With_Asset ("cash-scope");
      OK : constant Boolean := HRA.Daily_Target_Scope.Admit
        (Policy, Registry, Plans, Scope, Diag);
   begin
      Assert
        (not OK
           and then Diag.Status = HRA.Daily_Target_Scope.Duplicate_Selection_Id,
         "selection identity is unique across household and Plan declarations");
   end;

   declare
      Scope  : HRA.Daily_Target_Scope.Scope;
      Diag   : HRA.Daily_Target_Scope.Admission_Diagnostic;
      Plans  : constant HRA.Plan_Admission.Plan_Journal := Admit_Plans
        ("2026-08-25 Over reservation" & ASCII.LF &
         "    ; plan-id: rent" & ASCII.LF &
         "    ; daily-target-id: rent-obligation" & ASCII.LF &
         "    ; reservation-id: rent-buffer" & ASCII.LF &
         "    ; reservation-amount: 120" & ASCII.LF &
         "    ; reservation-commodity: JPY" & ASCII.LF &
         "    assets:cash       -100 JPY" & ASCII.LF &
         "    expenses:rent      100 JPY" & ASCII.LF);
      Policy : constant HRA.Household_Config.Household_Configuration :=
        Policy_With_Asset;
      OK : constant Boolean := HRA.Daily_Target_Scope.Admit
        (Policy, Registry, Plans, Scope, Diag);
   begin
      Assert
        (not OK
           and then Diag.Status =
             HRA.Daily_Target_Scope.Reservation_Exceeds_Obligation,
         "reservation is rejected instead of clamped when it exceeds obligation");
   end;

   declare
      Scope  : HRA.Daily_Target_Scope.Scope;
      Diag   : HRA.Daily_Target_Scope.Admission_Diagnostic;
      Plans  : constant HRA.Plan_Admission.Plan_Journal := Admit_Plans
        ("2026-08-25 Stray reservation" & ASCII.LF &
         "    ; plan-id: rent" & ASCII.LF &
         "    ; reservation-id: rent-buffer" & ASCII.LF &
         "    ; reservation-amount: 40" & ASCII.LF &
         "    ; reservation-commodity: JPY" & ASCII.LF &
         "    assets:cash       -100 JPY" & ASCII.LF &
         "    expenses:rent      100 JPY" & ASCII.LF);
      Policy : constant HRA.Household_Config.Household_Configuration :=
        Policy_With_Asset;
      OK : constant Boolean := HRA.Daily_Target_Scope.Admit
        (Policy, Registry, Plans, Scope, Diag);
   begin
      Assert
        (not OK
           and then Diag.Status =
             HRA.Daily_Target_Scope.Reservation_Without_Selection,
         "reservation metadata cannot create an implicit Daily Target selection");
   end;

   declare
      Scope  : HRA.Daily_Target_Scope.Scope;
      Diag   : HRA.Daily_Target_Scope.Admission_Diagnostic;
      Plans  : constant HRA.Plan_Admission.Plan_Journal := Admit_Plans
        ("2026-08-25 Selected split" & ASCII.LF &
         "    ; plan-id: split" & ASCII.LF &
         "    ; daily-target-id: split-obligation" & ASCII.LF &
         "    assets:cash       -100 JPY" & ASCII.LF &
         "    expenses:food       60 JPY" & ASCII.LF &
         "    expenses:household  40 JPY" & ASCII.LF);
      Policy : constant HRA.Household_Config.Household_Configuration :=
        Policy_With_Asset;
      OK : constant Boolean := HRA.Daily_Target_Scope.Admit
        (Policy, Registry, Plans, Scope, Diag);
   begin
      Assert
        (not OK
           and then Diag.Status =
             HRA.Daily_Target_Scope.Unsupported_Selected_Plan_Shape,
         "only explicitly selected Plans cross the narrow outgoing boundary");
   end;

   declare
      Scope  : HRA.Daily_Target_Scope.Scope;
      Diag   : HRA.Daily_Target_Scope.Admission_Diagnostic;
      Plans  : constant HRA.Plan_Admission.Plan_Journal :=
        Admit_Plans
          ("2026-08-26 Ordinary split" & ASCII.LF &
           "    ; plan-id: split" & ASCII.LF &
           "    assets:cash       -100 JPY" & ASCII.LF &
           "    expenses:food       60 JPY" & ASCII.LF &
           "    expenses:household  40 JPY" & ASCII.LF);
      Policy : HRA.Household_Config.Household_Configuration;
      OK : constant Boolean := HRA.Daily_Target_Scope.Admit
        (Policy, Registry, Plans, Scope, Diag);
   begin
      Assert
        (OK and then not HRA.Daily_Target_Scope.Is_Configured (Scope),
         "absent Daily Target policy remains an explicit empty scope");
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
end Test_Daily_Target_Scope;
