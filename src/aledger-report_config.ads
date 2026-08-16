with ALedger.Config_Support; use ALedger.Config_Support;
with ALedger.Dates;

package ALedger.Report_Config is

   type Boundary_Kind is (Latest, Beginning, Exact_Date);

   type Date_Boundary (Kind : Boundary_Kind := Latest) is record
      case Kind is
         when Exact_Date =>
            Value : ALedger.Dates.Date;
         when Latest | Beginning =>
            null;
      end case;
   end record;

   type Range_Spec is record
      From    : Date_Boundary;
      Through : Date_Boundary;
   end record;

   type As_Of_Spec is record
      Value : Date_Boundary;
   end record;

   type Recent_Spec is record
      Through : Date_Boundary;
      Count   : Positive;
   end record;

   type Negative_Style is (Parentheses, Minus);
   type Presentation_Color is
     (Red, Bright_Red, Green, Yellow, Blue, Magenta, Cyan, White);
   type Calendar_Markers is record
      Cycle_End : Character := '|';
      Plan_Due  : Character := '$';
      Issue_Due : Character := '!';
      Multiple  : Character := '+';
   end record;
   type Presentation_Config is record
      Negative           : Negative_Style := Parentheses;
      Heading_Color      : Presentation_Color := Cyan;
      Section_Color      : Presentation_Color := Yellow;
      Positive_Color     : Presentation_Color := Green;
      Negative_Color     : Presentation_Color := Red;
      Calendar           : Calendar_Markers;
      Daily_Date_Columns : Positive := 14;
   end record;

   type Report_Plan is record
      Trial_Balance       : As_Of_Spec;
      Balance_Sheet       : As_Of_Spec;
      Profit_And_Loss     : Range_Spec;
      Daily_Flow          : Range_Spec;
      Monthly_Accounts    : Range_Spec;
      Recent_Transactions : Recent_Spec;
   end record;

   type Report_Configuration is record
      Presentation : Presentation_Config;
      Plan         : Report_Plan;
   end record;

   function Parse_Report_Configuration
     (Text   : String;
      Config : out Report_Configuration;
      Diag   : out Config_Diagnostic) return Boolean;

end ALedger.Report_Config;
