with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

package ALedger.Writer is

   --  ========================================================================
   --  Safe Writer Laws: Atomic Publication, Backup, Stale Check, Restore
   --  ========================================================================

   type Writer_Status is
     (Success,
      Stale_Source_Rejected,
      Backup_Failed,
      File_Write_Failed,
      Post_Admission_Failed);

   function Writer_Status_Image (Status : Writer_Status) return String;

   function Atomic_Publish_Journal
     (Target_Path       : String;
      Expected_Old_Text : String;
      New_Text          : String;
      Status            : out Writer_Status;
      Error_Msg         : out Unbounded_String) return Boolean;

   function Append_Transaction_Safely
     (Target_Path : String;
      New_Tx_Text : String;
      Status      : out Writer_Status;
      Error_Msg   : out Unbounded_String) return Boolean;

end ALedger.Writer;
