with Ada.Characters.Handling;
with Ada.Containers.Ordered_Sets;
with Ada.Strings; use Ada.Strings;
with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with HRA.Money; use HRA.Money;

package body HRA.Entitlement_Journal is

   use type HRA.Dates.Date;
   use type HRA.Envelope.Envelope_Id;
   use type HRA.Money.Quantity;

   package Date_Sets is new Ada.Containers.Ordered_Sets
     (Element_Type => HRA.Dates.Date,
      "<"          => HRA.Dates."<",
      "="          => HRA.Dates."=");

   type Endpoint_Kind is (Unallocated, Spendable);

   type Endpoint (Kind : Endpoint_Kind := Unallocated) is record
      case Kind is
         when Unallocated =>
            null;
         when Spendable =>
            Envelope_Id : HRA.Envelope.Envelope_Id;
      end case;
   end record;

   function Empty_History return Entitlement_History is
   begin
      return
        (Origins   => HRA.Envelope_Entitlement.Commodity_Date_Maps.Empty_Map,
         Movements => Movement_Vectors.Empty_Vector);
   end Empty_History;

   function Movement_Count (History : Entitlement_History) return Natural is
     (Natural (History.Movements.Length));

   procedure Set_Diagnostic
     (Diag        : out Admission_Diagnostic;
      Status      : Admission_Status;
      Line_Number : Natural;
      Message     : String)
   is
   begin
      Diag :=
        (Status      => Status,
         Line_Number => Line_Number,
         Message     => To_Unbounded_String (Message));
   end Set_Diagnostic;

   function Strip_Comment (Line : String) return String is
      Semi : constant Natural := Index (Line, ";");
   begin
      if Line'Length = 0 then
         return "";
      elsif Semi = 0 then
         return Trim (Line, Both);
      elsif Semi = Line'First then
         return "";
      else
         return Trim (Line (Line'First .. Semi - 1), Both);
      end if;
   end Strip_Comment;

   procedure Next_Token
     (Text  : String;
      Pos   : in out Natural;
      Token : out Unbounded_String;
      Found : out Boolean)
   is
      Start : Natural;
   begin
      Token := Null_Unbounded_String;
      while Pos <= Text'Last
        and then (Text (Pos) = ' ' or else Text (Pos) = ASCII.HT)
      loop
         Pos := Pos + 1;
      end loop;

      if Pos > Text'Last then
         Found := False;
         return;
      end if;

      Start := Pos;
      while Pos <= Text'Last
        and then Text (Pos) /= ' '
        and then Text (Pos) /= ASCII.HT
      loop
         Pos := Pos + 1;
      end loop;
      Token := To_Unbounded_String (Text (Start .. Pos - 1));
      Found := True;
   end Next_Token;

   function Same (Left, Right : Endpoint) return Boolean is
   begin
      if Left.Kind /= Right.Kind then
         return False;
      elsif Left.Kind = Unallocated then
         return True;
      else
         return Left.Envelope_Id = Right.Envelope_Id;
      end if;
   end Same;

   function Parse_Endpoint
     (Token       : String;
      Registry    : HRA.Envelope.Envelope_Registry;
      Line_Number : Natural;
      Result      : out Endpoint;
      Diag        : out Admission_Diagnostic) return Boolean
   is
      Id : HRA.Envelope.Envelope_Id;
   begin
      if Ada.Characters.Handling.To_Lower (Token) = "unallocated" then
         Result := (Kind => Unallocated);
         return True;
      elsif HRA.Envelope.Lookup (Registry, Token, Id) then
         Result := (Kind => Spendable, Envelope_Id => Id);
         return True;
      else
         Set_Diagnostic
           (Diag, Unknown_Envelope, Line_Number,
            "unknown Envelope endpoint: " & Token);
         return False;
      end if;
   end Parse_Endpoint;

   function Validate_History
     (History : Entitlement_History;
      Registry : HRA.Envelope.Envelope_Registry;
      Diag    : out Admission_Diagnostic) return Boolean
   is
      Dates : Date_Sets.Set;
   begin
      --  Every transfer Commodity has exactly one explicit origin no later
      --  than the transfer. Origin uniqueness was checked while parsing.
      for Movement of History.Movements loop
         declare
            Comm_Key : constant String := Code (Movement.Amt.Comm);
         begin
            if not History.Origins.Contains (Comm_Key) then
               Set_Diagnostic
                 (Diag, Missing_Origin, 0,
                  "missing explicit stock origin for Commodity " & Comm_Key);
               return False;
            elsif History.Origins.Element (Comm_Key) > Movement.Tx_Date then
               Set_Diagnostic
                 (Diag, Origin_After_Transfer, 0,
                  "stock origin is after transfer for Commodity " & Comm_Key);
               return False;
            end if;
         end;
         Dates.Include (Movement.Tx_Date);
      end loop;

      --  Match h-kernel's stock law: same-day effects are combined before the
      --  cumulative non-negative check, so source ordering within one day does
      --  not invent a transient negative balance.
      for Env of HRA.Envelope.All_Ids (Registry) loop
         declare
            Origin_Cursor :
              HRA.Envelope_Entitlement.Commodity_Date_Maps.Cursor :=
                History.Origins.First;
         begin
            while HRA.Envelope_Entitlement.Commodity_Date_Maps.Has_Element
              (Origin_Cursor)
            loop
               declare
                  Comm_Key : constant String :=
                    HRA.Envelope_Entitlement.Commodity_Date_Maps.Key
                      (Origin_Cursor);
                  Running  : Quantity := Zero_Quantity;
                  Date_Cursor : Date_Sets.Cursor := Dates.First;
               begin
                  while Date_Sets.Has_Element (Date_Cursor) loop
                     declare
                        Day   : constant HRA.Dates.Date :=
                          Date_Sets.Element (Date_Cursor);
                        Delta : Quantity := Zero_Quantity;
                     begin
                        for Movement of History.Movements loop
                           if Movement.Tx_Date = Day
                             and then Code (Movement.Amt.Comm) = Comm_Key
                           then
                              case Movement.Kind is
                                 when HRA.Envelope_Entitlement.Grant_From_Unallocated =>
                                    if Movement.Target = Env then
                                       Delta := Delta + Movement.Amt.Val;
                                    end if;
                                 when HRA.Envelope_Entitlement.Transfer_Between_Envelopes =>
                                    if Movement.From_Envelope = Env then
                                       Delta := Delta - Movement.Amt.Val;
                                    end if;
                                    if Movement.To_Envelope = Env then
                                       Delta := Delta + Movement.Amt.Val;
                                    end if;
                                 when HRA.Envelope_Entitlement.Return_To_Unallocated =>
                                    if Movement.Source = Env then
                                       Delta := Delta - Movement.Amt.Val;
                                    end if;
                              end case;
                           end if;
                        end loop;
                        Running := Running + Delta;
                        if Running < Zero_Quantity then
                           Set_Diagnostic
                             (Diag, Negative_Envelope_Stock, 0,
                              "Envelope stock became negative: " &
                              HRA.Envelope.Image (Env) & " " & Comm_Key &
                              " on " & HRA.Dates.Image (Day));
                           return False;
                        end if;
                     end;
                     Date_Sets.Next (Date_Cursor);
                  end loop;
               end;
               HRA.Envelope_Entitlement.Commodity_Date_Maps.Next
                 (Origin_Cursor);
            end loop;
         end;
      end loop;

      Diag :=
        (Status      => Success,
         Line_Number => 0,
         Message     => Null_Unbounded_String);
      return True;
   end Validate_History;

   function Admit
     (Text     : String;
      Registry : HRA.Envelope.Envelope_Registry;
      History  : out Entitlement_History;
      Diag     : out Admission_Diagnostic) return Boolean
   is
      Result      : Entitlement_History := Empty_History;
      Line_Start  : Natural := Text'First;
      Line_Number : Natural := 0;
   begin
      Diag :=
        (Status      => Success,
         Line_Number => 0,
         Message     => Null_Unbounded_String);

      while Line_Start <= Text'Last loop
         declare
            LF : constant Natural := Index (Text, ASCII.LF & "", From => Line_Start);
            Line_End : constant Natural :=
              (if LF = 0 then Text'Last else LF - 1);
            Raw_Line : constant String :=
              (if Line_End < Line_Start then ""
               else Text (Line_Start .. Line_End));
            Statement : constant String := Strip_Comment (Raw_Line);
         begin
            Line_Number := Line_Number + 1;
            if Statement'Length > 0
              and then Statement (Statement'First) /= '#'
            then
               declare
                  Pos : Natural := Statement'First;
                  T_Date, T_Kind, T_1, T_Arrow, T_2, T_Qty, T_Comm :
                    Unbounded_String;
                  F_Date, F_Kind, F_1, F_Arrow, F_2, F_Qty, F_Comm : Boolean;
                  Tx_Date : HRA.Dates.Date;
                  D_Status : HRA.Dates.Date_Status;
               begin
                  Next_Token (Statement, Pos, T_Date, F_Date);
                  Next_Token (Statement, Pos, T_Kind, F_Kind);
                  Next_Token (Statement, Pos, T_1, F_1);

                  if not F_Date or else not F_Kind or else not F_1 then
                     Set_Diagnostic
                       (Diag, Syntax_Error, Line_Number,
                        "expected entitlement.journal statement");
                     return False;
                  elsif not HRA.Dates.Parse
                    (To_String (T_Date), Tx_Date, D_Status)
                  then
                     Set_Diagnostic
                       (Diag, Invalid_Date, Line_Number,
                        "invalid Gregorian date: " & To_String (T_Date));
                     return False;
                  end if;

                  if To_String (T_Kind) = "origin" then
                     declare
                        Comm   : Commodity;
                        Status : Commodity_Status;
                        Key    : constant String := To_String (T_1);
                     begin
                        if not Create_Commodity (Key, Comm, Status) then
                           Set_Diagnostic
                             (Diag, Invalid_Commodity, Line_Number,
                              "invalid Commodity: " & Key);
                           return False;
                        elsif Result.Origins.Contains (Key) then
                           Set_Diagnostic
                             (Diag, Duplicate_Origin, Line_Number,
                              "duplicate stock origin for Commodity " & Key);
                           return False;
                        end if;
                        Result.Origins.Insert (Key, Tx_Date);
                     end;
                  elsif To_String (T_Kind) = "transfer" then
                     Next_Token (Statement, Pos, T_Arrow, F_Arrow);
                     Next_Token (Statement, Pos, T_2, F_2);
                     Next_Token (Statement, Pos, T_Qty, F_Qty);
                     Next_Token (Statement, Pos, T_Comm, F_Comm);
                     if not F_Arrow or else To_String (T_Arrow) /= "->"
                       or else not F_2 or else not F_Qty or else not F_Comm
                     then
                        Set_Diagnostic
                          (Diag, Syntax_Error, Line_Number,
                           "expected transfer <from> -> <to> QUANTITY COMMODITY");
                        return False;
                     end if;

                     declare
                        From_Ep, To_Ep : Endpoint;
                        Qty            : Quantity;
                        Comm           : Commodity;
                        C_Status       : Commodity_Status;
                        Amt            : Amount;
                     begin
                        if not Parse_Endpoint
                          (To_String (T_1), Registry, Line_Number, From_Ep, Diag)
                          or else not Parse_Endpoint
                            (To_String (T_2), Registry, Line_Number, To_Ep, Diag)
                        then
                           return False;
                        elsif Same (From_Ep, To_Ep) then
                           Set_Diagnostic
                             (Diag, Same_Endpoint, Line_Number,
                              "transfer endpoints must differ");
                           return False;
                        elsif not Parse_Quantity (To_String (T_Qty), Qty) then
                           Set_Diagnostic
                             (Diag, Invalid_Quantity, Line_Number,
                              "invalid exact Quantity: " & To_String (T_Qty));
                           return False;
                        elsif Qty <= Zero_Quantity then
                           Set_Diagnostic
                             (Diag, Non_Positive_Quantity, Line_Number,
                              "transfer Quantity must be positive");
                           return False;
                        elsif not Create_Commodity
                          (To_String (T_Comm), Comm, C_Status)
                        then
                           Set_Diagnostic
                             (Diag, Invalid_Commodity, Line_Number,
                              "invalid Commodity: " & To_String (T_Comm));
                           return False;
                        end if;

                        Amt := Make_Amount (Comm, Qty);
                        if From_Ep.Kind = Unallocated
                          and then To_Ep.Kind = Spendable
                        then
                           Result.Movements.Append
                             ((Kind    => HRA.Envelope_Entitlement.Grant_From_Unallocated,
                               Tx_Date => Tx_Date,
                               Amt     => Amt,
                               Target  => To_Ep.Envelope_Id));
                        elsif From_Ep.Kind = Spendable
                          and then To_Ep.Kind = Unallocated
                        then
                           Result.Movements.Append
                             ((Kind    => HRA.Envelope_Entitlement.Return_To_Unallocated,
                               Tx_Date => Tx_Date,
                               Amt     => Amt,
                               Source  => From_Ep.Envelope_Id));
                        else
                           Result.Movements.Append
                             ((Kind          => HRA.Envelope_Entitlement.Transfer_Between_Envelopes,
                               Tx_Date       => Tx_Date,
                               Amt           => Amt,
                               From_Envelope => From_Ep.Envelope_Id,
                               To_Envelope   => To_Ep.Envelope_Id));
                        end if;
                     end;
                  else
                     Set_Diagnostic
                       (Diag, Syntax_Error, Line_Number,
                        "expected 'origin' or 'transfer'");
                     return False;
                  end if;
               end;
            end if;

            exit when LF = 0;
            Line_Start := LF + 1;
         end;
      end loop;

      if not Validate_History (Result, Registry, Diag) then
         return False;
      end if;

      History := Result;
      return True;
   end Admit;

   function Observe
     (History      : Entitlement_History;
      Through_Date : HRA.Dates.Date)
      return HRA.Envelope_Entitlement.Entitlement_Observation
   is
      Result : HRA.Envelope_Entitlement.Entitlement_Observation :=
        HRA.Envelope_Entitlement.Empty_Observation;
      Cursor : HRA.Envelope_Entitlement.Commodity_Date_Maps.Cursor :=
        History.Origins.First;
   begin
      while HRA.Envelope_Entitlement.Commodity_Date_Maps.Has_Element (Cursor) loop
         declare
            Comm : constant Commodity := Make_Commodity
              (HRA.Envelope_Entitlement.Commodity_Date_Maps.Key (Cursor));
            Day : constant HRA.Dates.Date :=
              HRA.Envelope_Entitlement.Commodity_Date_Maps.Element (Cursor);
         begin
            if Day <= Through_Date then
               Result := HRA.Envelope_Entitlement.Record_Origin
                 (Result, Comm, Day);
            end if;
         end;
         HRA.Envelope_Entitlement.Commodity_Date_Maps.Next (Cursor);
      end loop;

      for Movement of History.Movements loop
         if Movement.Tx_Date <= Through_Date then
            Result := HRA.Envelope_Entitlement.Fold_Movement
              (Result, Movement);
         end if;
      end loop;
      return Result;
   end Observe;

end HRA.Entitlement_Journal;
