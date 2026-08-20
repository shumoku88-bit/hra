with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO; use Ada.Text_IO;
with HRA.Account;
with HRA.Config_Support;
with HRA.Dates;
with HRA.Envelope;
with HRA.Envelope_Routing;

procedure Test_Envelope_Routing is
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

   function D (Text : String) return HRA.Dates.Date is
      Value  : HRA.Dates.Date;
      Status : HRA.Dates.Date_Status;
   begin
      if not HRA.Dates.Parse (Text, Value, Status) then
         raise Program_Error with "invalid synthetic date";
      end if;
      return Value;
   end D;

   Names    : HRA.Config_Support.String_Vectors.Vector;
   Registry : HRA.Envelope.Envelope_Registry;
   Env_Diag : HRA.Config_Support.Config_Diagnostic;
   Food     : HRA.Envelope.Envelope_Id;
   Daily    : HRA.Envelope.Envelope_Id;
   Food_Expense : constant HRA.Account.Account :=
     HRA.Account.Make_Account ("expenses:food");
   Rent_Expense : constant HRA.Account.Account :=
     HRA.Account.Make_Account ("expenses:rent");

begin
   Put_Line ("--- Testing focused Envelope routing laws ---");

   Names.Append ("food");
   Names.Append ("daily");
   Assert
     (HRA.Envelope.Admit_Registry (Names, Registry, Env_Diag),
      "setup admits stable Envelope identities");
   Assert
     (HRA.Envelope.Lookup (Registry, "food", Food)
        and then HRA.Envelope.Lookup (Registry, "daily", Daily),
      "setup resolves admitted Envelope identities");

   declare
      Entries : HRA.Envelope_Routing.Routing_Entry_Vectors.Vector;
      History : HRA.Envelope_Routing.Routing_History;
      Status  : HRA.Envelope_Routing.History_Status;
   begin
      Entries.Append
        (HRA.Envelope_Routing.Routing_Entry'
           (Effective => HRA.Envelope_Routing.Initial_Effective_Date,
            Expense   => Food_Expense,
            Route     => HRA.Envelope_Routing.Managed_Route (Food),
            Note      => To_Unbounded_String ("initial food intent")));
      Entries.Append
        (HRA.Envelope_Routing.Routing_Entry'
           (Effective => HRA.Envelope_Routing.Dated_Effective (D ("2026-09-01")),
            Expense   => Food_Expense,
            Route     => HRA.Envelope_Routing.Managed_Route (Daily),
            Note      => To_Unbounded_String ("later intent change")));
      Entries.Append
        (HRA.Envelope_Routing.Routing_Entry'
           (Effective => HRA.Envelope_Routing.Initial_Effective_Date,
            Expense   => Rent_Expense,
            Route     => HRA.Envelope_Routing.Not_Managed_Route,
            Note      => Null_Unbounded_String));

      Assert
        (HRA.Envelope_Routing.Admit (Entries, Registry, History, Status)
           and then Status = HRA.Envelope_Routing.Success
           and then HRA.Envelope_Routing.Length (History) = 3,
         "routing history admits initial and dated decisions");

      declare
         Before : constant HRA.Envelope_Routing.Expense_Route :=
           HRA.Envelope_Routing.Resolve
             (History, Food_Expense, D ("2026-08-31"));
         On_Date : constant HRA.Envelope_Routing.Expense_Route :=
           HRA.Envelope_Routing.Resolve
             (History, Food_Expense, D ("2026-09-01"));
         Later : constant HRA.Envelope_Routing.Expense_Route :=
           HRA.Envelope_Routing.Resolve
             (History, Food_Expense, D ("2026-12-31"));
      begin
         Assert
           (Before.Kind = HRA.Envelope_Routing.Managed_By_Envelope
              and then HRA.Envelope.Image (Before.Target) = "food",
            "future routing does not rewrite earlier Household meaning");
         Assert
           (On_Date.Kind = HRA.Envelope_Routing.Managed_By_Envelope
              and then HRA.Envelope.Image (On_Date.Target) = "daily"
              and then Later.Kind = HRA.Envelope_Routing.Managed_By_Envelope
              and then HRA.Envelope.Image (Later.Target) = "daily",
            "dated routing takes effect on its own date and remains effective");
      end;

      Assert
        (HRA.Envelope_Routing.Resolve
           (History, Rent_Expense, D ("2026-08-15")).Kind =
             HRA.Envelope_Routing.Not_Envelope_Managed,
         "explicit not-managed decision remains distinct from Envelope routing");
      Assert
        (not HRA.Envelope_Routing.Has_Routing
           (History, HRA.Account.Make_Account ("expenses:unknown"))
           and then HRA.Envelope_Routing.Resolve
             (History,
              HRA.Account.Make_Account ("expenses:unknown"),
              D ("2026-08-15")).Kind =
                HRA.Envelope_Routing.Not_Envelope_Managed,
         "missing routing never invents an Envelope target");
   end;

   declare
      Entries : HRA.Envelope_Routing.Routing_Entry_Vectors.Vector;
      History : HRA.Envelope_Routing.Routing_History;
      Status  : HRA.Envelope_Routing.History_Status;
      Entry   : constant HRA.Envelope_Routing.Routing_Entry :=
        (Effective => HRA.Envelope_Routing.Initial_Effective_Date,
         Expense   => Food_Expense,
         Route     => HRA.Envelope_Routing.Managed_Route (Food),
         Note      => Null_Unbounded_String);
   begin
      Entries.Append (Entry);
      Entries.Append (Entry);
      Assert
        (not HRA.Envelope_Routing.Admit (Entries, Registry, History, Status)
           and then Status = HRA.Envelope_Routing.Duplicate_Routing_Entry,
         "duplicate routing coordinate fails closed");
   end;

   declare
      Entries : HRA.Envelope_Routing.Routing_Entry_Vectors.Vector;
      History : HRA.Envelope_Routing.Routing_History;
      Status  : HRA.Envelope_Routing.History_Status;
      Unknown : constant HRA.Envelope.Envelope_Id :=
        HRA.Envelope.Make_Envelope_Id ("unknown");
   begin
      Entries.Append
        (HRA.Envelope_Routing.Routing_Entry'
           (Effective => HRA.Envelope_Routing.Initial_Effective_Date,
            Expense   => Food_Expense,
            Route     => HRA.Envelope_Routing.Managed_Route (Unknown),
            Note      => Null_Unbounded_String));
      Assert
        (not HRA.Envelope_Routing.Admit (Entries, Registry, History, Status)
           and then Status = HRA.Envelope_Routing.Unknown_Envelope_In_Route,
         "routing to an unadmitted Envelope fails closed");
   end;

   Put_Line
     (Natural'Image (Passed_Count) & " passed, " &
      Natural'Image (Failed_Count) & " failed");
   if Failed_Count > 0 then
      raise Program_Error with "Envelope routing tests failed";
   end if;
end Test_Envelope_Routing;
