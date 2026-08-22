with System;

package HRA.Writer.Test_Hooks is

   procedure Set_After_Stage_Hook (Hook_Address : System.Address);
   procedure Clear_After_Stage_Hook;
   procedure Notify_Staged (Staged_Path : String);

   --  Test-only hook immediately after Writer has atomically replaced the root
   --  with its candidate and before guarded-source post-publication fencing.
   procedure Set_After_Publish_Hook (Hook_Address : System.Address);
   procedure Clear_After_Publish_Hook;
   procedure Notify_Published (Target_Path : String);

end HRA.Writer.Test_Hooks;
