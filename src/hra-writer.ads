with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

package HRA.Writer is

   --  ========================================================================
   --  Typed Publication Coordinates
   --  ========================================================================

   --  The complete source snapshot that the caller/operation observed before mutation.
   --  Represents the observed publication premise used for optimistic stale checking.
   type Expected_Source is private;

   --  The complete source proposed for publication after operation preparation.
   --  Represents proposed mutation bytes, pending validation and publication.
   type Candidate_Source is private;

   function Make_Expected_Source (Text : String) return Expected_Source;
   function Make_Expected_Source
     (Text : Ada.Strings.Unbounded.Unbounded_String) return Expected_Source;

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

   --  Atomic journal publication:
   --  1. Initial stale check (re-read target vs Expected)
   --  2. Pre-admission validation
   --  3. Unique candidate staging in same directory
   --  4. Optional test/inspection hook
   --  5. Second stale fence (re-read target vs Expected right before rename)
   --  6. Backup creation
   --  7. Atomic rename
   --  8. Post-admission validation
   --  9. Cleanup
   function Atomic_Publish_Journal
     (Target_Path      : String;
      Expected         : Expected_Source;
      Candidate        : Candidate_Source;
      Status           : out Writer_Status;
      Error_Msg        : out Unbounded_String;
      After_Stage_Hook : access procedure (Staged_Path : String) := null) return Boolean
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
      Text : Ada.Strings.Unbounded.Unbounded_String :=
        Ada.Strings.Unbounded.Null_Unbounded_String;
   end record;

   type Candidate_Source is record
      Text : Ada.Strings.Unbounded.Unbounded_String :=
        Ada.Strings.Unbounded.Null_Unbounded_String;
   end record;

end HRA.Writer;
