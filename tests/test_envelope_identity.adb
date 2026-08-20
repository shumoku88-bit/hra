with Ada.Text_IO; use Ada.Text_IO;
with HRA.Account;
with HRA.Config_Support;
with HRA.Envelope;

procedure Test_Envelope_Identity is
   use type HRA.Envelope.Envelope_Id_Status;

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

   Id     : HRA.Envelope.Envelope_Id;
   Status : HRA.Envelope.Envelope_Id_Status;
   Food_UTF8 : constant String :=
     Character'Val (16#E9#) & Character'Val (16#A3#) & Character'Val (16#9F#) &
     Character'Val (16#E8#) & Character'Val (16#B2#) & Character'Val (16#BB#);

begin
   Put_Line ("--- Testing focused Envelope identity laws ---");

   Assert
     (HRA.Envelope.Create_Envelope_Id ("food", Id, Status)
        and then Status = HRA.Envelope.Success
        and then HRA.Envelope.Image (Id) = "food",
      "valid Envelope identity round-trips exactly");
   Assert
     (HRA.Envelope.Create_Envelope_Id (Food_UTF8, Id, Status)
        and then Status = HRA.Envelope.Success
        and then HRA.Envelope.Image (Id) = Food_UTF8,
      "UTF-8 Envelope identity bytes round-trip exactly");
   Assert
     (not HRA.Envelope.Create_Envelope_Id ("", Id, Status)
        and then Status = HRA.Envelope.Empty_Identity,
      "empty Envelope identity is rejected");
   Assert
     (not HRA.Envelope.Create_Envelope_Id (" food", Id, Status)
        and then Status = HRA.Envelope.Leading_Or_Trailing_Whitespace,
      "leading Envelope whitespace is rejected");
   Assert
     (not HRA.Envelope.Create_Envelope_Id ("food ", Id, Status)
        and then Status = HRA.Envelope.Leading_Or_Trailing_Whitespace,
      "trailing Envelope whitespace is rejected");
   Assert
     (not HRA.Envelope.Create_Envelope_Id ("fo" & ASCII.NUL & "od", Id, Status)
        and then Status = HRA.Envelope.Identity_Contains_Control,
      "Envelope control characters are rejected");
   Assert
     (HRA.Envelope.Create_Envelope_Id ("food:stock", Id, Status)
        and then HRA.Envelope.Image (Id) = "food:stock",
      "stable Envelope identity may contain an internal colon");

   declare
      Env : HRA.Envelope.Envelope_Id;
      Acc : constant HRA.Account.Account := HRA.Account.Make_Account ("food");
   begin
      Assert
        (HRA.Envelope.Create_Envelope_Id ("food", Env, Status)
           and then HRA.Envelope.Image (Env) = HRA.Account.Name (Acc),
         "Envelope and Account may share surface text without sharing a type");
   end;

   declare
      Names    : HRA.Config_Support.String_Vectors.Vector;
      Registry : HRA.Envelope.Envelope_Registry;
      Diag     : HRA.Config_Support.Config_Diagnostic;
      Food     : HRA.Envelope.Envelope_Id;
   begin
      Names.Append ("food");
      Names.Append ("daily");
      Names.Append ("food:stock");
      Assert
        (HRA.Envelope.Admit_Registry (Names, Registry, Diag)
           and then HRA.Envelope.Length (Registry) = 3,
         "stable Envelope registry admits distinct identities");
      Assert
        (HRA.Envelope.Contains (Registry, "food")
           and then HRA.Envelope.Lookup (Registry, "food", Food)
           and then HRA.Envelope.Image (Food) = "food",
         "registry lookup preserves admitted stable identity");
      Assert
        (not HRA.Envelope.Contains (Registry, "retired-unknown")
           and then not HRA.Envelope.Lookup (Registry, "retired-unknown", Food),
         "unadmitted Envelope identity is not invented by lookup");

      declare
         IDs : constant HRA.Envelope.Envelope_Id_Array :=
           HRA.Envelope.All_Ids (Registry);
      begin
         Assert
           (IDs'Length = 3
              and then HRA.Envelope.Image (IDs (1)) = "daily"
              and then HRA.Envelope.Image (IDs (2)) = "food"
              and then HRA.Envelope.Image (IDs (3)) = "food:stock",
            "registry exposes one canonical identity order");
      end;
   end;

   declare
      Names    : HRA.Config_Support.String_Vectors.Vector;
      Registry : HRA.Envelope.Envelope_Registry;
      Diag     : HRA.Config_Support.Config_Diagnostic;
   begin
      Assert
        (not HRA.Envelope.Admit_Registry (Names, Registry, Diag),
         "empty stable Envelope registry fails closed");

      Names.Append ("valid");
      Names.Append ("");
      Assert
        (not HRA.Envelope.Admit_Registry (Names, Registry, Diag),
         "registry containing an invalid identity fails closed");

      Names.Clear;
      Names.Append ("food");
      Names.Append ("food");
      Assert
        (not HRA.Envelope.Admit_Registry (Names, Registry, Diag),
         "duplicate Envelope identities fail closed");
   end;

   Put_Line
     (Natural'Image (Passed_Count) & " passed, " &
      Natural'Image (Failed_Count) & " failed");
   if Failed_Count > 0 then
      raise Program_Error with "Envelope identity tests failed";
   end if;
end Test_Envelope_Identity;
