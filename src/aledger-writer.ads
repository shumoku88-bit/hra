with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

package ALedger.Writer is

   --  ========================================================================
   --  Safe Writer Laws: Atomic Publication, Backup, Stale Check, Restore
   --  ========================================================================

   type Writer_Status is
     (Success,
      Stale_Source_Rejected,
      Pre_Admission_Failed,
      Backup_Failed,
      File_Write_Failed,
      Post_Admission_Failed);

   function Writer_Status_Image (Status : Writer_Status) return String;

   function Atomic_Publish_Journal
     (Target_Path       : String;
      Expected_Old_Text : String;
      New_Text          : String;
      Status            : out Writer_Status;
      Error_Msg         : out Unbounded_String) return Boolean
     with Pre => Target_Path'Length > 0,
          Post => (if Atomic_Publish_Journal'Result then Status = Success);

   function Append_Transaction_Safely
     (Target_Path : String;
      New_Tx_Text : String;
      Status      : out Writer_Status;
      Error_Msg   : out Unbounded_String) return Boolean
     with Pre => Target_Path'Length > 0 and then New_Tx_Text'Length > 0,
          Post => (if Append_Transaction_Safely'Result then Status = Success);

end ALedger.Writer;
