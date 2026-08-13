with Ada.Directories;       use Ada.Directories;
with Ada.Streams;           use Ada.Streams;
with Ada.Streams.Stream_IO;

package body ALedger.Canonical_Source is

   function Basename (Source : Source_Name) return String is
   begin
      case Source is
         when Accounts_Source         => return "accounts.journal";
         when Actual_Source           => return "actual.journal";
         when Plan_Source             => return "plan.journal";
         when Budget_Journal_Source   => return "budget.journal";
         when Budget_Config_Source    => return "budget.toml";
         when Household_Config_Source => return "household.toml";
         when Report_Config_Source    => return "report.toml";
         when Issues_Source           => return "issues.tsv";
      end case;
   end Basename;

   function Resolve_Source_Paths (Root_Dir : String) return Source_Paths is
      function Source_Path (Source : Source_Name) return Unbounded_String is
        (To_Unbounded_String (Compose (Root_Dir, Basename (Source))));
   begin
      return
        (Accounts_Journal => Source_Path (Accounts_Source),
         Actual_Journal   => Source_Path (Actual_Source),
         Plan_Journal     => Source_Path (Plan_Source),
         Budget_Journal   => Source_Path (Budget_Journal_Source),
         Budget_TOML      => Source_Path (Budget_Config_Source),
         Household_TOML   => Source_Path (Household_Config_Source),
         Report_TOML      => Source_Path (Report_Config_Source),
         Issues_TSV       => Source_Path (Issues_Source));
   end Resolve_Source_Paths;

   function Path_For
     (Paths  : Source_Paths;
      Source : Source_Name) return String
   is
   begin
      case Source is
         when Accounts_Source         => return To_String (Paths.Accounts_Journal);
         when Actual_Source           => return To_String (Paths.Actual_Journal);
         when Plan_Source             => return To_String (Paths.Plan_Journal);
         when Budget_Journal_Source   => return To_String (Paths.Budget_Journal);
         when Budget_Config_Source    => return To_String (Paths.Budget_TOML);
         when Household_Config_Source => return To_String (Paths.Household_TOML);
         when Report_Config_Source    => return To_String (Paths.Report_TOML);
         when Issues_Source           => return To_String (Paths.Issues_TSV);
      end case;
   end Path_For;

   function Text_For
     (Observation : Source_Observation;
      Source      : Source_Name) return String
   is
   begin
      return To_String (Observation.Texts (Source));
   end Text_For;

   function Read_Exact_Source
     (Path      : String;
      Text      : out Unbounded_String;
      Error_Msg : out Unbounded_String) return Boolean
   is
      package SIO renames Ada.Streams.Stream_IO;
      use type SIO.Count;
      File : SIO.File_Type;
   begin
      SIO.Open (File, SIO.In_File, Path);
      declare
         Byte_Count : constant SIO.Count := SIO.Size (File);
      begin
         if Byte_Count = 0 then
            Text := Null_Unbounded_String;
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
                  Error_Msg := To_Unbounded_String
                    ("short read while observing canonical source: " & Path);
                  return False;
               end if;

               for I in Bytes'Range loop
                  Value (Natural (I)) := Character'Val (Bytes (I));
               end loop;
               Text := To_Unbounded_String (Value);
            end;
         end if;
      end;
      SIO.Close (File);
      Error_Msg := Null_Unbounded_String;
      return True;
   exception
      when others =>
         if SIO.Is_Open (File) then
            SIO.Close (File);
         end if;
         Text := Null_Unbounded_String;
         Error_Msg := To_Unbounded_String
           ("cannot read canonical source: " & Path);
         return False;
   end Read_Exact_Source;

   function Observe_Canonical_Sources
     (Root_Dir    : String;
      Observation : out Source_Observation;
      Error_Msg   : out Unbounded_String) return Boolean
   is
      Result : Source_Observation;
   begin
      if not Exists (Root_Dir) or else Kind (Root_Dir) /= Directory then
         Error_Msg := To_Unbounded_String
           ("canonical Household root is not a directory: " & Root_Dir);
         return False;
      end if;

      Result.Root_Path := To_Unbounded_String (Full_Name (Root_Dir));
      Result.Paths := Resolve_Source_Paths (Root_Dir);

      for Source in Source_Name loop
         declare
            Path : constant String := Path_For (Result.Paths, Source);
         begin
            if not Exists (Path) or else Kind (Path) /= Ordinary_File then
               Error_Msg := To_Unbounded_String
                 ("missing canonical source " & Basename (Source) &
                  " under " & Root_Dir);
               return False;
            end if;

            if not Read_Exact_Source
              (Path, Result.Texts (Source), Error_Msg)
            then
               return False;
            end if;
         end;
      end loop;

      Observation := Result;
      Error_Msg := Null_Unbounded_String;
      return True;
   exception
      when others =>
         Error_Msg := To_Unbounded_String
           ("failed to observe canonical Household root: " & Root_Dir);
         return False;
   end Observe_Canonical_Sources;

end ALedger.Canonical_Source;
