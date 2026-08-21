with Ada.Directories; use Ada.Directories;
with Ada.IO_Exceptions;
with Ada.Streams; use Ada.Streams;
with Ada.Streams.Stream_IO;

package body HRA.Issue_Relation.Sidecar is

   Sidecar_Basename : constant String := "issue-relations.tsv";

   function State_Of (Value : Observation) return Presence is
     (Value.State);

   function Path_Of (Value : Observation) return String is
     (To_String (Value.Path));

   function Text_Of (Value : Observation) return String is
     (To_String (Value.Text));

   function Observe
     (Root_Dir : String;
      Result   : out Observation;
      Diag     : out Observation_Diagnostic) return Boolean
   is
      package SIO renames Ada.Streams.Stream_IO;
      use type SIO.Count;

      Normalized_Root : Unbounded_String := Null_Unbounded_String;
      Sidecar_Path    : Unbounded_String := Null_Unbounded_String;
      File            : SIO.File_Type;
   begin
      Result := (State => Absent, Path => Null_Unbounded_String);
      Diag := (Status => Success, Message => Null_Unbounded_String);

      if not Exists (Root_Dir) or else Kind (Root_Dir) /= Directory then
         Diag :=
           (Status  => Root_Not_Directory,
            Message => To_Unbounded_String
              ("Household root is not a directory: " & Root_Dir));
         return False;
      end if;

      Normalized_Root := To_Unbounded_String (Full_Name (Root_Dir));
      Sidecar_Path := To_Unbounded_String
        (Compose (To_String (Normalized_Root), Sidecar_Basename));

      if not Exists (To_String (Sidecar_Path)) then
         Result :=
           (State => Absent,
            Path  => Sidecar_Path);
         return True;
      end if;

      if Kind (To_String (Sidecar_Path)) /= Ordinary_File then
         Diag :=
           (Status  => Sidecar_Not_Regular_File,
            Message => To_Unbounded_String
              ("Issue relation sidecar is not a regular file: " &
               To_String (Sidecar_Path)));
         return False;
      end if;

      SIO.Open (File, SIO.In_File, To_String (Sidecar_Path));
      declare
         Byte_Count : constant SIO.Count := SIO.Size (File);
      begin
         if Byte_Count > SIO.Count (Natural'Last) then
            SIO.Close (File);
            Diag :=
              (Status  => Sidecar_Too_Large,
               Message => To_Unbounded_String
                 ("Issue relation sidecar is too large to observe: " &
                  To_String (Sidecar_Path)));
            return False;
         elsif Byte_Count = 0 then
            SIO.Close (File);
            Result :=
              (State => Present,
               Path  => Sidecar_Path,
               Text  => Null_Unbounded_String);
            return True;
         else
            declare
               Bytes : Stream_Element_Array
                 (1 .. Stream_Element_Offset (Byte_Count));
               Last  : Stream_Element_Offset;
               Value : String (1 .. Natural (Byte_Count));
            begin
               SIO.Read (File, Bytes, Last);
               if Last /= Bytes'Last then
                  SIO.Close (File);
                  Diag :=
                    (Status  => Sidecar_Read_Failed,
                     Message => To_Unbounded_String
                       ("short read while observing Issue relation sidecar: " &
                        To_String (Sidecar_Path)));
                  return False;
               end if;

               for I in Bytes'Range loop
                  Value (Natural (I)) := Character'Val (Bytes (I));
               end loop;

               SIO.Close (File);
               Result :=
                 (State => Present,
                  Path  => Sidecar_Path,
                  Text  => To_Unbounded_String (Value));
               return True;
            end;
         end if;
      end;
   exception
      when Ada.IO_Exceptions.Name_Error
         | Ada.IO_Exceptions.Use_Error
         | Ada.IO_Exceptions.Device_Error
         | Ada.IO_Exceptions.End_Error
         | Ada.IO_Exceptions.Data_Error =>
         if SIO.Is_Open (File) then
            SIO.Close (File);
         end if;
         Result := (State => Absent, Path => Sidecar_Path);
         Diag :=
           (Status  => Sidecar_Read_Failed,
            Message => To_Unbounded_String
              ("cannot observe Issue relation sidecar: " &
               To_String (Sidecar_Path)));
         return False;
   end Observe;

end HRA.Issue_Relation.Sidecar;
