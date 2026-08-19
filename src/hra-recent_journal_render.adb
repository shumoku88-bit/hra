with Ada.Strings;           use Ada.Strings;
with Ada.Strings.Fixed;     use Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA.Account;       use HRA.Account;
with HRA.Dates;
with HRA.Money;         use HRA.Money;

package body HRA.Recent_Journal_Render is

   function Render_Amount (Value : Amount) return String is
   begin
      return Render_Quantity (Value.Val) & " " & Code (Value.Comm);
   end Render_Amount;

   function Render
     (Recent : HRA.Recent_Journal.Observation) return String
   is
      Buf : Unbounded_String;
   begin
      Append
        (Buf,
         "== Recent Journal ==" & ASCII.LF &
         "Through: " & HRA.Dates.Image (Recent.Through_Date) &
         " | Requested: " & Trim (Positive'Image (Recent.Requested), Both) &
         " | Displayed: " &
         Trim (Natural'Image (Natural (Recent.Entries.Length)), Both) &
         ASCII.LF & ASCII.LF);

      for Item of Recent.Entries loop
         Append
           (Buf,
            HRA.Dates.Image (Item.Value.Date) & " " &
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

end HRA.Recent_Journal_Render;
