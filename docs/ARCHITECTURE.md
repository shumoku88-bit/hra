# aledger architecture

ステータス: active foundation

Report、Editor、TUIを含む全体の実装対象とparity順序は[`CAPABILITY_ROADMAP.md`](CAPABILITY_ROADMAP.md)が所有する。

## Dependency direction

```text
CLI / TUI
  -> Canonical_Source filesystem observation
  -> source-specific admission (Journal / Config / Issues)
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

会計計算はpath、environment variable、terminal、renameを知らない。Renderはsourceを読まない。CLI/TUIはAccount分類、期間、予算、writer lawを再実装しない。

SPARK境界は[`PROOF_CORE.md`](PROOF_CORE.md)が所有する。parserやUIを全面SPARK化せず、ordinary Ada admissionが正規化したbounded factsだけをpure proof coreへ渡す。現在、Envelope Remaining/Headroomは`ALedger.Envelope_Position`経由でSPARK Proof_Coreに接続完了している（Phase C）。Backingの証明接続（Phase D）は独立して進行中。

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

- cycleと観測日
- current Envelope membership、pacing、backing pool
- opening / unassigned / stable allocation coordinates
- explicit historical Expense routingとFulfillment routing
- primary Commodity
- Report query defaultとpresentation

policyはTOML構文のまま計算へ流さず、source-specific parserでtyped valueへ変換する。

## Admission failure and observable conditions

aledgerは「意味をadmitできない状態」と「admitできるが対話が必要な家計状態」を分ける。

### Admission failure

sourceを一つのHousehold事実として読めない場合はfail closedで拒否する。

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
- Unallocated / Unassigned balance
- unrouted Expense or Plan claim
- PlanとActualのvariance
- 将来支払に対する資金不足

これらをadmission failureやproof failureにしない。SPARKが証明するのは「良い家計状態であること」ではなく、admitted factsからその状態をexactに計算していることである。

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

AIも同じ境界に従う。AIはallocation、資金移動、Plan、Issue対応などを提案できるが、意味を推測してcanonical sourceを直接変更する権限にはならない。明示されたdecisionの後にnamed writerだけがsource candidateを作る。

この構造により、negative Remaining、Backing不足、Unallocated、Unroutedなどは隠す対象ではなく、対話の入口になる。

## Canonical source boundary

`ALedger.Canonical_Source`は固定8 basename、path解決、一回のexact-byte observationだけを所有する。Journal/TOML/TSVを一つのgeneric parserへ統合しない。各syntaxとdomain meaningはnamed admission ownerが持つ。

`ALedger.Household`はcomplete observationから各ownerを呼び、cross-source referenceを検証し、一つの`Household_State`を組み立てる。欠落・parse failure・未解決referenceを黙って飛ばさない。

## Migration chapters

1. **Observation foundation（完了）**: 固定8 sourceを一回だけexact-byteで観測し、欠落を拒否する
2. **Typed configuration（admission完了）**: `budget.toml`、`household.toml`、`report.toml`をnamed typed policyへadmitする。計算・renderingへの全面適用は各ownerのparity章で行う
3. **SPARK proof foundation（進行中）**: bounded normalized factsとTransaction / Plan / Envelope / Backing lawを現在のHousehold semanticsへ揃え、production接続前にstale proof lawを残さない
4. **Journal graph parity**: include、metadata、declared Account、Actual/Plan/Budget固有meaningをadmitする
5. **Cross-source validation**: Account、Envelope、Plan、Budget、identity/provenance referenceをcomplete stateで検証する
6. **Semantic parity**: synthetic corpusとprivate rehearsalでh-kernelと比較する
7. **Writer evaluation**: reader完成後、source別authority cutoverとは分離して評価する
8. **Interactive observation**: Observation -> Proposal -> Preview -> Decision -> WriterをCLI/TUI/AIで共有し、UIごとの意味論複製を作らない

各chapterは前段のsilent fallbackを残さない。将来機能を想定したplugin、generic repository、universal event frameworkは作らない。
