with Ada.Containers.Indefinite_Vectors;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with ALedger.Money;         use ALedger.Money;

package ALedger.Issues is

   --  ========================================================================
   --  Household Issues TSV Parser (issues.tsv)
   --  ========================================================================

   type Issue_Status is (Open, Resolved);

   type Household_Issue is record
      Issue_ID : Unbounded_String;
      Status   : Issue_Status;
      Date_Str : Unbounded_String;
      Title    : Unbounded_String;
      Amt      : Amount;
      Category : Unbounded_String;
      Details  : Unbounded_String;
   end record;

   package Issue_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Household_Issue);

   type Issues_Inventory is record
      Items : Issue_Vectors.Vector;
   end record;

   function Parse_Issues_TSV (TSV_Text : String; Inv : out Issues_Inventory) return Boolean;

   function Open_Issues (Inv : Issues_Inventory) return Issue_Vectors.Vector;

end ALedger.Issues;
