with System;

package HRA.Writer.Test_Hooks is

   procedure Set_After_Stage_Hook (Hook_Address : System.Address);
   procedure Clear_After_Stage_Hook;
   procedure Notify_Staged (Staged_Path : String);

end HRA.Writer.Test_Hooks;
