with Ada.Strings;           use Ada.Strings;
with Ada.Strings.Fixed;     use Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with ALedger.Account;       use ALedger.Account;
with ALedger.Dates;
with ALedger.Money;         use ALedger.Money;

package body ALedger.Recent_Journal_Render is

   function Render_Amount (Value : Amount) return String is
   begin
      return Render_Quantity (Value.Val) & " " & Code (Value.Comm);
   end Render_Amount;

   function Render
     (Recent : ALedger.Recent_Journal.Observation) return String
   is
      Buf : Unbounded_String;
   begin
      Append
        (Buf,
         "== Recent Journal ==" & ASCII.LF &
         "Through: " & ALedger.Dates.Image (Recent.Through_Date) &
         " | Requested: " & Trim (Positive'Image (Recent.Requested), Both) &
         " | Displayed: " &
         Trim (Natural'Image (Natural (Recent.Entries.Length)), Both) &
         ASCII.LF & ASCII.LF);

      for Item of Recent.Entries loop
         Append
           (Buf,
            ALedger.Dates.Image (Item.Value.Date) & " " &
            To_String (Item.Value.Code_Or_Payee) & ASCII.LF);
         for Posting of Item.Value.Postings loop
            Append
              (Buf,
               "    " & Name (Posting.Acc) & "    " &
               Render_Amount (Posting.Amt) & ASCII.LF);
         end loop;
         Append (Buf, ASCII.LF);
      end loop;

      return To_String (Buf);
   end Render;

end ALedger.Recent_Journal_Render;
