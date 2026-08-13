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

現在は4 journalと`issues.tsv`のadmissionが部分実装で、3 TOML sourceはexact observationのみです。h-kernel互換のtyped policy admissionとcross-source validationは今後のmigration chapterです。現時点のReportをcanonicalな意思決定結果として扱わないでください。

詳しくは以下を参照してください。

- [`docs/CANONICAL_HOUSEHOLD.md`](docs/CANONICAL_HOUSEHOLD.md)
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
- [`SECURITY.md`](SECURITY.md)

## Kernel invariants

- `delta 0.00000001`のexact decimal Quantity
- Commodity別のcanonical Balance
- double-entry balance law
- typed Account registry
- inverse postingとexplicit relationによるreversal
- source observationと会計計算、rendering、filesystem effectの分離

## Build and test

```sh
alr build
./bin/test_runner
```

canonical rootの構造と現在対応済みの意味を検証します。

```sh
./bin/aledger check --base /path/to/private-household-root
```

`LEDGER_DATA_DIR`または`HKERNEL_LEDGER_DATA_DIR`でもrootを指定できます。private source、生成Report、local pathを公開repositoryやCI logへ出力しないでください。

## Source layout

- `src/aledger-canonical_source.*`: 固定8-source pathとexact-byte observation
- `src/aledger-household.*`: complete observationからのHousehold composition
- `src/aledger-journal.*`: Journal admission
- `src/aledger-money.*`, `aledger-account.*`, `aledger-ledger.*`: accounting kernel
- `src/aledger-plan.*`, `aledger-budget.*`, `aledger-report.*`: domain projection
- `tests/test_runner.adb`: synthetic test suite
