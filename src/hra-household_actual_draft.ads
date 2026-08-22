with Ada.Containers.Vectors;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA.Account;
with HRA.Dates;
with HRA.Household;
with HRA.Ledger;
with HRA.Money;

--  Pure delivery-neutral editing model for one general Actual record.
--
--  A draft owns only explicit user-editable transaction coordinates: one
--  already-chosen day, one description, and two-or-more signed posting rows.
--  Terminal focus, cursor state, Account candidate ranking, filesystem effects,
--  and durable Actual identity remain outside this package.
package HRA.Household_Actual_Draft is

   type Posting_Draft is record
      Account_Text : Unbounded_String;
      Amount_Text  : Unbounded_String;
   end record;

   package Posting_Draft_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Posting_Draft);

   type Record_Draft is private;

   function Start (Day : HRA.Dates.Date) return Record_Draft;
   function Day_Of (Draft : Record_Draft) return HRA.Dates.Date;
   function Description_Text (Draft : Record_Draft) return String;
   function Posting_Count (Draft : Record_Draft) return Natural;

   function Posting_At
     (Draft : Record_Draft;
      Index : Positive) return Posting_Draft
     with Pre => Index <= Posting_Count (Draft);

   function Set_Description
     (Draft : Record_Draft;
      Text  : String) return Record_Draft;

   --  General Record always retains the Ledger-domain minimum of two posting
   --  rows. Existing row order and retained row contents are preserved.
   function Resize_Postings
     (Draft           : Record_Draft;
      Requested_Count : Natural) return Record_Draft;

   function Set_Posting
     (Draft        : Record_Draft;
      Index        : Positive;
      Account_Text : String;
      Amount_Text  : String) return Record_Draft
     with Pre => Index <= Posting_Count (Draft);

   type Build_Status is
     (Success,
      Invalid_Account,
      Undeclared_Account,
      Invalid_Amount_Shape,
      Invalid_Quantity,
      Zero_Quantity,
      Invalid_Commodity,
      Missing_Primary_Commodity,
      Transaction_Rejected);

   type Build_Diagnostic is record
      Status           : Build_Status := Success;
      Posting_Index    : Natural := 0;
      Account_Status   : HRA.Account.Account_Status := HRA.Account.Success;
      Commodity_Status : HRA.Money.Commodity_Status := HRA.Money.Success;
      Ledger_Status    : HRA.Ledger.Transaction_Error := HRA.Ledger.Success;
      Message          : Unbounded_String;
   end record;

   --  Lower raw draft text to one typed balanced Ledger.Transaction using only
   --  admitted Household policy and Account declarations.
   --
   --  Posting amount syntax is either:
   --    SIGNED_QUANTITY
   --    SIGNED_QUANTITY COMMODITY
   --
   --  Omitted Commodity resolves only through the Household primary commodity.
   --  Every Account must resolve through the canonical admitted registry. Each
   --  posting owns its sign; complete multi-commodity balancing remains Ledger's
   --  existing transaction law.
   function Build_Transaction
     (State : HRA.Household.Household_State;
      Draft : Record_Draft;
      Tx    : out HRA.Ledger.Transaction;
      Diag  : out Build_Diagnostic) return Boolean;

private

   type Record_Draft is record
      Day         : HRA.Dates.Date;
      Description : Unbounded_String;
      Postings    : Posting_Draft_Vectors.Vector;
   end record;

end HRA.Household_Actual_Draft;
