with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

--  Filesystem observation boundary for the optional Issue relation sidecar.
--
--  The sidecar is root-relative but is not a ninth ordinary canonical
--  Household source. Missing is a valid initial state and remains distinct from
--  a present zero-byte file so later publication can fence both existence and
--  exact observed bytes.
package HRA.Issue_Relation.Sidecar is

   type Presence is (Absent, Present);

   type Observation (State : Presence := Absent) is private;

   function State_Of (Value : Observation) return Presence;
   function Path_Of (Value : Observation) return String;

   function Text_Of (Value : Observation) return String
     with Pre => State_Of (Value) = Present;

   type Observation_Status is
     (Success,
      Root_Not_Directory,
      Sidecar_Not_Regular_File,
      Sidecar_Too_Large,
      Sidecar_Read_Failed);

   type Observation_Diagnostic is record
      Status  : Observation_Status := Success;
      Message : Unbounded_String;
   end record;

   --  Observe the one relation sidecar coordinate under an existing Household
   --  root. A missing sidecar succeeds as Absent. An existing path must be one
   --  ordinary file and is retained byte-for-byte when Present.
   function Observe
     (Root_Dir : String;
      Result   : out Observation;
      Diag     : out Observation_Diagnostic) return Boolean
     with Pre => Root_Dir'Length > 0;

private

   type Observation (State : Presence := Absent) is record
      Path : Unbounded_String;
      case State is
         when Absent =>
            null;
         when Present =>
            Text : Unbounded_String;
      end case;
   end record;

end HRA.Issue_Relation.Sidecar;
