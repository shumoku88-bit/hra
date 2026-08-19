with Ada.Characters.Handling; use Ada.Characters.Handling;
with Ada.Containers.Indefinite_Ordered_Sets;
with HRA.Dates;               use HRA.Dates;

package body HRA.Issues is

   --  ========================================================================
   --  Issue Identity
   --  ========================================================================

   function Create_Issue_Id
     (Value  : String;
      ID     : out Issue_Id;
      Status : out Issue_Id_Status) return Boolean
   is
   begin
      if Value'Length = 0 then
         Status := Empty_Issue_Id;
         return False;
      end if;

      for I in Value'Range loop
         if Is_Space (Value (I)) then
            Status := Issue_Id_Contains_Whitespace;
            return False;
         elsif Character'Pos (Value (I)) < 32 or else Character'Pos (Value (I)) = 127 then
            Status := Issue_Id_Contains_Control_Character;
            return False;
         end if;
      end loop;

      ID := (ID_Text => To_Unbounded_String (Value));
      Status := Success;
      return True;
   end Create_Issue_Id;

   function Make_Issue_Id (Value : String) return Issue_Id is
      ID     : Issue_Id;
      Status : Issue_Id_Status;
   begin
      if not Create_Issue_Id (Value, ID, Status) then
         raise Constraint_Error with "Invalid issue-id: " & Value;
      end if;
      return ID;
   end Make_Issue_Id;

   function Text (ID : Issue_Id) return String is
   begin
      return To_String (ID.ID_Text);
   end Text;

   function To_Unbounded (ID : Issue_Id) return Unbounded_String is
   begin
      return ID.ID_Text;
   end To_Unbounded;

   function "=" (Left, Right : Issue_Id) return Boolean is
   begin
      return Left.ID_Text = Right.ID_Text;
   end "=";

   function "<" (Left, Right : Issue_Id) return Boolean is
   begin
      return To_String (Left.ID_Text) < To_String (Right.ID_Text);
   end "<";

   --  ========================================================================
   --  Constructors
   --  ========================================================================

   function Make_Due_On (D : HRA.Dates.Date) return Issue_Due is
   begin
      return (Kind => Due_On, Due_Date => D);
   end Make_Due_On;

   function No_Due return Issue_Due is
   begin
      return (Kind => No_Due_Date);
   end No_Due;

   function Undetermined_Due return Issue_Due is
   begin
      return (Kind => Due_Undetermined);
   end Undetermined_Due;

   function Make_Closed_On (D : HRA.Dates.Date) return Issue_Closed is
   begin
      return (Kind => Closed_On, Closed_Date => D);
   end Make_Closed_On;

   function Not_Closed return Issue_Closed is
   begin
      return (Kind => Not_Closed);
   end Not_Closed;

   function Undetermined_Closed return Issue_Closed is
   begin
      return (Kind => Closed_Undetermined);
   end Undetermined_Closed;

   function No_Amount return Optional_Amount is
   begin
      return (Has_Amount => False);
   end No_Amount;

   function Make_Optional_Amount (A : Amount) return Optional_Amount is
   begin
      return (Has_Amount => True, Value => A);
   end Make_Optional_Amount;

   --  ========================================================================
   --  Inventory Operations
   --  ========================================================================

   function Empty_Inventory return Issues_Inventory is
      Result : Issues_Inventory;
   begin
      return Result;
   end Empty_Inventory;

   function Count (Inv : Issues_Inventory) return Natural is
   begin
      return Natural (Inv.Items.Length);
   end Count;

   function Is_Empty (Inv : Issues_Inventory) return Boolean is
   begin
      return Inv.Items.Is_Empty;
   end Is_Empty;

   function Element
     (Inv   : Issues_Inventory;
      Index : Positive) return Household_Issue is
   begin
      return Inv.Items.Element (Index);
   end Element;

   function All_Issues (Inv : Issues_Inventory) return Issue_Array is
      Result : Issue_Array (1 .. Natural (Inv.Items.Length));
      Idx    : Positive := 1;
   begin
      for Issue of Inv.Items loop
         Result (Idx) := Issue;
         Idx := Idx + 1;
      end loop;
      return Result;
   end All_Issues;

   function Open_Issues (Inv : Issues_Inventory) return Issues_Inventory is
      Result : Issues_Inventory;
   begin
      for Issue of Inv.Items loop
         if Issue.Status = Open then
            Result.Items.Append (Issue);
         end if;
      end loop;
      return Result;
   end Open_Issues;

   procedure Append
     (Inv   : in out Issues_Inventory;
      Issue : Household_Issue) is
   begin
      Inv.Items.Append (Issue);
   end Append;

   procedure Clear (Inv : in out Issues_Inventory) is
   begin
      Inv.Items.Clear;
   end Clear;

   --  ========================================================================
   --  Admission
   --  ========================================================================

   Canonical_Header : constant String :=
     "issue_id"   & ASCII.HT &
     "status"     & ASCII.HT &
     "date"       & ASCII.HT &
     "due"        & ASCII.HT &
     "closed"     & ASCII.HT &
     "category"   & ASCII.HT &
     "title"      & ASCII.HT &
     "amount"     & ASCII.HT &
     "currency"   & ASCII.HT &
     "details";

   package Issue_Id_Sets is new Ada.Containers.Indefinite_Ordered_Sets
     (Element_Type => String);

   type Field_Array is array (1 .. 10) of Unbounded_String;

   function Split_Line
     (Line        : String;
      Fields      : out Field_Array;
      Field_Count : out Natural) return Boolean
   is
      Current_Field : Natural := 0;
      Field_Start   : Positive := Line'First;
   begin
      Fields := [others => Null_Unbounded_String];
      Field_Count := 0;

      for I in Line'Range loop
         if Line (I) = ASCII.HT then
            Current_Field := Current_Field + 1;
            if Current_Field > 10 then
               Field_Count := Current_Field;
               return False;
            end if;
            if Field_Start <= I - 1 then
               Fields (Current_Field) := To_Unbounded_String (Line (Field_Start .. I - 1));
            else
               Fields (Current_Field) := Null_Unbounded_String;
            end if;
            Field_Start := I + 1;
         end if;
      end loop;

      Current_Field := Current_Field + 1;
      if Current_Field > 10 then
         Field_Count := Current_Field;
         return False;
      end if;
      if Field_Start <= Line'Last then
         Fields (Current_Field) := To_Unbounded_String (Line (Field_Start .. Line'Last));
      else
         Fields (Current_Field) := Null_Unbounded_String;
      end if;

      Field_Count := Current_Field;
      return Field_Count = 10;
   end Split_Line;

   function Contains_Control (Str : String) return Boolean is
   begin
      for I in Str'Range loop
         if Character'Pos (Str (I)) < 32 or else Character'Pos (Str (I)) = 127 then
            return True;
         end if;
      end loop;
      return False;
   end Contains_Control;

   function Admit_Issues_TSV
     (TSV_Text : String;
      Inv      : out Issues_Inventory;
      Diag     : out Admission_Diagnostic) return Boolean
   is
      Result      : Issues_Inventory;
      Seen_Ids    : Issue_Id_Sets.Set;
      Line_Start  : Positive := TSV_Text'First;
      Line_Num    : Natural := 0;
      Header_Seen : Boolean := False;
   begin
      Diag :=
        (Status      => Success,
         Line_Number => 0,
         Issue_ID    => Null_Unbounded_String,
         Message     => Null_Unbounded_String);

      if TSV_Text'Length = 0 then
         Diag :=
           (Status      => Invalid_Header,
            Line_Number => 1,
            Issue_ID    => Null_Unbounded_String,
            Message     => To_Unbounded_String ("empty issues source"));
         Inv := Result;
         return False;
      end if;

      while Line_Start <= TSV_Text'Last loop
         Line_Num := Line_Num + 1;
         declare
            Line_End : Natural := Line_Start;
         begin
            while Line_End <= TSV_Text'Last and then TSV_Text (Line_End) /= ASCII.LF loop
               Line_End := Line_End + 1;
            end loop;

            declare
               Raw_Line_Slice : constant String := TSV_Text (Line_Start .. Line_End - 1);
               Last_Idx       : constant Natural :=
                 (if Raw_Line_Slice'Length > 0 and then Raw_Line_Slice (Raw_Line_Slice'Last) = ASCII.CR
                  then Raw_Line_Slice'Last - 1
                  else Raw_Line_Slice'Last);
               Raw_Line       : constant String :=
                 (if Raw_Line_Slice'Length > 0 and then Last_Idx >= Raw_Line_Slice'First
                  then Raw_Line_Slice (Raw_Line_Slice'First .. Last_Idx)
                  else "");
            begin
               if not Header_Seen then
                  if Raw_Line /= Canonical_Header then
                     Diag :=
                       (Status      => Invalid_Header,
                        Line_Number => Line_Num,
                        Issue_ID    => Null_Unbounded_String,
                        Message     => To_Unbounded_String ("invalid or missing 10-column header"));
                     Inv := Result;
                     return False;
                  end if;
                  Header_Seen := True;
               else
                  if Raw_Line'Length > 0 then
                     declare
                        Fields      : Field_Array;
                        Field_Count : Natural;
                     begin
                        if not Split_Line (Raw_Line, Fields, Field_Count) then
                           Diag :=
                             (Status      => Malformed_Column_Count,
                              Line_Number => Line_Num,
                              Issue_ID    => Null_Unbounded_String,
                              Message     => To_Unbounded_String ("expected 10 columns"));
                           Inv := Result;
                           return False;
                        end if;

                        --  Control character check across all fields
                        for F_Idx in 1 .. 10 loop
                           if Contains_Control (To_String (Fields (F_Idx))) then
                              Diag :=
                                (Status      => Contains_Control_Character,
                                 Line_Number => Line_Num,
                                 Issue_ID    => Fields (1),
                                 Message     => To_Unbounded_String ("field contains control character"));
                              Inv := Result;
                              return False;
                           end if;
                        end loop;

                        declare
                           ID_Str       : constant String := To_String (Fields (1));
                           Issue_ID_Val : Issue_Id;
                           ID_Status    : Issue_Id_Status;
                        begin
                           if not Create_Issue_Id (ID_Str, Issue_ID_Val, ID_Status) then
                              Diag :=
                                (Status      => Invalid_Issue_Id,
                                 Line_Number => Line_Num,
                                 Issue_ID    => Fields (1),
                                 Message     => To_Unbounded_String ("invalid issue identity"));
                              Inv := Result;
                              return False;
                           end if;

                           if Seen_Ids.Contains (ID_Str) then
                              Diag :=
                                (Status      => Duplicate_Issue_Id,
                                 Line_Number => Line_Num,
                                 Issue_ID    => Fields (1),
                                 Message     => To_Unbounded_String ("duplicate issue identity: " & ID_Str));
                              Inv := Result;
                              return False;
                           end if;
                           Seen_Ids.Insert (ID_Str);

                           --  Status: exact token match without normalization
                           declare
                              Stat_Str   : constant String := To_String (Fields (2));
                              Issue_Stat : Issue_Status;
                           begin
                              if Stat_Str = "open" then
                                 Issue_Stat := Open;
                              elsif Stat_Str = "resolved" then
                                 Issue_Stat := Resolved;
                              elsif Stat_Str = "dropped" then
                                 Issue_Stat := Dropped;
                              else
                                 Diag :=
                                   (Status      => Unknown_Status,
                                    Line_Number => Line_Num,
                                    Issue_ID    => Fields (1),
                                    Message     => To_Unbounded_String ("unknown issue status: " & Stat_Str));
                                 Inv := Result;
                                 return False;
                              end if;

                              --  Recorded Date: exact format without normalization
                              declare
                                 Date_Str  : constant String := To_String (Fields (3));
                                 Rec_Date  : HRA.Dates.Date;
                                 Date_Stat : HRA.Dates.Date_Status;
                              begin
                                 if not HRA.Dates.Parse (Date_Str, Rec_Date, Date_Stat) then
                                    Diag :=
                                      (Status      => Invalid_Recorded_Date,
                                       Line_Number => Line_Num,
                                       Issue_ID    => Fields (1),
                                       Message     => To_Unbounded_String ("invalid recorded date: " & Date_Str));
                                    Inv := Result;
                                    return False;
                                 end if;

                                 --  Due: exact token match without normalization
                                 declare
                                    Due_Str : constant String := To_String (Fields (4));
                                    Due_Obj : Issue_Due;
                                 begin
                                    if Due_Str = "none" then
                                       Due_Obj := (Kind => No_Due_Date);
                                    elsif Due_Str = "undetermined" then
                                       Due_Obj := (Kind => Due_Undetermined);
                                    else
                                       declare
                                          D_Val  : HRA.Dates.Date;
                                          D_Stat : HRA.Dates.Date_Status;
                                       begin
                                          if HRA.Dates.Parse (Due_Str, D_Val, D_Stat) then
                                             Due_Obj := (Kind => Due_On, Due_Date => D_Val);
                                          else
                                             Diag :=
                                               (Status      => Invalid_Due_Date,
                                                Line_Number => Line_Num,
                                                Issue_ID    => Fields (1),
                                                Message     => To_Unbounded_String ("invalid due date: " & Due_Str));
                                             Inv := Result;
                                             return False;
                                          end if;
                                       end;
                                    end if;

                                    --  Closed: exact token match without normalization
                                    declare
                                       Closed_Str : constant String := To_String (Fields (5));
                                       Closed_Obj : Issue_Closed;
                                    begin
                                       if Closed_Str = "none" then
                                          Closed_Obj := (Kind => Not_Closed);
                                       elsif Closed_Str = "undetermined" then
                                          Closed_Obj := (Kind => Closed_Undetermined);
                                       else
                                          declare
                                             C_Val  : HRA.Dates.Date;
                                             C_Stat : HRA.Dates.Date_Status;
                                          begin
                                             if HRA.Dates.Parse (Closed_Str, C_Val, C_Stat) then
                                                Closed_Obj := (Kind => Closed_On, Closed_Date => C_Val);
                                             else
                                                Diag :=
                                                  (Status      => Invalid_Closed_Date,
                                                   Line_Number => Line_Num,
                                                   Issue_ID    => Fields (1),
                                                   Message     => To_Unbounded_String ("invalid closed date: " & Closed_Str));
                                                Inv := Result;
                                                return False;
                                             end if;
                                          end;
                                       end if;

                                       --  Lifecycle laws
                                       if Issue_Stat = Open and then Closed_Obj.Kind /= Not_Closed then
                                          Diag :=
                                            (Status      => Open_Issue_With_Closure,
                                             Line_Number => Line_Num,
                                             Issue_ID    => Fields (1),
                                             Message     => To_Unbounded_String ("open issue cannot have closure evidence"));
                                          Inv := Result;
                                          return False;
                                       end if;

                                       if (Issue_Stat = Resolved or else Issue_Stat = Dropped)
                                         and then Closed_Obj.Kind = Not_Closed
                                       then
                                          Diag :=
                                            (Status      => Closed_Issue_Without_Closure,
                                             Line_Number => Line_Num,
                                             Issue_ID    => Fields (1),
                                             Message     => To_Unbounded_String ("resolved or dropped issue must have closure evidence"));
                                          Inv := Result;
                                          return False;
                                       end if;

                                       if Closed_Obj.Kind = Closed_On
                                         and then Closed_Obj.Closed_Date < Rec_Date
                                       then
                                          Diag :=
                                            (Status      => Closed_Before_Recorded,
                                             Line_Number => Line_Num,
                                             Issue_ID    => Fields (1),
                                             Message     => To_Unbounded_String
                                               ("closed date " & HRA.Dates.Image (Closed_Obj.Closed_Date) &
                                                " is earlier than recorded date " & HRA.Dates.Image (Rec_Date)));
                                          Inv := Result;
                                          return False;
                                       end if;

                                       --  Amount & Currency: exact without silent trim
                                       declare
                                          Amt_Str  : constant String := To_String (Fields (8));
                                          Curr_Str : constant String := To_String (Fields (9));
                                          Amt_Obj  : Optional_Amount;
                                       begin
                                          if Amt_Str'Length = 0 and then Curr_Str'Length = 0 then
                                             Amt_Obj := (Has_Amount => False);
                                          elsif Amt_Str'Length = 0 or else Curr_Str'Length = 0 then
                                             Diag :=
                                               (Status      => Partial_Amount_Currency,
                                                Line_Number => Line_Num,
                                                Issue_ID    => Fields (1),
                                                Message     => To_Unbounded_String ("amount and currency must both be present or both be blank"));
                                             Inv := Result;
                                             return False;
                                          else
                                             --  Reject surrounding whitespace in amount
                                             if Is_Space (Amt_Str (Amt_Str'First))
                                               or else Is_Space (Amt_Str (Amt_Str'Last))
                                             then
                                                Diag :=
                                                  (Status      => Invalid_Amount,
                                                   Line_Number => Line_Num,
                                                   Issue_ID    => Fields (1),
                                                   Message     => To_Unbounded_String ("amount contains surrounding whitespace"));
                                                Inv := Result;
                                                return False;
                                             end if;

                                             declare
                                                Q      : Quantity;
                                                Comm   : Commodity;
                                                C_Stat : Commodity_Status;
                                             begin
                                                if not Parse_Quantity (Amt_Str, Q) then
                                                   Diag :=
                                                     (Status      => Invalid_Amount,
                                                      Line_Number => Line_Num,
                                                      Issue_ID    => Fields (1),
                                                      Message     => To_Unbounded_String ("invalid amount quantity: " & Amt_Str));
                                                   Inv := Result;
                                                   return False;
                                                end if;

                                                if not Create_Commodity (Curr_Str, Comm, C_Stat) then
                                                   Diag :=
                                                     (Status      => Invalid_Commodity,
                                                      Line_Number => Line_Num,
                                                      Issue_ID    => Fields (1),
                                                      Message     => To_Unbounded_String ("invalid commodity code: " & Curr_Str));
                                                   Inv := Result;
                                                   return False;
                                                end if;

                                                Amt_Obj := (Has_Amount => True, Value => Make_Amount (Comm, Q));
                                             end;
                                          end if;

                                          Result.Items.Append
                                            (Household_Issue'
                                               (ID          => Issue_ID_Val,
                                                Status      => Issue_Stat,
                                                Recorded_On => Rec_Date,
                                                Due         => Due_Obj,
                                                Closed      => Closed_Obj,
                                                Category    => Fields (6),
                                                Title       => Fields (7),
                                                Amt         => Amt_Obj,
                                                Details     => Fields (10)));
                                       end;
                                    end;
                                 end;
                              end;
                           end;
                        end;
                     end;
                  end if;
               end if;
            end;
            Line_Start := Line_End + 1;
         end;
      end loop;

      if not Header_Seen then
         Diag :=
           (Status      => Invalid_Header,
            Line_Number => 1,
            Issue_ID    => Null_Unbounded_String,
            Message     => To_Unbounded_String ("invalid or missing 10-column header"));
         Inv := Result;
         return False;
      end if;

      Inv := Result;
      return True;
   end Admit_Issues_TSV;

end HRA.Issues;
