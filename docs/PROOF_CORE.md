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

## 5. Not proved yet

現在のproof packageはまだproduction calculationから直接呼ばれていない。したがってReportのEnvelope/Backing計算がSPARKで証明済みだとはまだ主張しない。

未接続または未証明:

- `ALedger.Money.Quantity`とproof quantaのexact checked bridge
- multi-Commodity `Balance`とCommodityごとのproof evaluationのbridge
- canonical Account/Commodityとproof IDのbijection
- Budget movementからEntitlementへのfoldそのもの
- stock origin / Observed_Through selection
- Expense routingとConsumption classification
- Fulfillment routingとcompletion-root stock membership
- open Plan Commitment classification
- Asset funding observation through date
- production `Backing_Policy`へのproof result接続
- durable identity、completion、reversal provenance
- writer effect

## 6. Migration plan

### Phase A: current Household proof foundation

- proof-only normalized types
- strict standalone proof project
- Transaction / reversal laws
- current Envelope Remaining / Headroom law
- current Backing Gross / Available law
- stale proof-only compatibility lawを残さない

### Phase B: Money bridge

- `ALedger.Money.Quantity`とのexact checked conversion
- round-trip test
- range rejection
- multi-Commodity Balanceから一つのCommodity coordinateをexactに取り出すbridge

### Phase C: Envelope production connection

ordinary Adaが既にadmitした、同じ`Observed_Through`に属する次の4値をCommodityごとにproof inputへ変換する。

- Entitlement
- Net Consumption
- Net Fulfillment
- Plan Commitment

production Remaining / Headroomはproof coreの結果をauthorityとして使う。通常Ada版とproof版を二重実装し続けない。

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
