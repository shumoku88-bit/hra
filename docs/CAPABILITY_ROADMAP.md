# HRA capability and parity roadmap

ステータス: active implementation roadmap  
更新日: 2026-08-20  
Owner: HRAがcurrent canonical Household engineとして次に獲得する能力と順序

## 1. この文書の役割

この文書はsource contractのauthorityではない。canonical source topologyと意味は
[`CANONICAL_HOUSEHOLD.md`](CANONICAL_HOUSEHOLD.md)およびactual shared Household contractが所有し、
依存方向は[`ARCHITECTURE.md`](ARCHITECTURE.md)、証明可能な金額境界は
[`PROOF_CORE.md`](PROOF_CORE.md)が所有する。

ここでは、HRAをh-kernelへ意味論的に追いつかせるための**次の能力と順序**だけを保持する。
過去のmigration step、test件数、旧source名はgit historyと[`PROGRESS.md`](PROGRESS.md)へ置く。

## 2. 変えない前提

### One canonical Household

HRA専用database、同期copy、別schemaを作らない。h-kernelと同じuser-owned private rootを読む。

```text
accounts.journal
actual.journal
plan.journal
entitlement.journal
envelope.toml
household.toml
report.toml
issues.tsv
```

- `entitlement.journal` はaccounting Journalではない
- `envelope.toml` はcurrent Envelope membership / presentation / Backing topologyを所有する
- `household.toml` はcycle、money、stable Envelope history、routing等を所有する
- current configからhistorical meaningを逆算しない
- retired source名、compatibility alias、fallback、duplicate authorityを作らない

### Reader parity is not writer authority

同じsourceを正確に読めることは、書いてよいことを意味しない。
HRAには現在、shared canonical sourceへの承認済みwriter authorityはない。
writer実装はcandidate生成、安全なpublication law、synthetic testとして育て、source別cutoverを別判断にする。

### Kernel lawを設定へ逃がさない

次はconfiguration optionにしない。

- exact decimal Quantity
- AmountのCommodity保持
- Commodity別double-entry zero balance
- canonical Balanceのzero-entry除去
- stable identity / provenanceをdisplay textから復元しない
- explicit reversal relation
- invalid sourceのfail-closed admission
- historical meaningをcurrent configから再構成しない

## 3. 現在のfoundation

現在HRAには次のownerがある。

- fixed 8-source observationとcanonical basename resolution
- exact `Money.Quantity` / multi-Commodity `Balance`
- Account registryとJournal Transaction / Posting
- typed Gregorian Date / Period
- native `Entitlement_Journal` origin / transfer admission
- stable `Envelope_Registry`
- effective-dated Expense routing
- Entitlement / Consumption / Fulfillment / Commitment / Position / Backing observation
- typed Household / Envelope / Report configuration admission
- Plan identityとopen/completed observationのfoundation
- Issue admissionとtyped temporal coordinatesのfoundation
- complete Household report-book observationのfoundation
- Home TUI semantic navigationとUTF-8 terminal boundary
- focused test inventory owned by `tests/hra_tests.gpr`
- bounded exact arithmeticのSPARK proof coreとMoney bridge
- safe writer failure laws。ただしcanonical writer authorityは未承認

この一覧は「完成」を意味しない。ownerが存在してもh-kernel parityがpartialな領域は下のP0/P1で追跡する。

## 4. P0: canonical admissionとidentity/provenance

### Journal document graph

次の大きなfoundation gap。

- document-relative `include` を再帰解決する
- include cycleをtrace付きで拒否する
- duplicate document loadを拒否する
- rootとincluded sourceのpath / line / source locationを保持する
- parse failureをsource-local diagnosticとして保持する
- CRLF、UTF-8、空file、末尾newlineを明示的に扱う
- unknown directive / metadataを黙って捨てない

generic scanner frameworkを作らず、Journal document admissionとして所有する。

### Actual completeness

- multi-Postingをfirst-classのまま保持する
- Posting order、memo、metadata、source provenanceを保持する
- durable `event-id`をtyped identityへadmitする
- `reverses`を既知Actualへ解決する
- duplicate identity、self reference、invalid reversal chainをfail closedにする
- generated reversalとsource-admitted reversalのlaw境界を明示する

### Plan lifecycle parity

- stable `plan-id`とsource provenanceを保持する
- open / completed / overdue / upcomingを一つのlifecycle ownerから導出する
- Actual completionとのexplicit relationを保持する
- recurrence successorをdisplay textやlist indexから推測しない
- Envelope Fulfillment / Commitmentは同じadmitted Plan identityを参照する

### Complete Household validation

8 sourceを個別にparseできるだけで成功としない。

- Account、Commodity、Envelope、Plan、Actual、Issueのcross-source referenceを検証する
- dangling identity / relationを拒否する
- source-local failureをempty/defaultへ変換しない
- CLI / TUI / Reportで同じadmitted `Household_State`を使う

## 5. P0: Envelope / Backing parity

現在のnative Entitlement pipelineをauthorityとして育てる。

```text
entitlement.journal admitted history
  -> Entitlement through Observed_Through
  -> Actual stock Consumption
  -> Plan/Actual Fulfillment
  -> open Plan Commitment
  -> proof-backed Envelope Position
  -> Backing observation
```

維持するlaw:

- explicit Commodity stock origin
- `Observed_Through`より未来のfactを過去へ漏らさない
- Expense routingのfuture decisionでpast meaningを書き換えない
- current Envelope membershipとstable historical identityを分離する
- Remaining / Headroomをclampしない
- multi-Commodityを相殺しない
- missing required Positionをsilent zeroへしない

次はproduction Backing算術をSPARK resultへ接続するかを、現在のownerを壊さず観察する。

## 6. P0: Issue relation lifecycle

Issueは単なるメモではなく、Household decisionの未確定状態として扱う。

候補となるexplicit transition:

```text
Issue -> Actual
Issue -> Plan
Issue -> Plan cancellation / retirement
Issue -> Closed without financial fact
Issue -> successor Issue
```

relationはIssue titleや近い日付から推測しない。stable identityとexplicit evidenceを使う。
Actual / Plan writer authorityとは分離して設計する。

## 7. P1: Reports and temporal observation

既存のtyped report-bookを広げる。rendererに新しいsource authorityを持たせない。

優先:

- Account Balances / Trial Balance / Balance Sheet / P&L parity
- Recent Journal metadata / provenance
- Planned Payments lifecycle detail
- Envelope & Backing explanation
- same-cycle Change
- aligned previous-cycle comparison
- Monthly Accounts / Daily Flow
- Issues relation/lifecycle view

Reportは一回admitした同じ`Household_State`からpureに生成し、human/machine surfaceで意味計算を複製しない。

## 8. P1: TUI / GUI

UIはdomain ownerではなくthin application surfaceにする。

- HomeはSelected DayとObserved Throughを分離する
- calendar navigationでfuture/pastへ移動してもknowledge horizonを勝手に変えない
- typed identityを選択状態として保持する
- Report / Issue / Plan / Actualのdetailへ同じsemantic observationから進む
- UTF-8 / terminal cell widthはTUI adapter境界が所有する
- writer authority確立前にUI操作だけをcanonical mutationへ昇格させない

Brick相当の便利さを目標にしても、UI都合のduplicate domain modelは作らない。

## 9. P2 / Deferred

実需要が成立するまで作らない。

- Commodity conversion / market valuation
- report cache / background refresh
- plugin architecture
- generic repository/session framework
- HRA専用canonical database
- compatibility source aliases
- implicit Plan-to-Envelope synchronization

必要になった場合も、current exact Balanceやcanonical source contractへ暗黙に混ぜず別policy / projectionとして設計する。

## 10. 実装順序

現在の基本順序:

1. Journal document graph / source provenance
2. Actual identity / reversal completeness
3. Plan lifecycle completeness
4. Issue relation lifecycle
5. Complete Household cross-source validationを締める
6. Report portfolio / temporal observation parity
7. TUI / GUI detail surfaces
8. writer authorityをsource別に判断

一つの能力をend-to-endで完成させる。小さなPR数を増やすこと自体を目的にせず、同時に互換shellや巨大frameworkも作らない。
