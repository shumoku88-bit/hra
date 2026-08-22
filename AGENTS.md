# HRA 作業入口

## Repository command hub

人間・AIとも、通常のrepository操作は`./tools/hra`を唯一の入口にする。

```sh
./tools/hra help
./tools/hra build
./tools/hra test
./tools/hra prove
./tools/hra qualify
./tools/hra check --base /path/to/canonical-root
./tools/hra report --base /path/to/canonical-root
```

- `build`はcurrent sourceをAlireでbuildする
- `test`はGPRがbuildしたfocused `test_*` suitesをすべて実行する
- `prove`はSPARK proof projectを実行する
- `qualify`はbuild + test + proveのrepository-only qualification
- `check`はcanonical Household sourceのadmission checkであり、repository qualificationとは別
- raw `alr` / `gprbuild` / `gnatprove` / `bin/*` を通常手順としてdocsやAI指示へ増やさない
- `tools/hra`はdispatchだけを所有し、domain semantics、source admission、writer authorityをshellへ実装しない

## Naming boundary

公開project / repository名は **HRA**、long nameは **Household Reckoning Apparatus** とする。

Ada namespaceは`HRA`、Alire crate、native executable、source prefixは`hra`を現在のinternal machine nameとする。旧`ALedger` / `aledger`のcompatibility aliasは持たない。internal namingを変更する場合は、それ自体をnon-semantic migrationとして分離する。

`./tools/hra`はrepository command hubのstable entry pointとして維持し、public project名の表示上の大文字小文字に合わせるためだけにはrenameしない。

## Canonical Household law

HRA専用の正データを作らない。`h-kernel`と同じuser-owned private Household rootを読む。

canonical rootは次の8 sourceだけで構成する。

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

source topology / meaningへ触れる作業では、HRA内の文書や過去実装をauthorityにしない。actual `h-kernel` contractとshared Household rootのcurrent inventoryを先に照合し、矛盾するHRA文書はstaleとしてHRA側を更新する。互換alias、fallback、private data側の穴埋めで差を隠さない。

- basenameは`HRA.Canonical_Source`だけが解決する
- legacy source、fallback、redirect、engine別copy、dual authorityを追加しない
- unknownまたは未対応の意味を推測・黙殺しない
- private sourceの内容をrepository、test fixture、logへ複製しない
- reader capabilityとwriter authorityを分ける

詳細は[`docs/CANONICAL_HOUSEHOLD.md`](docs/CANONICAL_HOUSEHOLD.md)を参照する。Report、Editor、TUIを含む実装対象と順序は[`docs/CAPABILITY_ROADMAP.md`](docs/CAPABILITY_ROADMAP.md)を確認する。Actual、Plan、Envelope、Backingの金額式へ触れる場合は[`docs/PROOF_CORE.md`](docs/PROOF_CORE.md)を読み、`./tools/hra prove`を実行する。Ada実装時の言語規則とHRA固有のconventionの区別は[`docs/ADA_FOR_HRA.md`](docs/ADA_FOR_HRA.md)を参照する。

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

## 最短feedback / PR flow

安全gateを減らさず、同じ証拠を得る高コストcommandの重複だけを避ける。

- 作業開始時にactual `main`、対象PR/head、latest CI、working treeを確認し、cleanな`main`からsmall branchを切る
- development中は変更箇所に対応する最小のbuild / focused test / proofを先に使い、同じheadへ`qualify`を繰り返さない
- branchは最初のreviewable commitでpushしてDraft PRを作り、long-running repository qualificationをGitHub CIと並行させる
- latest successful `main` CIや同条件の信頼できるbenchmarkがある場合、変更前baselineをローカルで再実行しない
- benchmarkは比較条件を固定し、各候補に必要な最小回数だけ実行する。全候補後の重複`qualify`は行わない
- Ada executionへ影響し得るPRでは、latest headのGitHub `qualify`をrepository-only full qualificationの正本とする。Ready / mergeのgateはlatest head CI success、mergeable、未解決blockerなしである
- tracked変更がMarkdown (`*.md`) だけのPR / `main` pushではAda qualification workflowを起動しない。merge gateはreview済みdiff、mergeable、未解決blockerなしであり、build / test / proofを証拠なく消費しない
- Markdown以外を1つでも変更するPRは、docsを同時変更していてもfull GitHub qualificationを通す
- local `qualify`はPR CIを使えない場合、CI failureの診断、またはlocal固有の証拠が必要な場合だけ実行する。private canonical root、platform固有動作、resource計測は必要な対象commandだけを使う
- taskがmergeまでを含む場合、gate通過後は待たずにReady、squash merge、branch delete、local `main` syncまで進める。明示されたreview checkpointやDraft維持指示は優先する
- qualificationが起動したPRのmerge後に走る`main` CIは結果を追跡するが、merge完了報告や次の独立作業を待たせるgateにはしない
- source mutation、CI/compiler failure、writer/domain correctnessでは速度よりexact evidenceを優先し、必要ならraw outputへ戻る

このflowはexecution-affecting変更のtest数、SPARK checks、proof level、full CI qualificationを減らす許可ではない。

## 検証

Repository-only qualification:

```sh
./tools/hra qualify
```

canonical Householdを含む確認:

```sh
./tools/hra check --base /path/to/canonical-root
```

private rootを使う検証ではsource内容や生成Reportを公開ログへ出さない。
