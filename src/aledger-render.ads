with ALedger.Ledger;    use ALedger.Ledger;
with ALedger.Issues;    use ALedger.Issues;
limited with ALedger.Household;

package ALedger.Render is

   --  ========================================================================
   --  Human-Readable Report Rendering Engine (Conforming to h-kernel Standards)
   --  ========================================================================

   function Render_Account_Balances
     (L          : Ledger.Ledger;
      As_Of_Date : String) return String;

   function Render_Balance_Sheet
     (L          : Ledger.Ledger;
      As_Of_Date : String) return String;

   function Render_Profit_And_Loss
     (L          : Ledger.Ledger;
      Start_Date : String;
      End_Date   : String) return String;

   function Render_Budget_Status
     (State : ALedger.Household.Household_State) return String;

   function Render_Household_Issues
     (Inv : Issues_Inventory) return String;

   function Render_Recent_Transactions
     (L     : Ledger.Ledger;
      Count : Positive := 5) return String;

end ALedger.Render;
