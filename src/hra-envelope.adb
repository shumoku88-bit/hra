package body HRA.Envelope is

   --  ========================================================================
   --  Envelope Identity
   --  ========================================================================

   function Create_Envelope_Id
     (Name   : String;
      Id     : out Envelope_Id;
      Status : out Envelope_Id_Status) return Boolean
   is
   begin
      if Name'Length = 0 then
         Status := Empty_Identity;
         return False;
      end if;

      if Name (Name'First) = ' '
        or else Name (Name'Last) = ' '
      then
         Status := Leading_Or_Trailing_Whitespace;
         return False;
      end if;

      for C of Name loop
         if C < ' ' or else C = ASCII.DEL then
            Status := Identity_Contains_Control;
            return False;
         end if;
      end loop;

      Id := (Name => To_Unbounded_String (Name));
      Status := Success;
      return True;
   end Create_Envelope_Id;

   function Image (Id : Envelope_Id) return String is
   begin
      return To_String (Id.Name);
   end Image;

   function "=" (Left, Right : Envelope_Id) return Boolean is
   begin
      return Left.Name = Right.Name;
   end "=";

   function Make_Envelope_Id (Name : String) return Envelope_Id is
      Result : Envelope_Id;
      Status : Envelope_Id_Status;
      OK     : Boolean;
   begin
      OK := Create_Envelope_Id (Name, Result, Status);
      if not OK then
         raise Constraint_Error with
           "Make_Envelope_Id: invalid identity """ & Name & """";
      end if;
      return Result;
   end Make_Envelope_Id;

   function "<" (Left, Right : Envelope_Id) return Boolean is
   begin
      return To_String (Left.Name) < To_String (Right.Name);
   end "<";

   --  ========================================================================
   --  Envelope Registry
   --  ========================================================================

   function Empty_Registry return Envelope_Registry is
   begin
      return (By_Name => Envelope_Name_Maps.Empty_Map);
   end Empty_Registry;

   function Admit_Registry
     (Identities : String_Vectors.Vector;
      Registry   : out Envelope_Registry;
      Diag       : out Config_Diagnostic) return Boolean
   is
      Source_Name : constant String := "budget.toml";
      R           : Envelope_Registry;
      Id          : Envelope_Id;
      Status      : Envelope_Id_Status;
   begin
      if Identities.Is_Empty then
         Set_Error (Diag, Source_Name, "envelope-history.identities",
                    "expected at least one Envelope identity");
         return False;
      end if;

      for Name of Identities loop
         if not Create_Envelope_Id (Name, Id, Status) then
            Set_Error (Diag, Source_Name,
                       "envelope-history.identities",
                       "invalid Envelope identity: """ & Name & """");
            return False;
         end if;

         if R.By_Name.Contains (Name) then
            Set_Error (Diag, Source_Name,
                       "envelope-history.identities",
                       "duplicate Envelope identity: """ & Name & """");
            return False;
         end if;

         R.By_Name.Insert (Name, Id);
      end loop;

      Registry := R;
      return True;
   end Admit_Registry;

   function Contains (R : Envelope_Registry; Name : String) return Boolean is
   begin
      return R.By_Name.Contains (Name);
   end Contains;

   function Lookup
     (R    : Envelope_Registry;
      Name : String;
      Id   : out Envelope_Id) return Boolean
   is
   begin
      if R.By_Name.Contains (Name) then
         Id := R.By_Name.Element (Name);
         return True;
      else
         return False;
      end if;
   end Lookup;

   function Length (R : Envelope_Registry) return Natural is
   begin
      return Natural (R.By_Name.Length);
   end Length;

   function All_Ids (R : Envelope_Registry) return Envelope_Id_Array is
      Result : Envelope_Id_Array (1 .. Natural (R.By_Name.Length));
      I      : Positive := 1;
      Cursor : Envelope_Name_Maps.Cursor := R.By_Name.First;
   begin
      while Envelope_Name_Maps.Has_Element (Cursor) loop
         Result (I) := Envelope_Name_Maps.Element (Cursor);
         I := I + 1;
         Envelope_Name_Maps.Next (Cursor);
      end loop;
      return Result;
   end All_Ids;

end HRA.Envelope;
