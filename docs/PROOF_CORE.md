# SPARK proof core contract

ステータス: active foundation  
更新日: 2026-08-16  
Owner: Actual、Envelope、Plan commitment、Backingに共通する証明可能な金額計算境界

## 1. 目的

aledgerでは、parser、filesystem、Report、TUIを全面SPARK化しない。ordinary Adaがsource-specific admissionとcross-source validationを所有し、その結果から作られた小さなbounded factsだけをpure arithmetic kernelへ渡す。

```text
canonical 8-source exact observation
  -> ordinary Ada admission / validation
  -> normalized proof facts
  -> ALedger.Proof_Core (SPARK_Mode)
  -> typed semantic result
  -> ordinary Ada Observation / Report / Editor / TUI
```

SPARKの目的は「家計が望ましい状態であること」を証明することではない。negative Remaining、negative Headroom、under-backed fundingなどは有効なHousehold observationである。証明するのは、admitted factsからその状態をexactに、overflowやrange/index errorなしで計算していることである。

証拠は二種類を併用する。

1. **SPARK proof**: overflow、range/index error、contract違反がない
2. **semantic parity**: h-kernel / bqn-ledgerと同じfacts、観測範囲、符号、分類から同じ結果へ到達する

## 2. Boundary

### Ordinary Ada owner

- UTF-8、Journal、TOML、TSV parser
- include graphとfilesystem
- StringからDate、Account、Commodity、identityへのadmission
- durable identity、provenance、source location
- stock originとObserved_Throughによるsource selection
- Expense / Fulfillment routing
- Actual consumption / refund classification
- Plan open/completed lifecycleとcommitment classification
- canonical Account/Commodityからproof coordinateを作るadapter
- `ALedger.Proof_Money_Bridge`: `ALedger.Money.Quantity` / `Balance`とproof quanta（`10^-8`）のexact checked conversion
- proof rangeへexact conversionできない値の明示的拒否
- CLI、TUI、rendering、proposal、writer effect

### SPARK owner

- exact scaled integer arithmetic
- Commodity別Transaction balance predicate
- generated reversalのordered inverse predicate
- Envelope Remaining
- post-Plan Headroom
- positive-part Gross / Available Envelope Required
- Available Funding
- Gross / Available Surplus
- 上記計算のoverflow/range/index safetyと公開postcondition

proof coreはdurable identityやsource authorityを所有しない。proof-facing IDは一回のvalidated observation内のbounded coordinateである。

## 3. Exact quantity representation

`ALedger.Proof_Core`は1単位を`10^-8`とするsigned integer quantaを使う。

```text
source decimal Quantity
  <-> exact integer quanta (value * 100,000,000)
```

binary floating pointを使わず、変換時に丸めない。小数点以下9桁以上、範囲外、non-exact conversionはadmission failureとする。

現在のproof foundationは次の明示上限を持つ。

- 一回のfoldの最大contributor数: `256`
- Commodity ID: `1 .. 4096`
- Account ID: `1 .. 65535`
- 64-bit環境で一つのatomic proof inputは約`45,035,996.27370495`以下

この上限はcanonical source semanticsではなく、機械整数上で証明可能なoperational profileである。境界で黙ってtruncateまたはsaturateしない。実データに不足する場合は、proofを保ったままrange設計またはrepresentationを変更する。

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

現在のnarrow lawは、元と同じPosting order、Account、Commodityを保持し、Quantityだけをexactに反転したgenerated reversalを扱う。

```text
Rev[i].Account   = Original[i].Account
Rev[i].Commodity = Original[i].Commodity
Rev[i].Quantity  = -Original[i].Quantity
```

`event-id`と`reverses` relationの存在・一意性・参照整合性はordinary Ada admissionが所有する。

### Envelope

production Householdのstock observationと同じ式を使う。

```text
Remaining
  = Entitlement
  - Net Consumption
  - Net Fulfillment

Post-Plan Headroom
  = Remaining
  - Plan Commitment
```

`Net Consumption`と`Net Fulfillment`はsignedである。refundやreversalによりnegativeになり得る。`Plan Commitment`だけはnon-negative claimとしてadmitし、RemainingではなくHeadroomだけを減らす。

negative Remainingとnegative Headroomは有効な観測結果であり、zeroへ丸めず、proof failureにも変換しない。

### Backing

production `Backing_Policy`と同じ二つの視点を証明する。

```text
Gross Envelope Required
  = sum positivePart(Remaining)

Available Envelope Required
  = sum positivePart(Post-Plan Headroom)

Available Funding
  = Funding Balance - Funding Commitment

Gross Surplus
  = Funding Balance - Gross Envelope Required

Available Surplus
  = Available Funding - Available Envelope Required
```

negative Envelopeが別Envelopeのpositive claimを相殺してrequired fundingを減らさない。Funding CommitmentがFunding Balanceを上回ることやSurplusがnegativeになることは合法な観測状態である。

旧proof foundationにあった`Unassigned Balance -> Reconciliation Delta`は現在のproduction Backing lawではないためproof coreから除く。Unallocated / UnassignedはHousehold observationとして別に明示し、Backingへ暗黙に混ぜない。

旧`Unreserved_Obligation / Already_Excluded` helperも現在のproduction Plan Commitment ownerに対応しないためproof coreから除く。productionに存在しない将来用の計算をproof kernelへ保存しない。

## 5. Current production connection state

- production Envelope Remaining / Headroom: `ALedger.Envelope_Position` 経由で `ALedger.Proof_Core.Evaluate_Envelope` へ接続完了（Phase C）
- multi-Commodity coordinate evaluation: 各 Envelope 内で 4 入力（Entitlement, Net Consumption, Net Fulfillment, Plan Commitment）の Commodity 座標の union を構成し、各 Commodity 座標ごとに `ALedger.Proof_Money_Bridge` を介して `Proof_Core.Evaluate_Envelope` で評価（接続完了）
- dated report observation axis:
  ```text
  Observed_Through
    -> dated Entitlement (Budget_Source_Adapter.Observe_Entitlements through Observed_Through)
    -> dated stock Consumption (Envelope_Consumption.Observe_Stock_Consumption)
    -> dated stock Fulfillment (Envelope_Fulfillment.Observe_Stock)
    -> Plan Commitment (Envelope_Commitment.Observe)
    -> proof-backed Envelope Position (Envelope_Position.Observe)
    -> dated Funding (Backing_Policy.Observe_Funding_Commitment)
    -> Backing (Backing_Policy.Observe_Backing)
  ```
  `State.Entitlement` への fallback を禁止し、すべての金額観測は `Observed_Through` を基準とする dated pipeline を通る。
- `ALedger.Backing_Policy` は `Envelope_Position.Observation` から Position を必須取得し、missing position 時は fail-loud（`Program_Error`）で異常停止し、Gross/Available Required を過小計算したまま成功することを禁止。
- production Backing proof connection: Phase D（未接続）

未接続または未証明:

- production `Backing_Policy`へのproof result接続（Phase D）
- 複数 Envelope 間にまたがる global proof ID orchestration / bijection / cross-envelope proof ID assignment（Phase D/E）
- multi-Commodity cross-envelope proof orchestration
- Budget movementからEntitlementへのfoldそのもの
- stock origin / Observed_Through selection
- Expense routingとConsumption classification
- Fulfillment routingとcompletion-root stock membership
- open Plan Commitment classification
- Asset funding observation through date
- durable identity、completion、reversal provenance
- writer effect

## 6. Migration plan

### Phase A: current Household proof foundation (completed)

- proof-only normalized types
- strict standalone proof project
- Transaction / reversal laws
- current Envelope Remaining / Headroom law
- current Backing Gross / Available law
- stale proof-only compatibility lawを残さない

### Phase B: Money bridge (completed)

- `ALedger.Proof_Money_Bridge`がowner
- `ALedger.Money.Quantity`と`ALedger.Proof_Core` quanta（`10^-8`）のexact checked conversion
- Atomic input range rejection（Moneyでは合法でもproof operational profile外の値を`Out_Of_Proof_Input_Range`として明示拒否）
- wider proof output -> Money checked conversion（`Derived_Quanta`やBacking aggregateなどAtomicより広いLong_Long_Integer proof結果をexactに`Money.Quantity`へ戻し、overflowは`Out_Of_Money_Output_Range`で明示拒否）
- one-Commodity Balance coordinate bridge（指定された既知Commodityの一座標のみをexactに取り出し、欠損座標は`Money.Lookup_Balance`のcanonical zeroとして扱う。`To_Singleton_Balance`によるsingleton balance復元）
- round-trip / boundary / scale characterization test (`tests/test_proof_money_bridge.adb`)

### Phase C: Envelope production connection (completed)

- `ALedger.Envelope_Position` が production Remaining / Headroom observation owner
- scalar arithmetic authority は `ALedger.Proof_Core.Evaluate_Envelope`
- `ALedger.Proof_Money_Bridge` が唯一の Money ↔ quanta conversion boundary
- current Envelope membership authority は typed `Budget_Policy.Envelopes`
- stable identity universe は `Envelope_Registry` が所有し、retired identity は current observation に混入しない
- 4入力（Entitlement、Net Consumption、Net Fulfillment、Plan Commitment）の各 Entries から独立に Commodity union を構成（合算相殺による座標消失の防止）
- 各 Commodity 座標ごとに `Proof_Money_Bridge` 経由で `Proof_Core.Evaluate_Envelope` を呼び出し、結果を `Balance` へ合成
- dated report pipeline: `Observed_Through` に基づく dated Entitlement / stock Consumption / stock Fulfillment / Position 評価
- `ALedger.Backing_Policy` は Remaining/Headroom の計算責任を完全に手放し、`Envelope_Position.Observation` を入力として消費するのみ。要求 Envelope の Position 欠損時は fail-loud
- Backing proof そのものは Phase D（未接続）として維持
- focused tests (`tests/test_envelope_position.adb`) で Law A〜L を網羅

### Phase D: Backing production connection

同じEnvelope proof resultsと、同じ観測日のFunding Balance / Funding Commitmentからproof coreがGross / Available requiredとsurplusを返す。`Backing_Policy`はこの結果をproduction authorityとして組み立てる。

### Phase E: Actual balance / generated reversal connection

admitted Postingをproof factsへ変換し、transaction balanceとgenerated reversalのproduction validationをproof ownerへ接続する。durable relation validationはordinary Adaに残す。

### Phase F: interactive proposal preview

Envelope allocation、Plan、funding actionなどのproposal previewも、final production observationと同じdomain calculationを通す。UIやAIにpreview専用の金額計算を複製しない。

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

`--checks-as-errors=on`により未証明checkを成功扱いしない。

通常検証も別に実行する。

```sh
alr build
./bin/test_runner
./bin/aledger check --base /path/to/private-household-root
```

proof、runtime test、canonical rehearsal、cross-engine parityは互いの代替ではない。

## 8. Change rule

Actual、Plan、Budget、Envelope、Backingの金額式またはproof-facing boundsを変更するときは、同じchangeで次を更新する。

- `ALedger.Proof_Core` contract/body
- `./tools/prove`成功
- focused runtime test
- 必要なh-kernel / BQN parity evidence
- この文書のcurrent proved / not-proved境界

parserやTUIをSPARKへ入れるためにproof coreを汎用framework化しない。証明対象は小さく、pureで、productionで使う金額法則を直接読める形に保つ。
