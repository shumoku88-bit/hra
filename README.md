# aledger

`aledger` は、Haskell製複式簿記・家計簿カーネル `h-kernel` を Ada 2012 / Ada 2022 で再実装するプロジェクトです。

## 特徴と設計原則

- **Ada 2012 厳密型システム**: 金額・勘定科目・複式簿記の貸借一致を静的に保護。
- **Exact Decimal Quantity (`ALedger.Money`)**: 丸め誤差のない `delta 0.00000001` 固定小数点精度。
- **Commodity-Aware Multi-Balance (`Balance`)**: 多通貨（JPY, USD, BTC等）を混同せず独自バランスマップで集計し、0円の残高は自動消去。
- **Strict Account Registry (`ALedger.Account`)**: 5大勘定（Asset, Liability, Equity, Income, Expense）＋ Budget の明示的型宣言。
- **Double-Entry Balance Law (`ALedger.Ledger`)**: すべての取引（Transaction）において貸借和（Sum of Postings）が 0 になることを検証し、アンバランスな取引は受理を拒絶。

## ディレクトリ構造

- `alire.toml`: Alire パッケージマニフェスト
- `aledger.gpr`: GPRbuild ビルド定義
- `src/`: Ada ソースコード (`.ads` モジュール仕様 / `.adb` モジュール本体)
  - `aledger.ads`: ルートパッケージ
  - `aledger-money.ads`, `aledger-money.adb`: 金額・通貨・バランスマップ
  - `aledger-account.ads`, `aledger-account.adb`: 勘定科目・カテゴリ・レジストリ
  - `aledger-ledger.ads`, `aledger-ledger.adb`: ポスティング・取引・元帳計算
  - `aledger_main.adb`: CLI エントリポイント
- `tests/`: 単体テストスイート
  - `test_runner.adb`: 全モジュールの自動検証テストハーネス

## ビルドとテストの実行

```bash
# 依存ツールのセットアップ (Alire)
alr exec -- gprbuild -P aledger.gpr

# テストスイートの実行
./bin/test_runner

# CLIの実行
./bin/aledger check
```
