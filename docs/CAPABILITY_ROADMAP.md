# hra capability and parity roadmap

ステータス: active inventory / implementation roadmap  
更新日: 2026-08-13  
Owner: hraがcanonical Household engineとして今後必要とする能力と完成条件

## 1. 目的

hraを小さく保つこと自体を目標にせず、`h-kernel`と`bqn-ledger`で実際に使われている能力を一度見渡し、何をAda側へ実装するか、何を意図的に実装しないか、どの順序で安全に進めるかを明示する。

この文書は機能数を競うchecklistではない。実装時には一つのuser valueまたはdomain capabilityをend-to-endで完成させ、不要な互換層や抽象を増やさない。

canonical source shapeは[`CANONICAL_HOUSEHOLD.md`](CANONICAL_HOUSEHOLD.md)、componentと依存方向は[`ARCHITECTURE.md`](ARCHITECTURE.md)が所有する。

## 2. 変えない前提

### One canonical source

正データはh-kernelと共有するprivate Household rootだけである。

```text
accounts.journal
actual.journal
plan.journal
budget.journal
budget.toml
household.toml
report.toml
issues.tsv
```

hra用database、同期copy、別schema、legacy fallbackを作らない。

### Reader parityとwriter authorityを分ける

同じsourceを正確に読めることは、書いてよいことを意味しない。hraのcanonical writer authorityは現在ない。Editorを実装しても、source別cutoverが承認されるまではcandidate previewまたはsynthetic sourceだけに限定する。

現在のprototype TUIにはActual writerへの入口が残っているが、canonical operationとして承認されていない。writer authority gateを満たすまでdaily canonical writeへ使用しない。

### Kernel lawは設定にしない

次は設定可能にしない。

- exact decimal Quantity
- AmountのCommodity保持
- Commodityごとのdouble-entry zero balance
- zero entryを持たないcanonical Balance
- inverse Postingとexplicit relationによるreversal
- identity / provenanceをdisplay textから復元しないこと
- invalid sourceのfail-closed admission

cycle、Envelope、Account policy、Report query/presentationはcanonical TOMLからadmitする。

## 3. 優先度と状態

優先度:

- **P0**: shared sourceを壊さず、h-kernelと同じ意味へ到達するため必須
- **P1**: daily useとengine比較に必要
- **P2**:高度な保守、機械連携、UX改善
- **Deferred**: 実需要またはauthorityが成立するまで作らない

状態:

- **implemented**: 現在のownerとtestが存在する
- **partial**: 表面はあるがsemantic parityまたは適用が未完了
- **missing**: ownerがまだない
- **prototype**: 試作品でありcanonical capabilityとして数えない

## 4. 現在地

更新日: 2026-08-15

### 現在の実装状況

| 領域 | 状態 | 現在の意味 |
|---|---|---|
| 固定8-source exact observation | implemented | 欠落・読取不能を拒否し、一回のsource bytesを保持 |
| 3 TOML admission | implemented | Budget、Household、Reportを型付き値へ変換しunknown keyと参照不整合を拒否。`[envelope-history]` もadmit |
| Journal admission | partial | 基本Transaction、Posting、Account declaration、balance law |
| Issues admission | partial | current private sourceを読めるがschema/lifecycle parityの精査が必要 |
| Accounting kernel | partial | exact Quantity、Commodity Balance、Transaction、基本集計 |
| SPARK proof core | foundation | bounded quanta、Commodity別balance、ordered reversal、Envelope/Backing式を独立証明。production接続は未完了 |
| Reports | partial | current renderable portfolioはcomplete typed report-book observation経由。section catalog/parityは未完了 |
| Report policy application | partial | `report.toml`はadmitするが全query/renderingへ未適用 |
| Editor / writer | prototype | safe-writer experimentはあるがcanonical authorityなし |
| TUI | prototype | fixed date、固定JPY、画面内rule、未承認writer入口が残る |
| Cross-engine verification | partial | synthetic golden testのみ。portfolio全体のparity harnessは未実装 |
| Envelope Registry | implemented | `HRA.Envelope.Envelope_Registry` をstable identityとして確立 |
| Expense Routing | implemented | `HRA.Envelope_Routing.Routing_History` でeffective-dated route解決 |
| Entitlement Fold | implemented | `HRA.Envelope_Entitlement` でbudget.journal movementをfold |
| Consumption calculation | implemented | `HRA.Envelope_Consumption` でActual Ledger + Routing → Consumptionを計算 |
| Backing by pool | implemented | `HRA.Backing_Policy` でpool別のBacking positionを計算 |

### Envelope-native migration progress

詳細は [`PROGRESS.md`](PROGRESS.md) を参照。

- [x] Step 1: `HRA.Envelope` — 完了 (test_runner に28テスト)
- [x] Step 2: `HRA.Envelope_Routing` — 完了 (test_runner に20テスト)
- [x] Step 3: `household.toml` の `[envelope-history]` parse — 完了 (9テスト + `hra check` 成功)
- [x] Step 4: `HRA.Envelope_Entitlement` — 完了 (test_runner に9テスト)
- [x] Step 5: `HRA.Budget_Source_Adapter` — 完了 (test_runner に16テスト)
- [x] Step 6: `HRA.Envelope_Consumption` — 完了 (test_runner に18テスト)
- [x] Step 7: `HRA.Backing_Policy` — 完了 (test_runner に13テスト)
- [x] Step 8: `Household_State` 再構成 + report 接続 + `hra-budget` 退役 — 完了 (test_runner に3テスト + 旧コード退役)

現在の`report`出力は比較・開発確認用であり、canonical resultではない。

## 5. Canonical source admission

### P0: Journal graph parity

- `include`を読み飛ばさず、document相対pathで再帰解決する
- include cycleとduplicate loadをtrace付きで拒否する
- root source bytesとresolved graphを同一observationとして扱う
- parse errorにsource path、line、column、raw contextを付ける
- CRLF、UTF-8、空file、末尾newlineを明示的に扱う
- unknown directiveとunknown metadataを黙って捨てない

### P0: Account admission

- `accounts.journal`だけをAccount declarationのownerとする
- AccountTypeをprefixから推測しない
- optional default Commodityをadmitする
- Actual、Plan、Budgetの全Posting Accountをregistryへ照合する
- duplicate/conflicting declarationを拒否する

現在のprefix inferenceはmigration中の仮実装であり、parity完了時に除去する。

### P0: Actual admission

- multi-Postingをfirst-classで保持する
- Posting orderを保持する
- status、description、memo、metadataを保持する
- optional durable `event-id`をtyped identityへadmitする
- `reverses` relationを既知Actualへ解決する
- duplicate identity、self reversal、二重reversalなどのlawを明示する
- ordinary identity-free Actualを許す範囲をh-kernel contractと揃える

### P0: Plan admission

- `plan-id`、due date、amount、source/destination Postingを保持する
- lifecycle statusをtyped valueへする
- completion relationをActual identity/provenanceへ接続する
- recurrence metadata (`recur`, `series`, `anchor`, `offset`)を保持する
- open/all、overdue/upcoming、related Planを導出できるようにする
- display textやlist indexをidentityにしない

### P0: Budget movement admission

- `budget.journal`のsource orderを保持する
- movement date、memo、from/to Budget Account、Amountをtyped factへする
- provenanceを保持する
- Entitlement、Remaining、Backingへ同じmovement factを渡す

### P0: Issues admission

- current canonical columns、status、open/closed lifecycleを厳格にadmitする
- stable Issue identityを保持する
- close dateとdecision/detailsを失わない
- Issueから会計factを暗黙生成しない
- Issue→Planなどのrelationはexplicit evidenceがある場合だけ扱う

### P0: Complete Household validation

- 8 sourceを個別に読めるだけで成功としない
- Account、Commodity、Envelope、Plan、Actual、Budget、Issue relationをcross-sourceで検証する
- source-local errorを空vectorやdefault policyへ変換しない
- failure precedenceを決め、CLI/TUIで共通利用する

## 6. Accounting and policy kernel

Actual、Plan reserve、Envelope、Backingに共通する金額式は[`PROOF_CORE.md`](PROOF_CORE.md)のSPARK境界を通す。source admissionとidentity/provenanceはordinary Ada、bounded exact arithmeticはSPARKが所有する。proof foundationの存在だけでproduction計算を証明済みとは扱わない。

### P0

- typed Gregorian Dateとinclusive/half-open Period
- exact multi-Commodity Balance algebra
- Account balance、period movement、total balance
- Trial Balanceとaccounting equation
- P&LのIncome/Expense normalization
- Balance SheetのAsset/Liability/Equity/current earnings
- reversal lawとdurable identity/provenance
- Budget Entitlement、Consumption、Refund、Remaining
- Plan reserveとpost-Plan headroom
- Backing required、funding、surplus、unassigned、reconciliation delta
- cycle resolution (`income-anchor`)

### P1

- Plan temporal statusとrecurrence relation
- cycle-to-cycle comparison
- date/category flow matrix
- month/account movement matrix
- Daily Target
- Home calendar attention facts

### P2 / future boundary

- Liability positionの専用projection
- Commodity conversionまたはmarket valuation
- reservation funding location
- backing-pool別surplus

Commodity conversion等は現在のBalanceへ暗黙に追加しない。別policyとprojectionが必要になった時点で設計する。

## 7. Report portfolio

### 共通Report contract

すべてのReportは次を守る。

- 一回admitした同じ`Household_State`からpureに生成する
- rendererがsourceを再読込しない
- clockはapplication boundaryで一回だけ取得する
- `latest`はprocess-local calendar dayであり、Journal最大日ではない
- date rangeのinclusive/half-open semanticsを型で区別する
- multi-Commodityを一つの数へ潰さない
- sourceまたはpolicyのunknown evidenceを黙って除外しない
- canonical ordering、zero-row policy、empty-state表示をReportごとに定義する
- human rendererとmachine rendererが同じsemantic resultを使う
- Account、Plan、Issue identityとprovenanceを表示用文字列から再構築しない

### Target report catalog

`bqn-ledger`のcurrent retained portfolioを基準に、次の12 sectionを対象とする。順序もcanonical report-book候補として保持するが、Ada内部module数を12へ固定するものではない。

| # | Report | 優先度 | 必要な出力 | hra現在地 |
|---:|---|---|---|---|
| 1 | Envelope & Backing | P0 | Envelope別Entitlement、Consumption、Refund、Remaining、Plan reserve、headroom、Funding、required、surplus、unassigned、reconciliation | partial。policy適用と式parityが必要 |
| 2 | Account Balances | P0 | as-of残高、AccountType、Commodity別値、balanced status | rendererあり。date/policy/ordering parityが必要 |
| 3 | Balance Sheet | P0 | Asset、Liability、Equity、current earnings、totals、equation delta | partial |
| 4 | Profit and Loss | P0 | period Income/Expense lines、totals、net income | partial |
| 5 | Recent Journal | P1 | through date、count、Transaction identity、description、ordered Postings、Commodity | rendererあり。metadata/identity parityが必要 |
| 6 | Planned Payments | P1 | open Plan、due、amount、status、destination、recurrence、overdue/upcoming | missing |
| 7 | Current-cycle Accounts | P1 | resolved cycle内のAccount movement/balance | missing |
| 8 | Cycle Comparison | P1 |明示window間のIncome/Expense/Account差分 | missing |
| 9 | Monthly Accounts | P1 | month × Account movement、period totals | missing |
| 10 | Daily Flow | P1 | date × category/account flow、calendar gaps、block/period total | missing |
| 11 | Daily Target | P1 | eligible assets、open obligation、already excluded、capacity、days、Commodity別rate | missing |
| 12 | Issues | P1 | open Issue、due、amount、category、relation/lifecycle evidence | partial |

### Trial Balance

Trial Balanceは会計検証とstandalone inspectとしてP0で維持する。12-section daily report bookへ独立sectionとして入れるか、Account Balances/operationsに統合するかはReport catalog実装時に決める。内部resultを削除して表示上だけbalancedと推測してはならない。

### Report request and presentation

`report.toml`の次の値を実際のrequestへ適用する。

- Trial Balance / Balance Sheetの`as-of`
- P&L、Daily Flow、Monthly Accountsの`from` / `through`
- Recentの`through` / `count`
- Daily Flowの`max-date-columns`
- negative style
- hierarchy/amount colors
- calendar markers

CLIの明示date/domainは対応するquery coordinateだけをoverrideし、presentationを無効にしない。

### Output surfaces

- **P0 human text**: terminal向け、UTF-8 exact output、色の有無を制御可能
- **P1 compact text**: engine比較とshell利用向けの安定した簡潔表現
- **P1 machine output**: JSON等。human textをparseさせずsemantic resultを公開
- **P1 report metadata**: key、label、order、利用可能surfaceをsource読込なしで列挙
- **P2 report selection**: one section、ordered selection、`all`
- **Deferred cache**: 実測で必要になるまでreport cache/background refreshを実装しない

## 8. Read-only CLI and operations

### P0

- `check`: complete canonical admissionとlaw verification
- `report`: current policyに基づくreport book
- `report REPORT_KEY`: one report section
- explicit `--base`
- environment root selection
- non-zero exit statusとbounded diagnostic

### P1

- `journal list`
- `plans open|all|overdue|upcoming|related`
- `accounts list`とtype/Commodity filter
- `issues list`
- `inspect`: identity、provenance、source roleを含むbounded structural view
- explicit historical report date/range/domain
- report catalog/metadata
- hledger向けone-way export

### P2

- exact semantic query
- compact report summary
- doctor（toolchain、terminal、canonical root readiness）
- canonical source allowlistによるuser-directed `$EDITOR`起動

repository test suiteとHousehold readiness checkを同じcommandにしない。

## 9. Editor operations

EditorはUIより先にtyped operationとして作る。

```text
intent
  -> typed identity/input
  -> pure candidate
  -> complete-source admission
  -> semantic preview
  -> approved publication effect
  -> complete Household post-admission
  -> fresh state
```

### Actual

- ordinary Expense
- Income
- Asset transfer
- arbitrary multi-Posting Transaction
- compensating reversal/correction
- history/list and candidate preview
- destructive edit/deleteは実装しない

### Plan

- add
- date/amount edit
- finish/complete to Actual
- Plan→Budget sync
- recurrence successor replenishment
- open/all/overdue/upcoming/related selection
- skip/cancel/pause等は現在のcanonical contractに根拠ができるまでDeferred

### Budget

- typed movement candidate
- Envelope allocation/reallocation
- Plan completionからのBudget sync
- previewでbefore/afterとprovenanceを表示

### Accounts

- list/filter
- add declaration
- AccountType/default Commodity validation
- rename/deleteはidentity migration contractなしに実装しない

### Issues

- list
- add
- close/resolve/drop lifecycle
- relation追加はtarget identity lawが成立した種類だけ

### Specialized operations

travel exchange/friend-paid等、canonical 8 sourceにownerを持たない実験機能はhra parity対象へ自動追加しない。普通のmulti-Commodity Journalで表せる部分と、追加source/policyが必要な部分を分けて判断する。

## 10. Safe writer and authority gate

source別writerをcanonical operationとして有効化する前に、最低限次を満たす。

1. 対象operationのh-kernel/BQN semantic parity
2. exact expected source bytes
3. pure complete candidate generation
4. complete-source pre-admission
5. human-readable preview
6. immediate stale recheck
7. ignored backup
8. sibling staged file
9. atomic publication
10. complete Household post-admission
11. targetがjust-published candidateのままの場合だけchecked restore
12. crash/filesystem/concurrent writer failure tests
13. private disposable-copy rehearsal
14. single-writer運用と明示的authority approval

cross-file operationでfilesystem全体のatomicityを装わない。必要sourceを事前観測し、順序付きpublicationとsourceごとのchecked restoreを設計する。

## 11. TUI

現在のTUIを継ぎ足して完成扱いにせず、typed read/operation ownerができた順に薄いadapterとして接続する。

### P1 daily surface

- calendar-first Home
- selected-day Actual/Plan/Issue/cycle evidence
- Record（ordinaryからmulti-Postingへ自然に拡張）
- Plan completion/replenishment
- Budget movement
- Accounts/Issues maintenance
- Reports viewport
- Inspect
- keyboard-onlyで全操作可能
- visible objectのtyped identityを保持
- path/date/Account IDの暗記を要求しない
- operation後にfresh complete Household stateへ戻る

### P2 UX

- mouseを同じvisible operationへの補助入口として追加
- focus/status/breadcrumb
- help/keybinding画面
- themeとlocal UI preference
- terminal resize/width-aware layout
- report search/filter

UIへaccounting rule、source basename、writer law、report key一覧を複製しない。

## 12. Verification and engineering

### P0 evidence

- domain package別unit test
- parserのvalid/invalid fixture
- multi-Commodity property/law test
- date/leap/boundary test
- identity/provenance/reversal test
- complete 8-source synthetic fixture
- private内容を出力しないcanonical rehearsal
- clean buildでwarningなし
- non-zero failure exit status

### P1 parity

- 同じsynthetic Householdに対するh-kernel/hra semantic comparison
- 12 report resultのgolden comparison
- human renderingとは別のmachine-neutral comparison
- Posting/Account/Envelope orderの比較
- empty/zero/multi-Commodity/invalid evidence corpus
- writer failure injection
- Linux/macOS、可能ならWindowsのpublication差確認

### P2

- fuzz/property-based parser test
- performance benchmarkとregression threshold
- coverage reporting
- release artifact/installation check
- terminal capability matrix

private source値をfixture、CI log、Issue、PRへ転記しない。

## 13. 実装順序

次の順序を基本とする。

1. **SPARK proof foundation（完了、production接続は継続）**
2. **Journal graphとnamed source admission**
3. **Account registry照合とtyped Date/identity/provenance**
4. **Actual/Plan/Budget/Issueのcomplete Household validationとproof core接続**
5. **Report policy resolutionとP0 reports**
6. **P1の12-report portfolioとmachine-neutral parity**
7. **read-only CLI/Inspect/Export**
8. **pure typed Editor operationsとpreview**
9. **safe writerのfailure law**
10. **source別writer authority cutover（必要な場合だけ）**
11. **typed ownerを利用するTUI再構成**
12. **実測に基づくcache、performance、追加UX**

TUIを先に大きくするとdomain ruleとwriter ruleが画面へ複製される。Reportを先に文字列だけ増やすと比較不能になる。そのため、admission → semantic result → renderer/CLI → Editor effect → TUIの順を守る。

## 14. 完成の見方

「h-kernelまたはbqn-ledgerに同名commandがある」だけではhra capability完成としない。一つの能力は次が揃ったとき完成する。

- canonical ownerが一つ
- typed input/outputとinvalid state
- source/policy/clock/effect boundary
- exactness、ordering、identity、provenance
- focused testとcomplete Household test
- user-facing CLIまたはTUI route
- current document
- writerの場合はauthority gate

この条件を守れば、機能が増えてもCLI、TUI、Report、testへ同じdomain ruleを重複実装せず、hraを比較的コンパクトに保てる。
