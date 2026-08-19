# Canonical Household contract

ステータス: active foundation contract  
Owner: hraにおけるshared canonical sourceの境界

## 目的

hraは独自の正データ、同期copy、変換後databaseを持たない。user-owned private repositoryのrootを、`h-kernel`と共有する唯一のcanonical Household rootとして読む。

```text
one private Household root
  -> h-kernel source-specific admission
  -> hra source-specific admission
  -> engineごとのvalidated representation
```

共有するのは内部recordではなく、sourceから到達する会計・家計上の意味である。

## 固定topology

canonical rootのruntime authorityは次の8 sourceだけである。

| Source | Canonical role |
|---|---|
| `accounts.journal` | Account identity、AccountType、optional default Commodity |
| `actual.journal` | Actual Transaction、posting、identity、completion/reversal relation |
| `plan.journal` | Plan identity、schedule、recurrence、lifecycle relation |
| `budget.journal` | ordered Budget movement、provenance、CommodityごとのEnvelope stock origin |
| `budget.toml` | current Envelope membership/presentationとBacking topology |
| `household.toml` | cycle、opening/unassigned Budget accounts、stable allocation coordinates、Daily Target、explicit Envelope routing history |
| `report.toml` | Report query defaultとpresentation policy |
| `issues.tsv` | household notebook。会計factを暗黙生成しない |

basenameは`HRA.Canonical_Source`だけが解決する。別configでsource filenameを変更しない。追加directory、legacy TSV、manifest、generated Reportをcanonical inputへ戻さない。

## Clean Envelope source contract

current policyとhistorical meaningを同じauthorityへ潰さない。

- `budget.toml` は現在存在するEnvelopeとBackingだけを所有する。Expense routingやallocation Accountを所有しない。
- `household.toml [budget]` は `opening-accounts`、`unassigned-accounts`、`id + allocation-account` を明示する。
- current Envelopeには必ずallocation coordinateが必要だが、退役Envelopeのcoordinateはhistorical `budget.journal`を解釈するため残してよい。
- `[envelope-history].identities` がstable Envelope identity universeを所有する。current `budget.toml`からidentity historyを合成しない。
- `[envelope-history].expense-routing` がExpenseのhistorical meaningを所有する。current configからinitial routeを逆算しない。
- Budget endpointはexplicitなOpening / Unassigned / Envelope allocationだけで分類する。固定名fallback、spent/execution endpoint、Account policy fallbackを持たない。
- `budget.journal`の各Commodityで最古のadmitted movement日をstock originとする。0 movementもclean epochを明示できる。
- ConsumptionとFulfillmentのstock observationはorigin以後だけを累積する。reversalは自身の日ではなくroot Actualのmembershipを継承する。

retired compatibility source shapeはunknown keyとしてfail closedにする。reader parityのためにhidden aliasやduplicate authorityを残さない。

## Observation and admission

```text
Household root
  -> complete 8-source exact-byte observation
  -> source-specific syntax admission
  -> cross-source semantic validation
  -> Household_State
```

complete observationは8 sourceのどれかが欠落・読取不能なら失敗する。source-local parse failureを空値へ変換しない。同じload中にroot sourceを再読込して、異なる時点の値を混ぜない。

`Source_Observation`はrepository/session/cacheではない。一回のadmissionと将来のsafe publicationに必要な、短命な同一観測境界である。

## Current hra coverage

2026-08-16時点:

| Source | Exact observation | Typed semantic admission |
|---|---:|---:|
| Accounts/Actual/Plan/Budget journals | yes | typed graph/evidence admission。Account authorityとPlan/Actual relationを保持 |
| `issues.tsv` | yes | partial。lifecycle/typed identity parityは今後 |
| `budget.toml` | yes | current Envelope + Backingを型付きadmit |
| `household.toml` | yes | clean Budget coordinates + explicit Envelope historyを型付きadmit |
| `report.toml` | yes | typed query/presentation policy |

Envelope production observationはexplicit history、Budget-derived Entitlement origin、stock Consumption/Fulfillment、Remaining/Backingへ接続する。Report portfolio、Issue domain、writer authority、SPARK production cutoverは引き続き別の完成条件である。

## Fail-closed completion gate

canonical reader互換を宣言するには、以下を満たす。

1. 8 sourceすべてにnamed admission ownerがある
2. include graphを相対path、cycle、duplicate、read trace付きで解決する
3. AccountTypeやidentityを表示文字列から推測しない
4. unknown key、metadata、column、statusを黙って捨てない
5. exact Quantity、Commodity、Posting order、identity、provenanceを保持する
6. cross-source referenceをcomplete observation上で検証する
7. source failureにbasename・位置・意味を含む診断を返す
8. synthetic fixtureと、秘密を出力しないprivate-root rehearsalを通す
9. 同じcanonical rootに対するh-kernelとのsemantic parityを確認する

## Writer authority

同じsourceを読めることと、書いてよいことは別である。hraのwriterは現在canonical writer authorityを持たない。

- shared private sourceにはread-onlyで接続する
- write capabilityの存在からauthority移動を推測しない
- source別cutover、semantic parity、stale rejection、atomic publication、post-admission、checked restore、作者の承認なしに切り替えない
- h-kernelとhraを交互にcanonical writerとして使わない

## Private boundary

canonical sourceには私的な日付、数量、Account、Transaction、Plan、policy、Issueが含まれる。内容、backup、temporary file、生成Report、local pathをpublic repository、Issue、PR、CI logへ転記しない。公開testは意味を特定できないsynthetic fixtureだけを使用する。
