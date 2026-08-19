with HRA.Dates;
with HRA.Ledger;    use HRA.Ledger;
with HRA.Issues;    use HRA.Issues;

package HRA.Render is

   --  ========================================================================
   --  Human-Readable Report Rendering Engine (Conforming to h-kernel Standards)
   --  ========================================================================

   function Render_Account_Balances
     (L          : Ledger.Ledger;
      As_Of_Date : HRA.Dates.Date) return String;

   function Render_Account_Balances
     (L : Ledger.Ledger) return String;

   function Render_Balance_Sheet
     (L          : Ledger.Ledger;
      As_Of_Date : HRA.Dates.Date) return String;

   function Render_Balance_Sheet
     (L : Ledger.Ledger) return String;

   function Render_Profit_And_Loss
     (L      : Ledger.Ledger;
      Period : HRA.Dates.Closed_Period) return String;

   function Render_Profit_And_Loss
     (L : Ledger.Ledger) return String;

   function Render_Household_Issues
     (Inv : Issues_Inventory) return String;

   function Render_Recent_Transactions
     (L     : Ledger.Ledger;
      Count : Positive := 5) return String;

end HRA.Render;
