with HRA.Dates;
with HRA.Journal;
with HRA.Journal.Document;

package body HRA.Journal_Evidence is

   function Extract
     (Input    : String;
      L        : HRA.Ledger.Ledger;
      Evidence : out Journal_Evidence;
      Diag     : out Evidence_Diagnostic) return Boolean
   is
   begin
      return Extract
        (Input       => Input,
         Source_Path => "",
         L           => L,
         Evidence    => Evidence,
         Diag        => Diag);
   end Extract;

   function Extract
     (Input       : String;
      Source_Path : String;
      L           : HRA.Ledger.Ledger;
      Evidence    : out Journal_Evidence;
      Diag        : out Evidence_Diagnostic) return Boolean
   is
      Document   : HRA.Journal.Document.Parsed_Document;
      Parse_Diag : HRA.Journal.Parse_Diagnostic;
   begin
      Evidence.Transactions.Clear;
      Diag := (Line_Number => 0, Message => Null_Unbounded_String);

      if not HRA.Journal.Document.Parse
        (Input, Source_Path, Document, Parse_Diag)
      then
         Diag :=
           (Line_Number => Parse_Diag.Line_Number,
            Message     => Parse_Diag.Message);
         return False;
      end if;

      if Natural (Document.Transactions.Length) /=
        Natural (L.Transactions.Length)
      then
         Diag.Message := To_Unbounded_String
           ("transaction source evidence count does not match admitted Journal");
         return False;
      end if;

      for I in 1 .. Natural (L.Transactions.Length) loop
         declare
            Source : constant Transaction_Source :=
              Document.Transactions.Element (I);
            Tx : constant HRA.Ledger.Transaction := L.Transactions.Element (I);
         begin
            if To_String (Source.Date_Text) /= HRA.Dates.Image (Tx.Date)
              or else To_String (Source.Description) /=
                To_String (Tx.Code_Or_Payee)
            then
               Diag :=
                 (Line_Number => Source.Header_Line,
                  Message     => To_Unbounded_String
                    ("transaction source evidence does not align with admitted Journal"));
               return False;
            end if;
         end;
      end loop;

      Evidence.Transactions := Document.Transactions;
      return True;
   end Extract;

end HRA.Journal_Evidence;
