# Progress Log

日付ベースの進捗記録。大きな変更があったときだけ更新する。
詳細は git log と各テストの test_runner / test_entitlement 出力を参照。

更新日: 2026-08-15

## Envelope-native model migration

h-kernel が `Budget` domain を廃止して `Envelope-native model` へ移行したため、
aledger も同様に作り直し中。canonical source は同じだが、domain owner は分離する。

| Step | 内容 | 状態 | テスト |
|---:|---|---|---|
| 1 | `ALedger.Envelope` — EnvelopeId private type + Registry admission | ✅ done | 28 tests in test_runner |
| 2 | `ALedger.Envelope_Routing` — ExpenseRoute discriminated record + effective-dated Routing_History | ✅ done | 20 tests in test_runner |
| 3 | `household.toml` の `[envelope-history]` を Parse_Household_Configuration で admit | ✅ done | 9 tests in test_runner + `aledger check` 成功 |
| 4 | `ALedger.Envelope_Entitlement` — Entitlement_Movement discriminated record + Entitlement_Observation fold | ✅ done | 9 tests in test_runner |
| 5 | `ALedger.Budget_Source_Adapter` — budget.journal → Entitlement_Movement 変換 | ✅ done | 16 tests in test_runner |
| 6 | `ALedger.Envelope_Consumption` — Actual Ledger + Routing → Consumption per Envelope | ✅ done | 18 tests in test_runner |
| 7 | `ALedger.Backing_Policy` — pool別のBacking position | ✅ done | 13 tests in test_runner |
| 8 | `Household_State` 再構成 + report 接続 + `aledger-budget` 退役 | ✅ done | 3 tests in test_runner + report 統合 |

## テスト数

- test_runner: **227** tests passed (Baseline + Envelope + Routing + TOML + Entitlement + Adapter + Consumption + Backing + Household)
- SPARK prove: **142** checks proved
- `aledger check --base ../household-ledger-data`: **SUCCESS**
  - Actual Transactions: 484
  - Plan Transactions: 28
  - Budget Transactions: 35
  - Registered Accounts: 45
  - Open Issues: 4

## 設計メモ

### private type と discriminated record の名前衝突

discriminated record の field 名は、参照する型名と衝突しないこと。

```ada
-- NG: field "Amount" と type "Amount" が衝突
type Entitlement_Movement is record
   Amount : Amount;   -- error
end record;

-- OK: field 名を変える
type Entitlement_Movement is record
   Amt : Amount;     -- OK
end record;
```

### 日本語リテラルは `String` に直接書けない

`-gnatW8` を指定しても、Standard.String は Latin-1 しか扱えない。
日本語は `Character'Val (16#XX#) & ...` でバイト列を構築する。

```ada
Food_UTF8 : constant String :=
   Character'Val (16#E9#) & Character'Val (16#A3#) & Character'Val (16#9F#) &
   Character'Val (16#E8#) & Character'Val (16#B2#) & Character'Val (16#BB#);
```

既存コード（test_runner.adb）はこの方式を採用している。

### 短い qualified name には `use` が必要

`with ALedger.Envelope;` だけでは `Envelope.Envelope_Id` は書けない。
`use ALedger.Envelope;` が必要。

```ada
with ALedger.Envelope;
-- use ALedger.Envelope;   ← これを追加

Food_Id : constant Envelope.Envelope_Id := ...;   -- OK
```

ただし `use` を spec の可視部に置くと private 型が見えてしまい、
aggregate 構築が可能になる（望ましくない場合あり）。
本番コードでは `Make_Envelope_Id` のような構築関数を使う方が安全。

### Indefinite_Vectors インスタンス化時の "=" 演算子指定

`discriminated record` や `private type` を含むレコードを `Indefinite_Vectors` の要素型とする場合、
`"=" => Package."="` を明示的に指定することで、安全かつ確実に vector インスタンス化ができる。

## ハマりポイント・TODO

- [x] test_runner.adb に envelope_entitlement のテストを統合（完了）
- [x] `Budget_Source_Adapter` 設計・実装（Step 5 完了）
- [x] `ALedger.Envelope_Consumption` 実装（Step 6 完了）
- [x] `ALedger.Backing_Policy` 実装（Step 7 完了）
- [x] `Household_State` 再構成 + report 接続 + `aledger-budget` 退役（Step 8 完了）