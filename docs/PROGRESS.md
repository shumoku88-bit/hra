# Progress Log

日付ベースの進捗記録。大きな変更があったときだけ更新する。
詳細は git log と各focused testを参照する。

更新日: 2026-08-16

## Last qualified main baseline

main `a94a67663b212304d79ac4e3e4e20171b400ab38` で確認済み:

- clean build
- test_runner: **227 tests passed**
- SPARK prove: **142 checks proved**
- canonical Household check/report successful

以下のDraft作業のtest/proof数としてこのbaselineを流用しない。

## Draft PR #12: clean Envelope / Household contract

branch: `refactor/clean-envelope-household-contract`

h-kernelとprivate canonical Householdのclean epoch source shapeへ、aledgerのreader semanticsを揃える作業。

### Source authority

- `budget.toml` はcurrent Envelope + Backingだけを所有する
- `household.toml` はOpening / Unassigned / stable allocation coordinatesを所有する
- retired allocation coordinateはhistorical `budget.journal`解釈のため保持可能
- Envelope identity/routing historyはexplicit `[envelope-history]`だけからadmitする
- current configからhistorical identity/routingを再構成しない
- `expense-accounts`、`account-policy`、Plan destination compatibility authorityを退役
- fixed `budget:*` fallbackとspent/execution endpointを退役

### Stock horizon

- `budget.journal`のCommodityごとの最古movement日をEntitlement stock originとして保持
- 0 movementもclean epoch originを明示可能
- production Consumptionはroot Actual dateでstock membershipを判定
- production Fulfillmentはcompletion root dateでstock membershipを判定
- later reversalはpre-origin rootをstockへ持ち込まない
- Report periodはstock originを上書きしない

### Tests added / migrated

- canonical Household fixturesをclean source shapeへ移行
- Budget adapterのretired execution lawを削除
- zero movement source-origin lawを追加
- Consumption pre-origin reversal lawを追加
- Fulfillment pre-origin reversal-chain lawを追加
- `test_clean_household_contract` を追加し、retired authority rejectionを明示

### Qualification status

この実行環境にはAda toolchainがなく、repositoryにGitHub Actions workflowも無いため、PR #12のbuild / tests / GNATproveは**未実行**。Draftを維持する。

## Envelope-native model migration history

| Step | 内容 | 状態 |
|---:|---|---|
| 1 | `ALedger.Envelope` — EnvelopeId private type + Registry admission | done |
| 2 | `ALedger.Envelope_Routing` — effective-dated Routing_History | done |
| 3 | `household.toml` `[envelope-history]` admission | done |
| 4 | `ALedger.Envelope_Entitlement` — movement fold | done |
| 5 | `ALedger.Budget_Source_Adapter` — budget.journal projection | done, PR #12でclean endpointsへ更新 |
| 6 | `ALedger.Envelope_Consumption` — Actual + Routing | done, PR #12でstock horizon追加 |
| 7 | `ALedger.Backing_Policy` — pool別Backing | done |
| 8 | `Household_State` + report composition | done, PR #12でclean authority/stock pathへ更新 |

## Ada implementation notes

### private type と discriminated record の名前衝突

discriminated record のfield名は参照する型名と衝突させない。

```ada
type Entitlement_Movement is record
   Amt : Amount;
end record;
```

### UTF-8 test literal

Standard.Stringへ日本語source fixtureを直接書く代わりに、既存testではUTF-8 bytesを`Character'Val`で構成する。

### Generic container equality

private typeやdiscriminated recordをgeneric containerへ渡すときは、必要ならdomain packageが所有する`"="`を明示する。
