with Ada.Unchecked_Conversion;
with System; use type System.Address;

package body HRA.Writer.Test_Hooks is

   type Hook_Ptr is access procedure (Path : String);
   function To_Ptr is new Ada.Unchecked_Conversion (System.Address, Hook_Ptr);

   Current_After_Stage_Addr   : System.Address := System.Null_Address;
   Current_After_Publish_Addr : System.Address := System.Null_Address;

   procedure Set_After_Stage_Hook (Hook_Address : System.Address) is
   begin
      Current_After_Stage_Addr := Hook_Address;
   end Set_After_Stage_Hook;

   procedure Clear_After_Stage_Hook is
   begin
      Current_After_Stage_Addr := System.Null_Address;
   end Clear_After_Stage_Hook;

   procedure Notify_Staged (Staged_Path : String) is
   begin
      if Current_After_Stage_Addr /= System.Null_Address then
         declare
            H : constant Hook_Ptr := To_Ptr (Current_After_Stage_Addr);
         begin
            H.all (Staged_Path);
         end;
      end if;
   end Notify_Staged;

   procedure Set_After_Publish_Hook (Hook_Address : System.Address) is
   begin
      Current_After_Publish_Addr := Hook_Address;
   end Set_After_Publish_Hook;

   procedure Clear_After_Publish_Hook is
   begin
      Current_After_Publish_Addr := System.Null_Address;
   end Clear_After_Publish_Hook;

   procedure Notify_Published (Target_Path : String) is
   begin
      if Current_After_Publish_Addr /= System.Null_Address then
         declare
            H : constant Hook_Ptr := To_Ptr (Current_After_Publish_Addr);
         begin
            H.all (Target_Path);
         end;
      end if;
   end Notify_Published;

end HRA.Writer.Test_Hooks;
