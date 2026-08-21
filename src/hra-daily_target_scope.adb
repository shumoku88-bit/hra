with Ada.Containers.Indefinite_Vectors;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA.Account;
with HRA.Journal_Evidence;
with HRA.Money;

package body HRA.Daily_Target_Scope is

   use type HRA.Account.Account_Type;
   use type HRA.Money.Commodity;
   use type HRA.Money.Quantity;
   use type HRA.Plan.Plan_Id;

   package String_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Positive, Element_Type => String);

   function "=" (Left, Right : Obligation) return Boolean is
   begin
      if Left.Selection /= Right.Selection
        or else Left.Plan_ID /= Right.Plan_ID
        or else Left.Amount.Comm /= Right.Amount.Comm
        or else Left.Amount.Val /= Right.Amount.Val
        or else Left.Reservation.Present /= Right.Reservation.Present
      then
         return False;
      elsif not Left.Reservation.Present then
         return True;
      else
         return
           Left.Reservation.Value.ID = Right.Reservation.Value.ID
           and then Left.Reservation.Value.Amount.Comm =
             Right.Reservation.Value.Amount.Comm
           and then Left.Reservation.Value.Amount.Val =
             Right.Reservation.Value.Amount.Val;
      end if;
   end "=";

   function Contains
     (Values : String_Vectors.Vector;
      Value  : String) return Boolean
   is
   begin
      for Item of Values loop
         if Item = Value then
            return True;
         end if;
      end loop;
      return False;
   end Contains;

   procedure Find_Metadata
     (Source : HRA.Journal_Evidence.Transaction_Source;
      Key    : String;
      Count  : out Natural;
      Found  : out HRA.Journal_Evidence.Metadata_Entry)
   is
   begin
      Count := 0;
      Found :=
        (Key         => Null_Unbounded_String,
         Value       => Null_Unbounded_String,
         Line_Number => Source.Header_Line);

      for Meta of Source.Metadata loop
         if To_String (Meta.Key) = Key then
            Count := Count + 1;
            if Count = 1 then
               Found := Meta;
            end if;
         end if;
      end loop;
   end Find_Metadata;

   function Valid_Reservation_Id (Value : String) return Boolean is
   begin
      if Value'Length = 0 then
         return False;
      end if;

      for C of Value loop
         if C = ' '
           or else Character'Pos (C) < 32
           or else Character'Pos (C) = 127
         then
            return False;
         end if;
      end loop;
      return True;
   end Valid_Reservation_Id;

   function Admit
     (Policy   : HRA.Household_Config.Household_Configuration;
      Registry : HRA.Account.Account_Registry;
      Plans    : HRA.Plan_Admission.Plan_Journal;
      Result   : out Scope;
      Diag     : out Admission_Diagnostic) return Boolean
   is
      Output            : Scope := Empty_Scope;
      Seen_Selections   : String_Vectors.Vector;
      Seen_Reservations : String_Vectors.Vector;

      procedure Fail
        (Status       : Admission_Status;
         Line_Number  : Natural;
         Selection    : String;
         Plan_Id      : String;
         Message      : String)
      is
      begin
         Diag :=
           (Status      => Status,
            Line_Number => Line_Number,
            Selection   => To_Unbounded_String (Selection),
            Plan_Id     => To_Unbounded_String (Plan_Id),
            Message     => To_Unbounded_String (Message));
      end Fail;

      function Project_Selected_Outgoing
        (Item   : HRA.Plan_Admission.Plan_Transaction_Entry;
         Amount : out HRA.Money.Amount) return Boolean
      is
         Source_Count : Natural := 0;
         Target_Count : Natural := 0;
      begin
         if Natural (Item.Tx.Postings.Length) /= 2 then
            Fail
              (Unsupported_Selected_Plan_Shape,
               Item.Source.Header_Line,
               "",
               HRA.Plan.Text (Item.ID),
               "Daily Target selected Plan must be one Asset source and one Expense/Liability destination");
            return False;
         end if;

         for Posting of Item.Tx.Postings loop
            declare
               Category : HRA.Account.Account_Type;
            begin
               if not HRA.Account.Account_Type_For
                 (Registry, Posting.Acc, Category)
               then
                  Fail
                    (Unsupported_Selected_Plan_Shape,
                     Item.Source.Header_Line,
                     "",
                     HRA.Plan.Text (Item.ID),
                     "Daily Target selected Plan references an undeclared Account");
                  return False;
               elsif Category = HRA.Account.Asset
                 and then Posting.Amt.Val < HRA.Money.Zero_Quantity
               then
                  Source_Count := Source_Count + 1;
               elsif (Category = HRA.Account.Expense
                      or else Category = HRA.Account.Liability)
                 and then Posting.Amt.Val > HRA.Money.Zero_Quantity
               then
                  Target_Count := Target_Count + 1;
                  Amount := Posting.Amt;
               else
                  Fail
                    (Unsupported_Selected_Plan_Shape,
                     Item.Source.Header_Line,
                     "",
                     HRA.Plan.Text (Item.ID),
                     "Daily Target selected Plan is not an outgoing household commitment");
                  return False;
               end if;
            end;
         end loop;

         if Source_Count /= 1 or else Target_Count /= 1 then
            Fail
              (Unsupported_Selected_Plan_Shape,
               Item.Source.Header_Line,
               "",
               HRA.Plan.Text (Item.ID),
               "Daily Target selected Plan does not have one source and one destination");
            return False;
         end if;

         return True;
      end Project_Selected_Outgoing;

   begin
      Result := Output;
      Diag :=
        (Status      => Success,
         Line_Number => 0,
         Selection   => Null_Unbounded_String,
         Plan_Id     => Null_Unbounded_String,
         Message     => Null_Unbounded_String);

      --  Household admission already proved that these source coordinates are
      --  unique, syntactically valid, declared Asset Accounts. Re-admitting
      --  those same facts here would create a second policy authority.
      for Selection of Policy.Daily_Target_Assets loop
         Seen_Selections.Append (To_String (Selection.ID));
         Output.Assets.Append
           (HRA.Account.Make_Account (To_String (Selection.Account)));
      end loop;

      for I in 1 .. HRA.Plan_Admission.Transaction_Count (Plans) loop
         declare
            Item : constant HRA.Plan_Admission.Plan_Transaction_Entry :=
              HRA.Plan_Admission.Transaction_At (Plans, I);
            Selection_Count, Reservation_Id_Count,
              Reservation_Amount_Count, Reservation_Commodity_Count : Natural;
            Selection_Meta, Reservation_Id_Meta,
              Reservation_Amount_Meta, Reservation_Commodity_Meta :
                HRA.Journal_Evidence.Metadata_Entry;
         begin
            Find_Metadata
              (Item.Source, "daily-target-id",
               Selection_Count, Selection_Meta);
            Find_Metadata
              (Item.Source, "reservation-id",
               Reservation_Id_Count, Reservation_Id_Meta);
            Find_Metadata
              (Item.Source, "reservation-amount",
               Reservation_Amount_Count, Reservation_Amount_Meta);
            Find_Metadata
              (Item.Source, "reservation-commodity",
               Reservation_Commodity_Count, Reservation_Commodity_Meta);

            if Selection_Count > 1
              or else Reservation_Id_Count > 1
              or else Reservation_Amount_Count > 1
              or else Reservation_Commodity_Count > 1
            then
               Fail
                 (Duplicate_Daily_Target_Metadata,
                  Item.Source.Header_Line,
                  "",
                  HRA.Plan.Text (Item.ID),
                  "Plan repeats Daily Target metadata");
               return False;
            end if;

            declare
               Has_Reservation : constant Boolean :=
                 Reservation_Id_Count = 1
                 or else Reservation_Amount_Count = 1
                 or else Reservation_Commodity_Count = 1;
               Complete_Reservation : constant Boolean :=
                 Reservation_Id_Count = 1
                 and then Reservation_Amount_Count = 1
                 and then Reservation_Commodity_Count = 1;
            begin
               if Selection_Count = 0 then
                  if Has_Reservation then
                     Fail
                       (Reservation_Without_Selection,
                        Item.Source.Header_Line,
                        "",
                        HRA.Plan.Text (Item.ID),
                        "reservation metadata requires daily-target-id");
                     return False;
                  end if;
               else
                  declare
                     Selection_Text : constant String :=
                       To_String (Selection_Meta.Value);
                     Selection_Value : Selection_Id;
                     Payment_Amount  : HRA.Money.Amount;
                     Reservation     : Reservation_Option :=
                       (Present => False);
                  begin
                     if Selection_Text'Length = 0 then
                        Fail
                          (Empty_Selection_Id,
                           Selection_Meta.Line_Number,
                           Selection_Text,
                           HRA.Plan.Text (Item.ID),
                           "daily-target-id is empty");
                        return False;
                     elsif Contains (Seen_Selections, Selection_Text) then
                        Fail
                          (Duplicate_Selection_Id,
                           Selection_Meta.Line_Number,
                           Selection_Text,
                           HRA.Plan.Text (Item.ID),
                           "Daily Target selection identity is duplicated across household.toml and plan.journal");
                        return False;
                     elsif not Project_Selected_Outgoing
                       (Item, Payment_Amount)
                     then
                        return False;
                     end if;

                     Selection_Value.Value :=
                       To_Unbounded_String (Selection_Text);

                     if Has_Reservation and then not Complete_Reservation then
                        Fail
                          (Incomplete_Reservation,
                           Item.Source.Header_Line,
                           Selection_Text,
                           HRA.Plan.Text (Item.ID),
                           "reservation requires id, amount, and commodity together");
                        return False;
                     elsif Complete_Reservation then
                        declare
                           Reservation_Text : constant String :=
                             To_String (Reservation_Id_Meta.Value);
                           Quantity : HRA.Money.Quantity;
                           Commodity : HRA.Money.Commodity;
                           Commodity_Status : HRA.Money.Commodity_Status;
                           Reservation_Value : Reservation_Id;
                           Reservation_Amount : HRA.Money.Amount;
                        begin
                           if not Valid_Reservation_Id (Reservation_Text) then
                              Fail
                                (Invalid_Reservation_Id,
                                 Reservation_Id_Meta.Line_Number,
                                 Selection_Text,
                                 HRA.Plan.Text (Item.ID),
                                 "invalid reservation-id");
                              return False;
                           elsif Contains
                             (Seen_Reservations, Reservation_Text)
                           then
                              Fail
                                (Duplicate_Reservation_Id,
                                 Reservation_Id_Meta.Line_Number,
                                 Selection_Text,
                                 HRA.Plan.Text (Item.ID),
                                 "reservation-id is duplicated");
                              return False;
                           elsif not HRA.Money.Parse_Quantity
                             (To_String (Reservation_Amount_Meta.Value), Quantity)
                           then
                              Fail
                                (Invalid_Reservation_Amount,
                                 Reservation_Amount_Meta.Line_Number,
                                 Selection_Text,
                                 HRA.Plan.Text (Item.ID),
                                 "invalid reservation amount");
                              return False;
                           elsif Quantity <= HRA.Money.Zero_Quantity then
                              Fail
                                (Nonpositive_Reservation_Amount,
                                 Reservation_Amount_Meta.Line_Number,
                                 Selection_Text,
                                 HRA.Plan.Text (Item.ID),
                                 "reservation amount must be positive");
                              return False;
                           elsif not HRA.Money.Create_Commodity
                             (To_String (Reservation_Commodity_Meta.Value),
                              Commodity, Commodity_Status)
                           then
                              Fail
                                (Invalid_Reservation_Commodity,
                                 Reservation_Commodity_Meta.Line_Number,
                                 Selection_Text,
                                 HRA.Plan.Text (Item.ID),
                                 "invalid reservation commodity");
                              return False;
                           end if;

                           Reservation_Amount :=
                             HRA.Money.Make_Amount (Commodity, Quantity);

                           if Reservation_Amount.Comm /= Payment_Amount.Comm then
                              Fail
                                (Reservation_Commodity_Mismatch,
                                 Reservation_Commodity_Meta.Line_Number,
                                 Selection_Text,
                                 HRA.Plan.Text (Item.ID),
                                 "reservation commodity differs from selected Plan obligation");
                              return False;
                           elsif Reservation_Amount.Val > Payment_Amount.Val then
                              Fail
                                (Reservation_Exceeds_Obligation,
                                 Reservation_Amount_Meta.Line_Number,
                                 Selection_Text,
                                 HRA.Plan.Text (Item.ID),
                                 "reservation exceeds selected Plan obligation");
                              return False;
                           end if;

                           Reservation_Value.Value :=
                             To_Unbounded_String (Reservation_Text);
                           Reservation :=
                             (Present => True,
                              Value   =>
                                (ID     => Reservation_Value,
                                 Amount => Reservation_Amount));
                           Seen_Reservations.Append (Reservation_Text);
                        end;
                     end if;

                     Seen_Selections.Append (Selection_Text);
                     Output.Obligations.Append
                       (Obligation'
                          (Selection   => Selection_Value,
                           Plan_ID     => Item.ID,
                           Amount      => Payment_Amount,
                           Reservation => Reservation));
                  end;
               end if;
            end;
         end;
      end loop;

      if Output.Assets.Is_Empty and then not Output.Obligations.Is_Empty then
         Fail
           (Missing_Eligible_Assets, 0, "", "",
            "Daily Target Plan selections require at least one eligible Asset selection");
         return False;
      end if;

      Result := Output;
      return True;
   end Admit;

end HRA.Daily_Target_Scope;
