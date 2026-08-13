# aledger architecture

ステータス: active foundation

Report、Editor、TUIを含む全体の実装対象とparity順序は[`CAPABILITY_ROADMAP.md`](CAPABILITY_ROADMAP.md)が所有する。

## Dependency direction

```text
CLI / TUI
  -> Canonical_Source filesystem observation
  -> source-specific admission (Journal / Config / Issues)
  -> validated Household_State
  -> Money / Account / Ledger / Plan / Budget / Report
  -> Render

edit intent
  -> pure complete-source candidate
  -> source-specific admission
  -> approved writer effect
```

会計計算はpath、environment variable、terminal、renameを知らない。Renderはsourceを読まない。CLI/TUIはAccount分類、期間、予算、writer lawを再実装しない。

## Stable invariants

設定可能にしないkernel law:

- Quantityはexact decimalである
- AmountはCommodityを必ず保持する
- 異なるCommodityを暗黙に相殺しない
- TransactionはCommodityごとにbalancedである
- reversalは対象postingのexact inverseとexplicit relationを持つ
- identityとprovenanceをdisplay textから復元しない
- invalid sourceを正常なdomain valueへ変換しない

設定からadmitするpolicy:

- cycleと観測日
- Account policyとBudget routing
- Envelope、pacing、backing pool
- primary Commodity
- Report query defaultとpresentation

policyはTOML構文のまま計算へ流さず、source-specific parserでtyped valueへ変換する。

## Canonical source boundary

`ALedger.Canonical_Source`は固定8 basename、path解決、一回のexact-byte observationだけを所有する。Journal/TOML/TSVを一つのgeneric parserへ統合しない。各syntaxとdomain meaningはnamed admission ownerが持つ。

`ALedger.Household`はcomplete observationから各ownerを呼び、cross-source referenceを検証し、一つの`Household_State`を組み立てる。欠落・parse failure・未解決referenceを黙って飛ばさない。

## Migration chapters

1. **Observation foundation（完了）**: 固定8 sourceを一回だけexact-byteで観測し、欠落を拒否する
2. **Typed configuration（admission完了）**: `budget.toml`、`household.toml`、`report.toml`をnamed typed policyへadmitする。計算・renderingへの全面適用は各ownerのparity章で行う
3. **Journal graph parity**: include、metadata、declared Account、Actual/Plan/Budget固有meaningをadmitする
4. **Cross-source validation**: Account、Envelope、Plan、Budget、identity/provenance referenceをcomplete stateで検証する
5. **Semantic parity**: synthetic corpusとprivate rehearsalでh-kernelと比較する
6. **Writer evaluation**: reader完成後、source別authority cutoverとは分離して評価する

各chapterは前段のsilent fallbackを残さない。将来機能を想定したplugin、generic repository、universal event frameworkは作らない。
