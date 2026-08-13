# aledger 作業入口

## Canonical Household law

aledger専用の正データを作らない。`h-kernel`と同じuser-owned private Household rootを読む。

canonical rootは次の8 sourceだけで構成する。

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

- basenameは`ALedger.Canonical_Source`だけが解決する
- legacy source、fallback、redirect、engine別copy、dual authorityを追加しない
- unknownまたは未対応の意味を推測・黙殺しない
- private sourceの内容をrepository、test fixture、logへ複製しない
- reader capabilityとwriter authorityを分ける

詳細は[`docs/CANONICAL_HOUSEHOLD.md`](docs/CANONICAL_HOUSEHOLD.md)を参照する。

## 設計原則

- source bytesの観測、syntax admission、domain calculation、rendering、filesystem mutationを分離する
- exact Quantity、Commodity、Account identity、durable identity、provenance、Posting orderを失わない
- Accountの意味を名前から推測する実装は互換完了時に廃止する
- UI/CLIへ会計ruleやsource basenameを複製しない
- generic parser、plugin、repository/session frameworkを先回りして作らない
- source format migrationとwriter cutoverを同じ変更へ混ぜない

## 検証

```sh
alr build
./bin/test_runner
./bin/aledger check --base /path/to/canonical-root
```

private rootを使う検証ではsource内容や生成Reportを公開ログへ出さない。
