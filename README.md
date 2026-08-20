# HRA — Household Reckoning Apparatus

**HRA**は、h-kernelと同じcanonical Household sourceをAda 2022で読み、exactな複式簿記・家計projectionを行う実験的なHousehold reckoning apparatusです。

名前の **Reckoning** はledgerへの記帳だけを指しません。Actual、Plan、Envelope、Issue、Relation、Observation、provenance、proofを含めて、Householdの事実と観察を壊さず勘定することを意図しています。

> Public project / repository name: **HRA**
>
> Long name: **Household Reckoning Apparatus**

現在のinternal machine nameは、Ada namespaceが`HRA`、Alire crate、native executable、source prefixが`hra`です。旧`ALedger` / `aledger`のcompatibility aliasは提供しません。

## Canonical data

HRA専用の正データは作りません。user-owned private repositoryのrootを、h-kernelと共有する唯一のcanonical Household rootとして扱います。

```text
accounts.journal
actual.journal
plan.journal
entitlement.journal
envelope.toml
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
- [`docs/PROOF_CORE.md`](docs/PROOF_CORE.md): Actual、Plan、Envelope、BackingのSPARK境界
- [`SECURITY.md`](SECURITY.md)

## Kernel invariants

- `delta 0.00000001`のexact decimal Quantity
- Commodity別のcanonical Balance
- double-entry balance law
- typed Account registry
- inverse postingとexplicit relationによるreversal
- source observationと会計計算、rendering、filesystem effectの分離

## Native Ada implementation

本体とTOML parserはAdaで実装され、GNAT/AlireがOSのnative executableへコンパイルします。interpreter、JVM、Node.js runtimeは使用しません。CLIはcanonical source内のUTF-8を再変換せず、terminalへexact byteとして出力します。

```sh
file bin/hra
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
cd /path/to/hra
./tools/hra qualify
```

成功時は各focused testとproofが成功して終了します。

## Quick start

h-kernelと同じprivate canonical Household rootを`--base`で指定します。

```sh
./tools/hra check --base /path/to/private-household-root
./tools/hra report --base /path/to/private-household-root
```

このworkspaceと同じ配置なら、例えば次のように実行できます。

```sh
cd /path/to/moko/hra
./tools/hra check --base ../household-ledger-data
./tools/hra report --base ../household-ledger-data
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
./tools/hra check
./tools/hra report
```

### `check`

固定8 sourceの存在、exact observation、Journal/TSVの現在対応済みadmission、3 TOML policy、Account参照、balance lawを検証します。

```sh
./tools/hra check --base /path/to/private-household-root
```

出力形式:

```text
SUCCESS: Fixed 8-source topology and currently supported admissions verified for ...
  Configuration         : typed envelope, household, and report policy admitted
  Actual Transactions   : ...
  Plan Transactions     : ...
  Entitlement Movements : ...
  Registered Accounts   : ...
  Open Issues           : ...
```

source本文や金額は`check`出力へ表示しません。

### `report`

```sh
./tools/hra report --base /path/to/private-household-root
```

現在は一つのreport bookとして、次の順に表示します。

1. Profit & Loss
2. Balance Sheet
3. open Household Issues
4. Envelope / backing status

冒頭とsectionの概形:

```text
WARNING: typed TOML policies are not yet fully applied; this report is not canonical.
==================================================
   HRA Financial Statements
==================================================

== Profit & Loss Statement (hra Engine) ==
...
== Balance Sheet (hra Engine) ==
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
./tools/hra report --base /path/to/private-household-root > /private/path/hra-report.txt
```

### その他

```sh
./tools/hra version
./tools/hra app-help
```

private source、生成Report、local pathを公開repositoryやCI logへ出力しないでください。

## Source layout

内部Ada namespaceは`HRA`です。

- `src/hra-proof_core.*`: bounded exact arithmeticのSPARK proof foundation
- `proof/hra_proof.gpr`, `tools/hra prove`: strict proof target
- `src/hra-output.*`: UTF-8を二重encodeしないnative terminal output
- `src/hra-canonical_source.*`: 固定8-source pathとexact-byte observation
- `src/hra-*_config.*`: Envelope、Household、Report TOMLの型付きadmission
- `src/hra-household.*`: complete observationからのHousehold composition
- `src/hra-journal.*`: Journal admission
- `src/hra-money.*`, `hra-account.*`, `hra-ledger.*`: accounting kernel
- `src/hra-plan.*`, `hra-entitlement_journal.*`, `hra-envelope_*`, `hra-report.*`: domain projection
- `tests/test_*.adb`: focused synthetic test suites

## License

MIT License. See [`LICENSE`](LICENSE).
