# Daily Target scope authority

Daily Target is assembled from two existing admitted source families. It does not introduce a ninth canonical source and it does not reparse `plan.journal`.

## Ownership

`household.toml` owns the long-lived selection of Asset Accounts that may contribute to ordinary daily spending capacity. Each selection already has a stable `id` and an Account coordinate. Account syntax, declaration, uniqueness, and Asset type are admitted by canonical Household admission and are not re-admitted by `HRA.Daily_Target_Scope`.

`HRA.Plan_Admission.Plan_Journal` remains the general Plan authority. Its admitted transaction entries already retain parser-produced Journal metadata and physical provenance. `HRA.Daily_Target_Scope` assigns Daily Target meaning only to the metadata keys:

- `daily-target-id`
- `reservation-id`
- `reservation-amount`
- `reservation-commodity`

Transactions without `daily-target-id` remain ordinary Plans and publish no Daily Target obligation.

## Narrowing law

General Plan admission is not narrowed to satisfy Daily Target. Only a Plan explicitly selected by `daily-target-id` is required to project to one outgoing household commitment:

- exactly one negative Asset posting
- exactly one positive Expense or Liability posting
- the positive destination amount is the obligation amount

Therefore a valid multi-post Plan remains admissible when it is not selected for Daily Target. Selecting the same Plan makes the narrower Daily Target boundary fail closed instead of changing general Plan semantics.

## Selection identity

Household Asset selections and Plan obligation selections share one Daily Target selection identity universe. Duplicate identities across either source family are rejected. This prevents two source coordinates from silently claiming one semantic selection identity.

## Reservation evidence

Reservation metadata never creates an implicit Daily Target selection. When present it must be complete and prove:

- a non-empty durable reservation identity
- a positive exact amount
- the same Commodity as the selected Plan obligation
- an amount no greater than the obligation
- a reservation identity not used by another selected obligation

Amounts are rejected rather than clamped or converted.

## Empty policy

The current HRA canonical format allows `[daily-target]` to be absent. An absent policy with no selected Plan obligations therefore admits an explicit empty scope. Plan obligations without any eligible Asset selection fail admission.

## Temporal ownership stays outside the scope

`HRA.Daily_Target_Scope` deliberately does not decide whether a selected Plan is currently open or belongs to the current cycle. Those meanings already have typed owners.

A later Daily Target observation should combine this scope with:

- the current typed cycle window
- Actual balances through the observation day
- `HRA.Plan_Temporal_Observation` open Plans

Only selected Plans that are both open at the observation day and scheduled inside the current cycle contribute an obligation. A selection therefore needs no embedded cycle identifier and the scope does not duplicate Plan lifecycle or cycle authority.

The intended derived evidence remains visible as separate quantities:

`capacity = eligible assets - (current-cycle open selected obligations - already excluded reservations)`

The final per-day rate is a report projection of that evidence, not an authority of its own. A failure of this narrow Daily Target projection should make only that report section unavailable, not invalidate the admitted Household or unrelated report sections.
