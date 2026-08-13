# SPARK proof core contract

ステータス: active foundation  
更新日: 2026-08-13  
Owner: Actual、Plan reserve、Envelope、Backingに共通する証明可能な金額計算境界

## 1. 目的

aledgerで最も損失リスクが高い領域は次の連携である。

```text
Actual記帳
+ open Plan / completion
+ Budget movement / Envelope consumption
+ funding / backing reconciliation
```

parser、filesystem、Report、TUIを全面SPARK化せず、この連携が最終的に通る小さなpure arithmetic kernelをSPARKで証明する。

SPARKは仕様の意味が正しいことを自動発見しない。したがって二種類の証拠を併用する。

1. **SPARK proof**: overflow、range/index error、contract違反がない
2. **semantic parity**: h-kernel / bqn-ledgerと同じfacts、期間、符号、分類から同じ結果へ到達する

## 2. Boundary

```text
canonical 8-source exact observation
  -> ordinary Ada source-specific admission
  -> cross-source validation
  -> normalized proof facts
  -> ALedger.Proof_Core (SPARK_Mode)
  -> typed semantic result
  -> ordinary Ada Report / Editor / TUI
```

### Ordinary Ada owner

- UTF-8、Journal、TOML、TSV parser
- include graphとfilesystem
- StringからDate、Account、Commodity、identityへのadmission
- canonical Account/Commodityをbounded numeric IDへ割り当てること
- proof rangeへ変換できない値の明示的拒否
- lifecycle、durable identity、provenance、source location
- CLI、TUI、rendering、writer effect

### SPARK owner

- exact scaled integer arithmetic
- Commodity別Transaction balance predicate
- generated reversalのordered inverse predicate
- bounded Plan obligationからalready-excluded reservationを一度だけ引くこと
- Envelope Remaining
- post-Plan Headroom
- positive-part Backing Required
- Signed Envelope Total
- Funding、Backing Surplus、Reconciliation Delta
- 上記計算のoverflow/range/index safetyと公開postcondition

IDは一回のvalidated observation内で使うproof-facing coordinateであり、canonical sourceのdurable identityではない。

## 3. Exact quantity representation

`ALedger.Proof_Core`は1単位を`10^-8`とするsigned integer quantaを使う。

```text
source decimal Quantity
  <-> exact integer quanta (value * 100,000,000)
```

binary floating pointを使わず、変換時に丸めない。小数点以下9桁以上、範囲外、非exact conversionはadmission failureとする。

現在のproof foundationは次の明示上限を持つ。

- 一回のfoldの最大contributor数: `256`
- Commodity ID: `1 .. 4096`
- Account ID: `1 .. 65535`
- 64-bit環境で一つのatomic amountは約`45,035,996.27370495`以下

この上限はcanonical source semanticsではなく、機械整数上で証明可能な最初のoperational profileである。境界で黙ってtruncateまたはsaturateしない。実データや将来の住宅購入等に不足する場合は、proofを保ったままrange設計またはmulti-precision representationを変更する。

## 4. Current proved laws

### Transaction balance

2件以上のnormalized Postingについて、各Postingが参照するCommodityのexact sumがすべてzeroならbalancedである。

```text
Balanced(Transaction)
  <=> posting count >= 2
      and for every observed Commodity:
            sum Posting.Quantity = 0
```

異なるCommodityを相殺しない。

### Generated reversal

最初のnarrow lawは、元と同じPosting order、Account、Commodityを保持し、Quantityだけを正確に反転したTransactionをgenerated reversalとする。

```text
Rev[i].Account   = Original[i].Account
Rev[i].Commodity = Original[i].Commodity
Rev[i].Quantity  = -Original[i].Quantity
```

`event-id`と`reverses` relationの存在・一意性・参照整合性はordinary Ada admissionが所有する。順序を変更した外部sourceのreversal admissionは、Journal parity時に別のmultiset lawが必要かをh-kernel contractから決める。

### Plan obligation

一つのopen Plan obligationに対するalready-excluded reservation evidenceはnon-negativeかつPlan amount以下でなければならない。

```text
Unreserved Obligation
  = Plan Amount - Already Excluded
  >= 0
```

Plan selection、一意なreservation relation、open/completed lifecycleはordinary Ada admissionが所有する。proof coreはvalidated evidenceに対するexact deductionを所有する。

### Envelope

```text
Remaining
  = Entitlement - Consumption + Refunds

Post-Plan Headroom
  = Remaining - Plan Reserve
```

Consumption、Refund、Plan Reserveはnon-negative evidenceとして入力する。overspent Remainingとnegative Headroomは有効な結果であり、zeroへ丸めない。

### Backing

```text
Signed Total
  = sum Envelope Remaining

Backing Required
  = sum positivePart(Envelope Remaining)

Backing Surplus
  = Funding Balance - Backing Required

Reconciliation Delta
  = Backing Surplus - Unassigned Balance

Under Backed
  <=> Backing Surplus < 0
```

negative Envelopeが別Envelopeのpositive claimを相殺してBacking Requiredを減らさない。

## 5. Not proved yet

現在のproof packageはfoundationであり、production `ALedger.Money`、`Ledger`、`Budget`からまだ呼ばれていない。したがって現在のReport計算がSPARKで証明済みだとは主張しない。

次は未証明である。

- source `Quantity`とproof quantaのexact conversion
- canonical Account/Commodityとproof IDのbijection
- Date/Period selection
- Expense→Envelope routing
- Actual consumption/refund classification
- Plan open/completed lifecycle、reservation一意性、複数Plan集計の二重計上防止
- Plan completionで生成するActualのbalance
- Plan→Budget syncのconservation
- Budget movementからEntitlementへのfold
- multi-Commodity Envelope/Backing全体
- durable identity、completion、reversal provenance
- cross-file writer effect

## 6. Migration plan

### Phase A — foundation（現在）

- proof-only normalized types
- strict standalone proof project
- Transaction、Envelope、Backingの最小law
- ordinary runtime characterization test

### Phase B — Money bridge

- `ALedger.Money.Quantity`とのexact checked conversion
- canonical Commodity tableからproof IDを作るbounded adapter
- round-trip testとrange rejection
- production Balance algebraとのparity

### Phase C — Actual

- admitted Postingをproof factsへ変換
- `Create_Transaction` / `Add_Transaction`がproof resultを要求
- generated reversalをproof ownerへ接続
- durable relationをordinary admissionで検証

### Phase D — Envelope and Plan

- h-kernel parityでEntitlement/Consumption/Refund/Reserveのownerを確定
- Envelope resultをproof coreから取得
- open Plan reserveとcompletionの重複を状態transition contractで防ぐ
- Plan completion ActualとBudget syncのconservation lawを追加

### Phase E — Backing

- policy指定Asset funding
- positive-part required
- unassigned reconciliation
- Commodityごとに独立したresult
- Report rendererを証明済みsemantic resultへ接続

Editor/TUIへ金額計算を追加する前に、対象operationがこの境界を通るようにする。

## 7. Verification

proof toolはAlire dependencyとして固定する。

```sh
./tools/prove
```

これは次を実行する。

```sh
alr exec -- gnatprove \
  -P proof/aledger_proof.gpr \
  --mode=prove \
  --level=2 \
  --report=fail \
  --warnings=error \
  --checks-as-errors=on
```

`--checks-as-errors=on`により未証明checkを成功扱いしない。proof objectとsessionはGit管理しない。

通常検証も別に実行する。

```sh
alr build
./bin/test_runner
./bin/aledger check --base /path/to/private-household-root
```

proof、runtime test、cross-engine parityは互いの代替ではない。

## 8. Change rule

Actual、Plan、Budget、Envelope、Backingの金額式またはproof-facing boundsを変更するときは、同じchangeで次を更新する。

- `ALedger.Proof_Core` contract/body
- `./tools/prove`成功
- focused runtime test
- 必要なh-kernel/BQN parity evidence
- この文書のcurrent proved / not-proved境界

parserやTUIをSPARKへ入れるためにproof coreを汎用framework化しない。証明対象は小さく、pureで、金額法則を直接読める形に保つ。
