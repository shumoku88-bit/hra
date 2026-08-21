# Cycle Accounts

`HRA.Report_Cycle_Accounts` owns exact Account state inside one already resolved
Household cycle and the aligned movement comparison with the immediately previous
cycle.

It consumes typed cycle windows and the admitted Actual Ledger. It does not
resolve Household policy, parse source text, inspect Account-name prefixes, or
own rendering.

## Current Cycle Accounts

The Account axis is every declaration in admitted declaration order, including
Accounts with zero activity.

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

## Aligned previous-cycle comparison

The comparison does not compare whole cycles by accident. It compares the
current movement through the observation day with the immediately previous cycle
at the same elapsed day count from cycle start.

The baseline date is derived only from the two typed cycle windows and the current
observation day. Journal activity does not choose the baseline. The calendar-day
mapping itself belongs to `HRA.Cycle_Observation.Aligned_Day`; both Cycle
Accounts and the pre-existing Envelope cycle comparison consume that one temporal
law rather than maintaining parallel alignment algorithms.

For each Account:

- current movement remains present,
- baseline movement remains present,
- `Difference = current movement - baseline movement`.

The Account axis must be identical on both sides. Current, baseline, and
difference movement totals each retain the double-entry zero law.

A previous cycle can be too short to contain the aligned elapsed day. That is a
narrow comparison limitation, not a failure of current Cycle Accounts. The
Household report book therefore keeps current state and publishes the aligned
comparison as typed unavailable.

## Report-book composition

`HRA.Household_Report_Observation` resolves one `HRA.Cycle_Observation`
context for the report composition. Its current window is passed to both Envelope
observation and Cycle Accounts, so those sections share one temporal coordinate
rather than independently inferring matching dates.

Cycle Accounts does not add a configurable range to `HRA.Report_Plan`. Daily
Flow and Monthly Accounts continue to consume their resolved report-plan periods;
Cycle Accounts consumes Household cycle evidence.

## Why Daily Target follows later

The admitted Household policy already has long-lived Daily Target Asset
selection, but HRA does not yet have the separate current-cycle Plan obligation
and reservation evidence required to define Daily Target capacity without a
hidden fallback. Cycle Accounts can be expressed completely from authorities
that already exist, so it is added first.
