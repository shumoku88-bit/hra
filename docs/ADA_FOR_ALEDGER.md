# Ada for aledger

この文書はAdaの入門書ではない。

aledgerを実装するときに繰り返し現れるAda固有の判断を短く参照するためのもの。
一般的なAdaの規則と、aledger固有の設計判断を混同しないことを最優先にする。

## ラベル

各項目は必要に応じて次のラベルで区別する。

- **[Ada]** 言語仕様または標準ライブラリの性質
- **[GNAT]** GNAT/GPRbuildなど実装・toolchain側の性質
- **[ALedger]** このrepositoryで選んでいる設計方針
- **[Current]** 現在の実装形であり、長期的な設計規則ではないもの

`[ALedger]` や `[Current]` を一般的なAdaの作法として覚えないこと。
他のAda projectでは別の選択が自然なことがある。

---

## 1. Packageが主なmodule境界

**[Ada]** packageはAdaの基本的なmodularization単位。
通常、specificationは`.ads`、bodyは`.adb`に置かれる。

```ada
package ALedger.Plan is
   type Plan_Id is private;

   function Text (PID : Plan_Id) return String;

private
   type Plan_Id is record
      -- representation
   end record;
end ALedger.Plan;
```

```ada
package body ALedger.Plan is
   function Text (PID : Plan_Id) return String is
   begin
      ...
   end Text;
end ALedger.Plan;
```

**[Ada]** visible partはclientが知る契約、private partはclientから隠すrepresentation、bodyはimplementation。

**[ALedger]** stable identity、admitted history、domain observationなどでrepresentation自体が契約ではない場合は、private typeをまず検討する。
ただし「すべてprivateにする」は規則ではない。値そのものが公開data shapeであるrecordまで隠す必要はない。

---

## 2. Private typeはrepresentation hidingであって儀式ではない

**[Ada]** `type T is private` はpartial viewを公開し、full viewをpackage private partに置く。
clientは公開operationを通して値を扱う。

**[ALedger]** private typeを使う主な理由は次のいずれか。

- identityの内部表現へ依存させたくない
- container実装をclientへ漏らしたくない
- invalid constructionを公開したくない
- historical/admitted stateを勝手に組み立てさせたくない

例:

```ada
type Plan_Id_Universe is private;

function Empty_Plan_Id_Universe return Plan_Id_Universe;
procedure Include (Universe : in out Plan_Id_Universe; PID : Plan_Id);
function Contains (Universe : Plan_Id_Universe; PID : Plan_Id) return Boolean;
function Length (Universe : Plan_Id_Universe) return Natural;
```

**[ALedger]** clientが必要なのはcontainerそのものではなく、stable PlanIdの存在を問い合わせる能力である。

**[Current]** private `Plan_Id`をvisible partのgeneric container instantiationへ直接持ち上げる設計でvisibility問題に当たったことがある。
その場合、compile workaroundとしてrepresentationを公開しない。
containerをprivate partへ移すか、representation-agnosticなAPIを公開する。

---

## 3. Generic containerのinstantiation場所もAPI設計の一部

**[Ada]** standard containersはgeneric packageとして提供される。
使用前にelement/index型を指定してinstantiateする。

```ada
package Payment_Vectors is new Ada.Containers.Indefinite_Vectors
  (Index_Type   => Positive,
   Element_Type => Planned_Payment);
```

**[Ada]** generic instantiationには、その場所で必要な型やoperationがvisibleでなければならない。

**[ALedger]** public container型を本当にclient contractとして必要とする場合だけvisible partでinstantiateする。
containerが単なるrepresentationならprivate partまたはbodyに置く。

**[ALedger]** containerを隠すためだけにwrapperを大量生産しない。
公開すべきsemantic operationが `Contains`, `Resolve`, `Observe`, `Length` など少数なら、その語彙を公開する。

---

## 4. `with`, `use`, `use type` を区別する

**[Ada]** `with P;` はunit dependencyを与える。

```ada
with ALedger.Money;
```

**[Ada]** `use P;` はpackage visible partの名前をdirectly visibleにする。

**[Ada]** `use type T;` は主に型のprimitive operatorをdirectly visibleにするために使える。

```ada
use type ALedger.Money.Quantity;

if Q > ALedger.Money.Zero_Quantity then
   ...
end if;
```

**[ALedger]** operatorだけが必要なら、広い`use`より`use type`を優先してよい。
ただしpackage qualificationが読みやすい場所まで機械的に`use type`へ変えない。

**[ALedger]** semantic boundaryでは、どのpackageが意味を所有しているか見えるqualificationを残す価値がある。

---

## 5. Subtypeは意味のある制約として使う

**[Ada]** `Natural` は0以上、`Positive` は1以上のinteger subtype。

**[ALedger]** 「本当に0が無効」な座標だけを`Positive`にする。
例: source line number、1-based posting position。

```ada
Header_Line : Positive;
```

**[ALedger]** 「未設定」を0で表したい内部探索結果には`Natural`が適切なことがある。

```ada
Best_Index : Natural := 0;
```

**[Ada]** subtype conversionはruntime range checkを伴いうる。

```ada
Positive (I)
```

**[ALedger]** conversionは「ここまでに0でないことが成立した」という境界で行う。
根拠のないcastとして使わない。

---

## 6. Container `Length` とindex型を混同しない

**[Ada]** Ada.Containersの`Length`はcontainer用のcount型を返す。
index型そのものとは別物。

**[Current]** aledgerでは次の形が多い。

```ada
for I in 1 .. Natural (Items.Length) loop
   ...
end loop;
```

これはaledgerの現在の小規模dataでは実用的だが、Ada一般の唯一のidiomではない。

**[ALedger]** indexが意味を持たないならelement iterationを優先する。

```ada
for Item of Items loop
   ...
end loop;
```

indexがprovenance、posting position、aligned evidenceなどの意味を持つときだけindex iterationを使う。

---

## 7. `String` は必ず1-originとは限らない

**[Ada]** unconstrained `String` のlower boundは1とは限らない。

```ada
Text'First
Text'Last
Text'Length
```

を使う。

悪い前提:

```ada
Text (1 .. 10)
```

境界が本当に1-originであると保証されていない限り避ける。

より安全な形:

```ada
Text (Text'First .. Text'First + 9)
```

**[ALedger]** parser、source evidence、filesystem boundaryでは特に`'First`/`'Last`を尊重する。

**[Ada]** empty string、null range、sliceの境界を意識する。
`Length = 0`を先に検査する方が読みやすい場合はそうする。

---

## 8. `String` と `Unbounded_String` の役割を分ける

**[Ada]** `String` は固定boundsのarray type。
`Unbounded_String` は長さが変わるtextを扱うlibrary type。

**[ALedger]** API入力としてそのcall中だけ読むtextは`String`が自然なことが多い。

```ada
function Resolve (Date : String) return ...;
```

**[ALedger]** record内で保持するsource path、metadata value、diagnostic textなどは`Unbounded_String`を使うことが多い。

```ada
Source_Path : Unbounded_String;
Message     : Unbounded_String;
```

**[ALedger]** `To_String`/`To_Unbounded_String`の往復をdomain modelの中心に増やしすぎない。
identityやmoneyに専用型があるならそちらを使う。

---

## 9. Discriminated recordは「場合によってfieldが違う」を型にする

**[Ada]** variantを持つdiscriminated recordは、kindごとに存在するcomponentを変えられる。

```ada
type Fulfillment_Route
  (Kind : Fulfillment_Route_Kind := Not_Fulfillment_Target)
is record
   case Kind is
      when Fulfills_Envelope =>
         Target : Envelope_Id;
      when Not_Fulfillment_Target =>
         null;
   end case;
end record;
```

**[ALedger]** `Target`が存在してよいcaseと存在してはいけないcaseがdomain上明確なら、この形は有力。

**[ALedger]** Boolean flag + 常に存在するdummy fieldへ落とさない。
ただし単純なenumだけで十分な状態まで無理にvariant recordへしない。

---

## 10. Constructorとadmissionを混同しない

**[ALedger]** 小さなvalue constructorと、source全体を検証するadmissionは別責任。

例:

```ada
function Create_Plan_Id (...) return Boolean;
```

と

```ada
function Admit
  (Decisions   : Decision_Vectors.Vector;
   Known_Plans : Plan_Id_Universe;
   ...)
   return Boolean;
```

は違う。

**[ALedger]** constructorだけではcross-reference、duplicate history、whole-document invariantまで検証済みとはみなさない。

---

## 11. `Pre` / `Post` はparserのvalidation代わりではない

**[Ada]** preconditionはcallerが満たすべきsubprogram contractを表せる。

```ada
function Load (...)
  return Boolean
  with Pre => Root_Path'Length > 0;
```

**[ALedger]** user-owned sourceのsyntax errorやunknown referenceを`Pre`へ押し込まない。
それらはfail-closed admissionとしてdiagnosticを返す。

悪い考え方:

```text
sourceが正しいことをPreにする
```

良い分離:

```text
caller contract      -> Pre/Post
untrusted source law -> parser/admission result + diagnostic
```

**[ALedger]** contractは「呼出側の義務」と「入力dataの検証」を区別するために使う。

---

## 12. Boolean + `out` APIではfailure valueを明確にする

**[ALedger]** fail-closed APIで`Boolean`と`out`を組み合わせる場合、failure pathでcallerが半端な結果を観測しないようにする。

```ada
Result := Empty_Observation;

if ...invalid... then
   Diag := ...;
   return False;
end if;
```

**[ALedger]** empty constructorを用意するのは便利だが、意味のある「空」と「未初期化」を混同しない。

**[Current]** aledgerには `Empty_Registry`, `Empty_History`, `Empty_Observation` などがある。
これはrepositoryのcomposition styleであり、すべてのAda programに必要なpatternではない。

---

## 13. Exceptionはexternal boundaryとprogramming errorを分ける

**[Ada]** exceptionは言語機能であり、必ず避けるものではない。

**[ALedger]** filesystem、stream I/O、library boundaryではexternal failureをdomain diagnosticへ変換する必要があることがある。

**[ALedger]** `when others`を通常のdomain branchingとして使わない。
可能なら予想されるexceptionを狭く扱う。

**[ALedger]** broad catchを使う場合は、programming errorまで「source error」に見せかけていないか確認する。

**[ALedger]** private Household sourceの内容をexception messageやpublic logへ複製しない。

---

## 14. Access typeを「参照渡しのため」に導入しない

**[Ada]** parameter passingやcontainer利用のためにCのpointer相当を毎回書く必要はない。

**[ALedger]** ownership/lifetime上の理由がない限り、access typeを抽象化のdefaultにしない。
package、private type、value、containerで表現できるならそちらを先に検討する。

---

## 15. OOPはAdaを使うための必須条件ではない

**[Ada]** Adaのpackage/private type/generic/contractはtagged typeを使わなくても利用できる。

**[ALedger]** domainが自然にdispatch hierarchyを要求するまでは、package + plain type + operationでよい。
「Adaらしくするため」にinheritance hierarchyを作らない。

---

## 16. Package hierarchyとdirectory hierarchyを混同しない

**[Ada]** child packageは名前自体がhierarchyを表す。

```ada
ALedger.Envelope
ALedger.Envelope.Fulfillment
```

**[GNAT]** default naming schemeではexpanded unit nameがsource filenameへ対応する。

**[ALedger]** `src/`がflat directoryであること自体は問題ではない。
folderを増やすだけではAdaのsemantic module境界は強くならない。

**[ALedger]** child package化は、privacy、dependency、semantic ownershipの階層が本当にあるときに行う。
見た目を整えるためだけに `ALedger.Envelope_Fulfillment` を即座に `ALedger.Envelope.Fulfillment` へ変えない。

---

## 17. Public specを先に読む

**[ALedger]** packageを変更するときは、原則として次の順で読む。

1. `.ads` visible part
2. `.ads` private part
3. `.adb` body
4. direct tests
5. callers

これはAda言語の規則ではなく、spec/body分離を活かすaledgerの作業順。

**[ALedger]** bodyから読んで偶然のimplementation detailをAPI semanticsだと思い込まない。

---

## 18. Domain vocabularyをstandard container vocabularyへ潰さない

**[ALedger]** domain operationが `Resolve_Decision`, `Observe`, `Admit`, `Entitlement_For`, `Net_For` なら、その語彙を保持する。

悪い抽象化:

```text
Get_Map_Value
Process_Items
Generic_Manager
```

良い抽象化:

```text
Resolve_Decision
Observe_Consumption
Admit_Backing_Policy
```

これはAda固有ではないが、package specが契約として強く見えるAdaでは特に重要。

---

## 19. Exact arithmeticは`ALedger.Money`に従う

**[ALedger]** accounting amountへ`Float`を導入しない。
既存の`Quantity`, `Amount`, `Balance`, `Commodity`を使う。

**[ALedger]** numeric literalが便利でも、Money packageのexactness invariantを迂回しない。
金額式へ触れたら `docs/PROOF_CORE.md` と `./tools/prove` を確認する。

---

## 20. Source provenanceは値と同じくらい重要

**[ALedger]** parsed valueだけ残してsource ownershipを捨てない。
必要なsemantic evidenceには、元document、line、stable identity、historical decision coordinateなどを保持する。

**[ALedger]** provenanceを復元するために後からraw textを再探索する設計を増やさない。
source admission時に得られるevidenceは、対応するadmitted valueとalignmentを保つ。

これはAda一般の作法ではなくaledgerのdomain law。

---

## 21. Compiler optionを一般Adaの正解と思わない

**[Current]** `aledger.gpr` が現在のcompiler設定のsource of truth。

現在はAda 2022、assertion有効化、warning設定などをproject fileで指定している。

**[GNAT]** GNATにはstyle checkやformatterもあるが、それらはAda言語仕様そのものではない。
GNATのcoding styleを採用する場合も、project policyとして明示して採用する。

**[ALedger]** formatterやstyle checkを導入するためだけにsemantic diffを混ぜない。

---

## 22. SPARKは「Adaより正しい別言語」ではない

**[ALedger]** SPARK対象部分ではproof可能性、initialization、contracts、side effect境界を意識する。

ただし、

```text
proofしやすい
```

ことと

```text
domain modelとして自然
```

であることを混同しない。

**[ALedger]** まずsemantic ownerとlawを明確にし、その後SPARKでmachine-checkableな部分を強める。
proofの都合だけでpublic vocabularyを歪めない。

---

## 23. 新しいAda patternを導入するときの確認

新しい書き方をrepository全体へ広げる前に次を確認する。

- これは **[Ada]** の言語上必要な形か
- それとも **[GNAT]** のtoolchain都合か
- **[ALedger]** のdomain/architecture上の選択か
- 単なる **[Current]** implementation convenienceか
- package specを単純にするか
- representationを不必要に公開しないか
- provenanceを失わないか
- proof boundaryを悪化させないか
- 別のAda codebaseでも通用する知識だと誤解させないか

判断できなければ、この文書へ「best practice」として追加しない。

---

## 24. 変更後の最小確認

repositoryの正式な検証入口は`AGENTS.md`とproject scriptsをsource of truthにする。

```sh
alr build
./bin/test_runner
./tools/prove
./bin/aledger check --base /path/to/canonical-root
```

focused executableがある変更では、それも実行する。

compilerを実行できない環境では、`compiled`、`tests passed`、`proved`と報告しない。
静的確認と実行確認を分けて記録する。

---

## 外部一次資料

この文書より言語仕様を優先する。

- Ada Reference Manual, 7.3 Private Types and Private Extensions
  - https://docs.adacore.com/live/wave/arm12/html/arm12/arm12-7-3.html
- AdaCore Learn, Advanced Ada: Packages and use type
  - https://learn.adacore.com/courses/advanced-ada/parts/modular_prog/packages.html
- AdaCore Learn, Standard library: Containers
  - https://learn.adacore.com/courses/intro-to-ada/chapters/standard_library_containers.html
- GNAT User's Guide, style checking
  - https://docs.adacore.com/gnat_ugn-docs/html/gnat_ugn/gnat_ugn/building_executable_programs_with_gnat.html

この文書とcompiler、Ada Reference Manualが矛盾した場合、compiler errorを隠すためにdomain modelを崩さず、まず言語規則を再確認する。
