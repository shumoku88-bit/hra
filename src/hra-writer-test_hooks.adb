with Ada.Unchecked_Conversion;
with System; use type System.Address;

package body HRA.Writer.Test_Hooks is

   type Hook_Ptr is access procedure (Staged_Path : String);
   function To_Ptr is new Ada.Unchecked_Conversion (System.Address, Hook_Ptr);

   Current_Hook_Addr : System.Address := System.Null_Address;

   procedure Set_After_Stage_Hook (Hook_Address : System.Address) is
   begin
      Current_Hook_Addr := Hook_Address;
   end Set_After_Stage_Hook;

   procedure Clear_After_Stage_Hook is
   begin
      Current_Hook_Addr := System.Null_Address;
   end Clear_After_Stage_Hook;

   procedure Notify_Staged (Staged_Path : String) is
   begin
      if Current_Hook_Addr /= System.Null_Address then
         declare
            H : constant Hook_Ptr := To_Ptr (Current_Hook_Addr);
         begin
            H.all (Staged_Path);
         end;
      end if;
   end Notify_Staged;

end HRA.Writer.Test_Hooks;
