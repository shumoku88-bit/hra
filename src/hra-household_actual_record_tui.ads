with HRA.Dates;
with HRA.Household;
with HRA.Ledger;

--  Curses delivery adapter for editing one general Actual draft.
--
--  The editor owns only screen focus, UTF-8 text editing, preview, and terminal
--  keys. It lowers through HRA.Household_Actual_Draft and returns a typed
--  Ledger.Transaction. Durable identity, publication, Household reload, and
--  domain-date choice remain outside this package.
package HRA.Household_Actual_Record_TUI is

   type Edit_Result_Kind is (Cancelled, Accepted);

   type Edit_Result (Kind : Edit_Result_Kind := Cancelled) is record
      case Kind is
         when Cancelled =>
            null;
         when Accepted =>
            Tx : HRA.Ledger.Transaction;
      end case;
   end record;

   --  Curses must already be initialized by the surrounding TUI shell.
   --  Day is the explicit typed coordinate chosen by Household Home.
   function Edit
     (State : HRA.Household.Household_State;
      Day   : HRA.Dates.Date) return Edit_Result;

end HRA.Household_Actual_Record_TUI;
