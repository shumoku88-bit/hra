with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

package HRA.Writer is

   --  ========================================================================
   --  Typed Publication Coordinates
   --  ========================================================================

   type Source_Presence is (Absent, Present);

   --  The complete source snapshot that the caller/operation observed before mutation.
   --  Presence is part of the premise: an absent path and a present zero-byte file
   --  are distinct observations even though both expose an empty text payload.
   type Expected_Source is private;

   --  The complete source proposed for publication after operation preparation.
   --  Represents proposed mutation bytes, pending validation and publication.
   type Candidate_Source is private;

   function Make_Expected_Source (Text : String) return Expected_Source;
   function Make_Expected_Source
     (Text : Ada.Strings.Unbounded.Unbounded_String) return Expected_Source;
   function Make_Absent_Expected_Source return Expected_Source;

   --  Observe the target publication premise from the filesystem without text
   --  normalization. CRLF, LF, and trailing-newline presence are retained byte-for-byte.
   function Observe_Source
     (Target_Path : String;
      Observed    : out Expected_Source;
      Error_Msg   : out Unbounded_String) return Boolean
     with Pre => Target_Path'Length > 0;

   function Presence_Of (Value : Expected_Source) return Source_Presence;

   function Make_Candidate_Source (Text : String) return Candidate_Source;
   function Make_Candidate_Source
     (Text : Ada.Strings.Unbounded.Unbounded_String) return Candidate_Source;

   function Source_Text (Value : Expected_Source) return String;
   function Source_Text (Value : Candidate_Source) return String;

   function Unbounded_Text
     (Value : Expected_Source) return Ada.Strings.Unbounded.Unbounded_String;
   function Unbounded_Text
     (Value : Candidate_Source) return Ada.Strings.Unbounded.Unbounded_String;

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
     (Target_Path : String;
      Expected    : Expected_Source;
      Candidate   : Candidate_Source;
      Status      : out Writer_Status;
      Error_Msg   : out Unbounded_String) return Boolean
     with Pre => Target_Path'Length > 0,
          Post => (if Atomic_Publish_Journal'Result then Status = Success);

   function Append_Transaction_Safely
     (Target_Path : String;
      New_Tx_Text : String;
      Status      : out Writer_Status;
      Error_Msg   : out Unbounded_String) return Boolean
     with Pre => Target_Path'Length > 0 and then New_Tx_Text'Length > 0,
          Post => (if Append_Transaction_Safely'Result then Status = Success);

private

   type Expected_Source is record
      State : Source_Presence := Absent;
      Text  : Ada.Strings.Unbounded.Unbounded_String :=
        Ada.Strings.Unbounded.Null_Unbounded_String;
   end record;

   type Candidate_Source is record
      Text : Ada.Strings.Unbounded.Unbounded_String :=
        Ada.Strings.Unbounded.Null_Unbounded_String;
   end record;

end HRA.Writer;
