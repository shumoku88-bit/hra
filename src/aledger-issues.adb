with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with ALedger.Money;     use ALedger.Money;

package body ALedger.Issues is

   function Parse_Issues_TSV (TSV_Text : String; Inv : out Issues_Inventory) return Boolean is
      Result : Issues_Inventory;
      Line_Start : Positive := TSV_Text'First;
      Line_Num   : Natural := 0;
   begin
      while Line_Start <= TSV_Text'Last loop
         Line_Num := Line_Num + 1;
         declare
            Line_End : Natural := Line_Start;
         begin
            while Line_End <= TSV_Text'Last and then TSV_Text (Line_End) /= ASCII.LF loop
               Line_End := Line_End + 1;
            end loop;

            declare
               Raw_Line : constant String := TSV_Text (Line_Start .. Line_End - 1);
               Trimmed  : constant String := Trim (Raw_Line, Ada.Strings.Both);
            begin
               if Line_Num > 1 and then Trimmed'Length > 0 then
                  --  Parse tab-separated fields: issue_id status date due closed category title amount currency details
                  declare
                     Field_Count : Natural := 0;
                     Field_Start : Positive := Trimmed'First;
                     F_ID, F_Stat, F_Date, F_Title, F_Cat, F_Det : Unbounded_String;
                     F_Amt_Str, F_Curr_Str : Unbounded_String;
                  begin
                     for I in Trimmed'Range loop
                        if Trimmed (I) = ASCII.HT or else I = Trimmed'Last then
                           Field_Count := Field_Count + 1;
                           declare
                              F_End : constant Natural := (if Trimmed (I) = ASCII.HT then I - 1 else I);
                              F_Val : constant String := Trimmed (Field_Start .. F_End);
                           begin
                              case Field_Count is
                                 when 1 => F_ID       := To_Unbounded_String (F_Val);
                                 when 2 => F_Stat     := To_Unbounded_String (F_Val);
                                 when 3 => F_Date     := To_Unbounded_String (F_Val);
                                 when 6 => F_Cat      := To_Unbounded_String (F_Val);
                                 when 7 => F_Title    := To_Unbounded_String (F_Val);
                                 when 8 => F_Amt_Str  := To_Unbounded_String (F_Val);
                                 when 9 => F_Curr_Str := To_Unbounded_String (F_Val);
                                 when 10=> F_Det      := To_Unbounded_String (F_Val);
                                 when others => null;
                              end case;
                           end;
                           Field_Start := I + 1;
                        end if;
                     end loop;

                     if Length (F_ID) > 0 then
                        declare
                           Stat : Issue_Status := Open;
                           Q    : Quantity := Zero_Quantity;
                           Comm : Commodity;
                           C_Stat : Commodity_Status;
                        begin
                           if To_String (F_Stat) = "resolved" then
                              Stat := Resolved;
                           end if;

                           if not Parse_Quantity (To_String (F_Amt_Str), Q) then
                              Q := Zero_Quantity;
                           end if;

                           if not Create_Commodity (To_String (F_Curr_Str), Comm, C_Stat) then
                              Comm := Make_Commodity ("JPY");
                           end if;

                           Result.Items.Append
                             ((Issue_ID => F_ID,
                               Status   => Stat,
                               Date_Str => F_Date,
                               Title    => F_Title,
                               Amt      => Make_Amount (Comm, Q),
                               Category => F_Cat,
                               Details  => F_Det));
                        end;
                     end if;
                  end;
               end if;
            end;

            Line_Start := Line_End + 1;
         end;
      end loop;

      Inv := Result;
      return True;
   end Parse_Issues_TSV;

   function Open_Issues (Inv : Issues_Inventory) return Issue_Vectors.Vector is
      Vec : Issue_Vectors.Vector;
   begin
      for Issue of Inv.Items loop
         if Issue.Status = Open then
            Vec.Append (Issue);
         end if;
      end loop;
      return Vec;
   end Open_Issues;

end ALedger.Issues;
