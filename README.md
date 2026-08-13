# aledger

`aledger`は、h-kernelと同じcanonical Household sourceをAda 2022で読み、exactな複式簿記・家計projectionを行う実験的kernelです。

## Canonical data

aledger専用の正データは作りません。user-owned private repositoryのrootを、h-kernelと共有する唯一のcanonical Household rootとして扱います。

```text
accounts.journal
actual.journal
plan.journal
budget.journal
budget.toml
household.toml
report.toml
issues.tsv
```

8 sourceのどれかが欠落・読取不能ならcomplete observationは失敗します。legacy fallback、source filename redirect、engine別copyは追加しません。

3 TOML sourceはsource別の型付きpolicyへadmitされ、unknown key、欠落、型不一致、構造的な重複、未宣言または不正種別のAccount参照を拒否します。Journalと`issues.tsv`のadmission、include graph、identity/provenance、およびpolicyを計算へ適用する部分はまだh-kernel parityに達していません。現時点のReportをcanonicalな意思決定結果として扱わないでください。

詳しくは以下を参照してください。

- [`docs/CANONICAL_HOUSEHOLD.md`](docs/CANONICAL_HOUSEHOLD.md)
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
- [`docs/CAPABILITY_ROADMAP.md`](docs/CAPABILITY_ROADMAP.md): Report、Editor、TUIを含むparity inventory
- [`SECURITY.md`](SECURITY.md)

## Kernel invariants

- `delta 0.00000001`のexact decimal Quantity
- Commodity別のcanonical Balance
- double-entry balance law
- typed Account registry
- inverse postingとexplicit relationによるreversal
- source observationと会計計算、rendering、filesystem effectの分離

## Native Ada implementation

本体とTOML parserはAdaで実装され、GNAT/AlireがOSのnative executableへコンパイルします。interpreter、JVM、Node.js runtimeは使用しません。CLI/TUIはcanonical source内のUTF-8を再変換せず、terminalへexact byteとして出力します。

```sh
file bin/aledger
# macOSの例: Mach-O 64-bit executable ...
# Linuxの例: ELF 64-bit ... executable
```

設計もAda 2022のpackage spec/body、fixed-point型、container、contractを利用しています。ただし現在は移植途中のため、公開record、`Boolean + out`形式、手続き的parserなど古典的なAda表現も残っています。単に新しい構文へ置換するのではなく、canonical semanticsを確立したownerからprivate typeと小さなAPIへ整えていきます。

外部依存の`ada_toml`もpure Ada libraryです。

## Build and test

必要なもの:

- Alire
- Alireが選択するGNAT toolchain

```sh
cd /path/to/aledger
alr build
./bin/test_runner
```

成功時は最後に次のように表示されます。

```text
Summary: Passed = ..., Failed = 0
RESULT: SUCCESS
```

## Quick start

h-kernelと同じprivate canonical Household rootを`--base`で指定します。

```sh
./bin/aledger check --base /path/to/private-household-root
./bin/aledger report --base /path/to/private-household-root
./bin/aledger tui --base /path/to/private-household-root
```

このworkspaceと同じ配置なら、例えば次のように実行できます。

```sh
cd /path/to/moko/aledger
./bin/aledger check --base ../household-ledger-data
./bin/aledger report --base ../household-ledger-data
```

### Household rootの選択順

1. `--base <dir>`
2. `LEDGER_DATA_DIR`
3. `HKERNEL_LEDGER_DATA_DIR`
4. current directoryの`ledger-data/`
5. current directory

環境変数を使う例:

```sh
export HKERNEL_LEDGER_DATA_DIR=/path/to/private-household-root
./bin/aledger check
./bin/aledger report
```

### `check`

固定8 sourceの存在、exact observation、Journal/TSVの現在対応済みadmission、3 TOML policy、Account参照、balance lawを検証します。

```sh
./bin/aledger check --base /path/to/private-household-root
```

出力形式:

```text
SUCCESS: Fixed 8-source topology and currently supported admissions verified for ...
  Configuration       : typed budget, household, and report policy admitted
  Actual Transactions : ...
  Plan Transactions   : ...
  Budget Transactions : ...
  Registered Accounts : ...
  Open Issues         : ...
```

source本文や金額は`check`出力へ表示しません。

### `report`

```sh
./bin/aledger report --base /path/to/private-household-root
```

現在は一つのreport bookとして、次の順に表示します。

1. Profit & Loss
2. Balance Sheet
3. open Household Issues
4. Budget / backing status

冒頭とsectionの概形:

```text
WARNING: typed TOML policies are not yet fully applied; this report is not canonical.
==================================================
   ALedger Financial Statements
==================================================

== Profit & Loss Statement (aledger Engine) ==
...
== Balance Sheet (aledger Engine) ==
...
== Household Issues ==
...
== Envelope & Backing ==
...
```

現在の`report`は確認・比較用です。`report.toml`は型付き値へadmitされますが、period/presentation policyはまだすべてのrendererへ適用されていません。h-kernelとのsemantic parityが完了するまでcanonicalな判断や自動処理には使用しないでください。

ReportにはprivateなAccount、日付、金額、Issueが含まれます。terminalはUTF-8 localeで使用してください。

```sh
locale
# LANGまたはLC_CTYPEがUTF-8であることを確認
```

保存する場合はprivate repositoryの外側かつ公開されない場所を使います。

```sh
umask 077
./bin/aledger report --base /path/to/private-household-root > /private/path/aledger-report.txt
```

### `tui`

```sh
./bin/aledger tui --base /path/to/private-household-root
```

native terminal UIを起動します。現在は実験的reader surfaceであり、canonical writer authorityは持ちません。

### その他

```sh
./bin/aledger version
./bin/aledger help
```

private source、生成Report、local pathを公開repositoryやCI logへ出力しないでください。

## Source layout

- `src/aledger-output.*`: UTF-8を二重encodeしないnative terminal output
- `src/aledger-canonical_source.*`: 固定8-source pathとexact-byte observation
- `src/aledger-*_config.*`: Budget、Household、Report TOMLの型付きadmission
- `src/aledger-household.*`: complete observationからのHousehold composition
- `src/aledger-journal.*`: Journal admission
- `src/aledger-money.*`, `aledger-account.*`, `aledger-ledger.*`: accounting kernel
- `src/aledger-plan.*`, `aledger-budget.*`, `aledger-report.*`: domain projection
- `tests/test_runner.adb`: synthetic test suite
