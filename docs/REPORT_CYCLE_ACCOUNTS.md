# Cycle Accounts

Cycle Accounts now has two explicit owners rather than one report-shaped package
holding both meanings.

`HRA.Cycle_Accounts_Observation` owns exact current Account state inside one
already resolved Household cycle. `HRA.Report_Cycle_Accounts` owns only the
aligned movement comparison with the immediately previous cycle and the report
availability of that narrower projection.

Neither owner resolves Household policy, parses source text, inspects Account-name
prefixes, or owns rendering.

## Current Cycle Account observation

`HRA.Cycle_Accounts_Observation` consumes one typed cycle window, one admitted
Actual Ledger, and one observation day. The Account axis is every declaration in
admitted declaration order, including Accounts with zero activity.

For each Account:

- `Opening` is all admitted Actual movement before cycle start.
- `Debit` is positive Ledger movement from cycle start through the observation
  day, inclusive.
- `Credit` is negative Ledger movement over the same interval and retains its
  Ledger sign.
- `Movement = Debit + Credit`.
- `Closing = Opening + Movement`.

All values remain exact `HRA.Money.Balance`; Commodities are never collapsed.
Because the observation spans every declared Account, double-entry gives three
explicit portfolio laws: Opening total is zero, Movement total is zero, and
Closing total is zero.

The observation day must belong to the supplied half-open cycle. Future Actual
facts after that day remain admitted but do not enter the observation.

This observation is deliberately not report-owned. A later Daily Target consumer
can read the same exact closing evidence instead of querying the Actual Ledger a
second time or depending on a report package.

## Aligned previous-cycle comparison

`HRA.Report_Cycle_Accounts` compares the current movement through the observation
day with the immediately previous cycle at the same elapsed day count from cycle
start.

The baseline date is derived only from the two typed cycle windows and the current
observation day. Journal activity does not choose the baseline. The calendar-day
mapping itself belongs to `HRA.Cycle_Observation.Aligned_Day`; both Cycle
Accounts comparison and the pre-existing Envelope cycle comparison consume that
one temporal law rather than maintaining parallel alignment algorithms.

For each Account:

- current movement remains present,
- baseline movement remains present,
- `Difference = current movement - baseline movement`.

The Account axis must be identical on both sides. Current, baseline, and
difference movement totals each retain the double-entry zero law.

A previous cycle can be too short to contain the aligned elapsed day. That is a
narrow comparison limitation, not a failure of current Cycle Account state. The
Household report book therefore keeps the neutral current observation and
publishes the aligned comparison as typed unavailable.

## Report-book composition

`HRA.Household_Report_Observation` resolves one `HRA.Cycle_Observation` context
for the report composition. Its current window is passed to both Envelope
observation and `HRA.Cycle_Accounts_Observation`, so those consumers share one
temporal coordinate rather than independently inferring matching dates.

The resulting current observation is then passed to
`HRA.Report_Cycle_Accounts.Observe_Aligned`. Cycle Accounts does not add a
configurable range to `HRA.Report_Plan`. Daily Flow and Monthly Accounts continue
to consume their resolved report-plan periods; Cycle Accounts consumes Household
cycle evidence.

## Daily Target boundary unlocked

`HRA.Daily_Target_Scope` now owns the atemporal selection and reservation meaning
for Daily Target. The remaining temporal consumer can therefore be assembled
without a new Actual authority:

1. intersect selected obligations with `HRA.Plan_Temporal_Observation.Open_Plans`,
2. retain only Plans whose transaction dates belong to the typed current cycle,
3. read eligible Asset closing balances from `HRA.Cycle_Accounts_Observation`,
4. preserve reservation evidence as a separate deduction coordinate,
5. derive exact capacity before introducing any per-day rate representation.

This keeps Daily Target downstream of existing admitted and observed evidence and
prevents a report feature from becoming another Ledger query engine.
