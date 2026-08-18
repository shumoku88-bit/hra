# HRA 作業入口

## Repository command hub

人間・AIとも、通常のrepository操作は`./tools/al`を唯一の入口にする。

```sh
./tools/al help
./tools/al build
./tools/al test
./tools/al prove
./tools/al qualify
./tools/al check --base /path/to/canonical-root
./tools/al report --base /path/to/canonical-root
./tools/al tui --base /path/to/canonical-root
```

- `build`はcurrent sourceをAlireでbuildする
- `test`はbuild後にcanonical `test_runner`を実行する
- `prove`はSPARK proof projectを実行する
- `qualify`はbuild + test + proveのrepository-only qualification
- `check`はcanonical Household sourceのadmission checkであり、repository qualificationとは別
- raw `alr` / `gprbuild` / `gnatprove` / `bin/*` を通常手順としてdocsやAI指示へ増やさない
- `tools/al`はdispatchだけを所有し、domain semantics、source admission、writer authorityをshellへ実装しない

## Naming boundary

公開project / repository名は **HRA**、long nameは **Household Reckoning Apparatus** とする。

現在のAda namespace、Alire crate、native executableには移行前の`ALedger` / `aledger`が残る。これらはpublic project identityとは別のinternal compatibility nameとして扱い、semantic changeへ機械的renameを混ぜない。internal namingを変更する場合は、それ自体をnon-semantic migrationとして分離する。

`./tools/al`はrepository command hubのstable entry pointとして維持し、public project名へ合わせるためだけにはrenameしない。

## Canonical Household law

HRA専用の正データを作らない。`h-kernel`と同じuser-owned private Household rootを読む。

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

詳細は[`docs/CANONICAL_HOUSEHOLD.md`](docs/CANONICAL_HOUSEHOLD.md)を参照する。Report、Editor、TUIを含む実装対象と順序は[`docs/CAPABILITY_ROADMAP.md`](docs/CAPABILITY_ROADMAP.md)を確認する。Actual、Plan、Envelope、Backingの金額式へ触れる場合は[`docs/PROOF_CORE.md`](docs/PROOF_CORE.md)を読み、`./tools/al prove`を実行する。Ada実装時の言語規則とHRA固有のconventionの区別は[`docs/ADA_FOR_ALEDGER.md`](docs/ADA_FOR_ALEDGER.md)を参照する。

## 設計原則

- source bytesの観測、syntax admission、domain calculation、rendering、filesystem mutationを分離する
- exact Quantity、Commodity、Account identity、durable identity、provenance、Posting orderを失わない
- Accountの意味を名前から推測する実装は互換完了時に廃止する
- UI/CLIへ会計ruleやsource basenameを複製しない
- generic parser、plugin、repository/session frameworkを先回りして作らない
- source format migrationとwriter cutoverを同じ変更へ混ぜない

## Ada growth guardrails

- canonical writerはcomplete Household candidate admissionを通るまで昇格させない
- production / tests / proofのbuild境界を混ぜない
- `when others`はparser / I/O / application boundaryに限定し、domain lawの失敗を潰さない
- exact fixed-pointとrange safetyを別に扱い、proof-facing値はbounded admissionを通す
- Editor/TUIへuse-case compositionを積まず、Application境界を先に置く
- 8-source observationにwriter concurrencyが入る段階で途中変更検出を追加する

## 検証

Repository-only qualification:

```sh
./tools/al qualify
```

canonical Householdを含む確認:

```sh
./tools/al check --base /path/to/canonical-root
```

private rootを使う検証ではsource内容や生成Reportを公開ログへ出さない。
