# Report Flow

`HRA.Report_Flow` owns the shared typed basis for Daily Flow and Monthly Accounts.

It consumes an already-admitted Actual Ledger plus the two independently resolved
`Closed_Period` coordinates from `HRA.Report_Plan`. It performs no source I/O,
no report configuration parsing, and no rendering.

The shared laws are:

- Account meaning comes from the admitted Account registry, never name prefixes.
- Income postings are sign-normalized for report presentation; Expense postings
  retain Ledger sign, so refunds remain negative Expense.
- Asset, Liability, and Equity postings do not become flow.
- Daily and Monthly observations are built in one pass over Actual transactions.
- Daily activity is ordered by Date; Account rows retain declaration order.
- Monthly time coordinates include every calendar month touched by the resolved
  range, including partial and zero-flow months.
- All arithmetic remains exact `HRA.Money.Balance`, preserving Commodities.
- Renderers receive typed observations and do not query the Ledger.

`HRA.Household_Report_Observation` is the portfolio owner. It resolves report
policy once, then passes `Daily_Flow` and `Monthly_Accounts` periods into this
package beside the other report sections.
