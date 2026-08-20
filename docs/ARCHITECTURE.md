# HRA architecture

ステータス: active foundation  
更新日: 2026-08-20

Report、Editor、TUIを含む全体の実装対象とparity順序は[`CAPABILITY_ROADMAP.md`](CAPABILITY_ROADMAP.md)が所有する。

## Dependency direction

```text
CLI / TUI
  -> Canonical_Source filesystem observation
  -> source-specific admission (Journal / Entitlement / Config / Issues)
  -> validated Household_State
  -> normalized proof facts
  -> SPARK Proof_Core (Transaction / Plan / Envelope / Backing arithmetic)
  -> Money / Account / Ledger / Plan / Envelope / Backing / Report
  -> Render

edit intent
  -> pure complete-source candidate
  -> source-specific admission
  -> approved writer effect
```

会計計算はpath、environment variable、terminal、renameを知らない。Renderはsourceを読まない。CLI/TUIはAccount分類、期間、Envelope/Backing rule、writer lawを再実装しない。

現在のhuman check / report commandはそれぞれ`HRA.Household_Check_Observation`および`HRA.Household_Report_Observation`をfocused semantic boundaryとする。check commandはadmitted factsのtyped summaryを`HRA.Household_Check_Observation`から受け取り表示する。report commandは一つのadmitted `Household_State`とapplication境界で一回取得した観測日から、resolved query、current section order、Envelope/Backing、Trial Balance、Balance Sheet、P&L、Recent Journal、Planned Payments、open Issuesを一つのtyped report-book observationとしてall-or-nothingで生成する。CLIはtyped summaryまたはtyped sectionを順にrendererへ渡すだけで、rendererやCLI presentationは`Household_State`、Ledger、source、clockを受け取らない。

SPARK境界は[`PROOF_CORE.md`](PROOF_CORE.md)が所有する。parserやUIを全面SPARK化せず、ordinary Ada admissionが正規化したbounded factsだけをpure proof coreへ渡す。現在、Envelope Remaining/Headroomは`HRA.Envelope_Position`経由でSPARK Proof_Coreに接続済み。Backingのproof result接続は独立した次段として扱う。

## Stable invariants

設定可能にしないkernel law:

- Quantityはexact decimalである
- AmountはCommodityを必ず保持する
- 異なるCommodityを暗黙に相殺しない
- TransactionはCommodityごとにbalancedである
- reversalは対象postingのexact inverseとexplicit relationを持つ
- identityとprovenanceをdisplay textから復元しない
- invalid sourceを正常なdomain valueへ変換しない
- current configurationからhistorical identityやroutingを復元しない

設定またはhistory sourceからadmitするpolicy:

- cycleとprimary Commodity
- current Envelope membership、pacing、backing pool
- stable Envelope identity history
- explicit historical Expense routingとFulfillment routing
- Report query defaultとpresentation

policyはTOML構文のまま計算へ流さず、source-specific parserでtyped valueへ変換する。

## Canonical source ownership

current Household rootは次の8 sourceだけで構成する。

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

owner境界:

- `accounts.journal`: accounting Account declaration
- `actual.journal`: occurred accounting facts
- `plan.journal`: future intention / commitment evidence
- `entitlement.journal`: Envelope Entitlement origin / transfer history。accounting Journalではない
- `envelope.toml`: current Envelope membership / presentation / Backing topology
- `household.toml`: cycle、money、stable Envelope history、routing
- `report.toml`: report query / presentation policy
- `issues.tsv`: Issue facts

`HRA.Canonical_Source`はbasename、path解決、一回のexact-byte observationだけを所有する。Journal/TOML/TSVを一つのgeneric parserへ統合しない。各syntaxとdomain meaningはnamed admission ownerが持つ。

`HRA.Household`はcomplete observationから各ownerを呼び、cross-source referenceを検証し、一つの`Household_State`を組み立てる。欠落・parse failure・未解決referenceを黙って飛ばさない。

## Native Entitlement pipeline

Envelope stockはaccounting Accountから再構成しない。

```text
entitlement.journal
  -> HRA.Entitlement_Journal admission
  -> admitted Entitlement history
  -> observation through Observed_Through
  -> Envelope Entitlement
```

`Envelope_Registry`はstable identity universe、`Envelope_Config.Envelope_Policy`はcurrent membershipを所有する。retired identityがhistoryに残ってもcurrent positionへ自動混入させない。

Expense Consumption、Plan/Actual Fulfillment、open Plan Commitmentはそれぞれ独立ownerから同じEnvelope identityへ投影され、`HRA.Envelope_Position`がproof-backed Remaining / Headroomを構成する。BackingはそのPositionを入力として消費し、欠損をsilent zeroへしない。

## Admission failure and observable conditions

HRAは「意味をadmitできない状態」と「admitできるが対話が必要なHousehold状態」を分ける。

### Admission failure

sourceを一つのHousehold factとして読めない場合はfail closedで拒否する。

例:

- parse failure
- undeclared Account / Commodity
- unknown or conflicting stable identity
- broken reversal / completion relation
- invalid routing shape
- cross-source reference conflict
- proof-facing rangeへのnon-exact conversion

これらをzero、fallback、current configからの推測へ変換しない。

### Observable household condition

意味が明確であれば、困った状態そのものは有効な観測結果である。

例:

- negative Envelope Remaining
- negative post-Plan Headroom
- under-backed funding pool
- Unallocated balance
- unrouted Expense or Plan claim
- PlanとActualのvariance
- 将来支払に対する資金不足

これらをadmission failureやproof failureにしない。SPARKが証明するのは「良いHousehold状態であること」ではなく、admitted factsからその状態をexactに計算していることである。

## Temporal boundary

`Observed_Through`はknowledge horizon、`Selected_Day`はpresentation / focus coordinateである。

- TUI navigationでSelected Dayを過去や未来へ動かしてもObserved Throughを暗黙に変更しない
- future evidenceをpast observationへ漏らさない
- effective-dated routingのfuture decisionでpast meaningを書き換えない
- typed baselineを得た後にcurrent configやsource anchorから同じ意味を再推論しない

past / present / futureを同じHousehold evidenceから観測できるようにしつつ、「知っている範囲」と「見ている日」を分離する。

## Dialogue and writer boundary

入力と管理は単なるform submissionではなく、観測と提案を往復できる対話として構成する。

```text
admitted Household
  -> Observation
  -> Dialogue
  -> Proposal
  -> Preview through the same domain calculation
  -> explicit human decision
  -> named source writer
  -> complete-source candidate admission
  -> durable source fact
```

CLI、TUI、GUI、AIはObservationを表示しProposalを組み立ててよいが、Household semanticsやwriter authorityを所有しない。preview専用の別計算をUIに実装せず、productionと同じdomain calculationで変更後の状態を観測する。

AIも同じ境界に従う。AIはallocation、資金移動、Plan、Issue対応などを提案できるが、意味を推測してcanonical sourceを直接変更する権限にはならない。明示されたdecisionの後に、承認されたnamed writerだけがsource candidateを作る。

HRAには現在、shared canonical sourceへの承認済みwriter authorityはない。reader parity、安全なcandidate generation、publication failure lawとwriter cutoverを分離する。

## Current architecture chapters

1. **Observation foundation（完了）**: fixed 8 sourceを一回だけexact-byteで観測し、欠落を拒否する
2. **Current typed configuration（完了）**: `envelope.toml`、`household.toml`、`report.toml`をnamed typed policyへadmitする
3. **Native Entitlement source（完了）**: `entitlement.journal`をAccount Ledgerから独立してadmitし、stock origin / transfer historyを所有する
4. **SPARK proof foundation（継続）**: bounded normalized factsとTransaction / Envelope / Backing lawをproduction ownerへ段階的に接続する
5. **Journal graph parity（次）**: include、metadata、source provenance、Actual/Plan固有meaningをadmitする
6. **Cross-source validation**: Account、Envelope、Plan、Actual、Issue identity / provenance relationをcomplete stateで検証する
7. **Semantic parity**: synthetic corpusとprivate rehearsalでh-kernelと比較する
8. **Interactive observation**: Observation -> Proposal -> Preview -> DecisionをCLI/TUI/GUI/AIで共有する
9. **Writer evaluation**: reader完成とsource別authority cutoverを分離して判断する

各chapterは前段のsilent fallbackを残さない。将来機能を想定したplugin、generic repository、universal event frameworkは作らない。
