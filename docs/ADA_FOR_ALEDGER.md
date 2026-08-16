# Ada for aledger

aledgerを実装するときのAdaクイックリファレンス。
Adaの入門書や一般的なcoding standardではない。

この文書の目的は「禁止項目」を増やすことではない。
**実装したい意味から、Adaがもともと持つ語彙へ素直に降りるための地図**にする。

## ラベル

- **[Ada]** 言語仕様またはstandard libraryの性質
- **[GNAT]** GNAT/GPRbuildなどtoolchain側の性質
- **[ALedger]** このrepositoryで選ぶ設計方針
- **[Current]** 現在の実装形。長期的な規則ではない

`[ALedger]` と `[Current]` はAdaそのものではない。
言語上の判断に迷ったらcompilerとAda Reference Manualを優先する。

---

## まず「意味 → Adaの語彙」で考える

| 表したいもの | まず検討するAdaの語彙 |
| --- | --- |
| module / semantic owner | `package`, child package |
| representationを隠したdomain value | private type |
| 有限個の状態 | enumeration type |
| 状態ごとに存在するfieldが違う値 | discriminated / variant record |
| 値域そのものに意味がある数 | subtype / range |
| shapeが固定・自然にboundedな列 | array / constrained array |
| 長さが動的なcollection | `Ada.Containers` |
| 型に依存する再利用可能なalgorithm/data structure | generic |
| callerが満たす契約 | `Pre`, `Post` |
| 型全体が守る性質 | predicate / invariant |
| 一時的に読むtext | `String` |
| 長さが変わり保持されるtext | `Unbounded_String` など |
| ownership / aliasing / lifetimeを明示した参照 | access type |
| 本当にruntime dispatchするdomain hierarchy | tagged type / dispatching |

**[ALedger]** 新しい抽象化を作る前に、上の標準語彙でdomainをそのまま表せないかを見る。

---

## 1. Packageを意味のownerにする

**[Ada]** packageはAdaの基本的なmodule境界。
通常、`.ads`がspecification、`.adb`がbody。

```ada
package ALedger.Plan is
   type Plan_Id is private;
   function Text (PID : Plan_Id) return String;
private
   type Plan_Id is record
      ...
   end record;
end ALedger.Plan;
```

- visible part: clientへ公開する契約
- private part: clientから隠すrepresentation
- body: implementation

**[ALedger]** stable identity、admitted history、routing policyなどは、意味を所有するpackageを先に決める。
UIやrendererから使うときも、そのpackageが公開したoperationを通す。

### Child package

**[Ada]** child packageは名前そのものにhierarchyを持てる。

```text
ALedger.Envelope
ALedger.Envelope.Fulfillment
```

**[ALedger]** ownershipやprivacyに本物の親子関係ができたときchild packageを検討する。
filesystem上のfolder整理とは別の判断。

---

## 2. Representationを隠すならprivate type

**[Ada]** `type T is private` はclientにpartial viewだけを見せ、full viewをpackage private partへ置ける。

**[ALedger]** 次のような値ではprivate typeが自然な候補になる。

- stable identity
- admitted history
- registry / universe
- invalid constructionを外へ出したくないvalue

例:

```ada
type Plan_Id_Universe is private;

function Empty return Plan_Id_Universe;
procedure Include (Universe : in out Plan_Id_Universe; PID : Plan_Id);
function Contains (Universe : Plan_Id_Universe; PID : Plan_Id) return Boolean;
function Length (Universe : Plan_Id_Universe) return Natural;
```

clientが知るのはcontainer実装ではなく、stable PlanIdを問い合わせる語彙。

### Genericとの組み合わせ

**[Ada]** generic instantiationには、その場所でformal parameterへ渡す型やoperationがvisibleである必要がある。

**[ALedger]** containerがprivate typeのrepresentationなら、instantiationもprivate part/body側へ置くと自然なことが多い。

---

## 3. 有限状態はenumeration、shapeの違いはvariant record

**[Ada]** finite stateはenumeration typeで直接表せる。

```ada
type Route_Kind is
  (Fulfills_Envelope,
   Not_Fulfillment_Target);
```

**[Ada]** caseごとに存在するcomponentが違うならdiscriminated recordを使える。

```ada
type Fulfillment_Route
  (Kind : Route_Kind := Not_Fulfillment_Target)
is record
   case Kind is
      when Fulfills_Envelope =>
         Target : Envelope_Id;
      when Not_Fulfillment_Target =>
         null;
   end case;
end record;
```

**[ALedger]** 「このcaseではTargetが存在する」というdomain lawを、commentやdummy valueではなくdata shapeとして表す。

単に状態名だけあれば十分ならenumerationだけでよい。

---

## 4. 値域に意味があるならsubtypeを使う

**[Ada]** `Natural`は0以上、`Positive`は1以上のinteger subtype。
独自のrange/subtypeも作れる。

```ada
subtype Source_Line is Positive;
```

**[ALedger]** 0がdomain上存在しない座標は、その事実が型に見えるようにする。
source lineや1-based posting positionなどが候補。

探索途中の「まだ見つからない」を0で表すなら`Natural`が自然なこともある。

```ada
Best_Index : Natural := 0;
```

**[Ada]** subtype conversionはrange checkを伴いうる。

```ada
Positive (I)
```

は「ここでは0でない」という既に成立した事実を型へ移す操作として使う。

---

## 5. Collectionはshapeから選ぶ

### Array

**[Ada]** shapeやboundsが自然に決まるdataにはarrayを使える。
arrayはindex subtypeもdomainの一部にできる。

### Standard container

**[Ada]** 動的なcollectionには`Ada.Containers`のgeneric package群がある。

```ada
package Payment_Vectors is new Ada.Containers.Indefinite_Vectors
  (Index_Type   => Positive,
   Element_Type => Planned_Payment);
```

**[ALedger]** containerそのものがpublic contractなら公開してよい。
representationならprivate partへ置き、`Contains`, `Resolve`, `Observe`などdomain operationを表へ出す。

### Container order と domain order

**[Ada]** containerが提供するiteration orderはcontainerの意味に従う。たとえばordered mapはkey orderで走査される。それはsource insertion orderを意味しない。

**[ALedger]** source declaration order、posting order、evidence orderなど、順序そのものがdomain lawなら、その順序を所有するsequenceを明示する。lookup用mapのiteration orderをdomain orderへ昇格させない。

Account Registryでは、source-admitted declaration sequenceがauthorityで、Account名からsequence positionへのmapはprivate lookup indexにすぎない。

```text
source order
  -> declaration sequence   -- domain authority
       ^
       |
     name -> position map   -- private lookup index
```

同じ値をmapとsequenceの両方へauthorityとして複製するのではなく、semantic valueはsequenceに一度だけ保持し、indexはその位置を指す。

逆にEnvelope Registryのように「canonical key sort」が明示的なcontractなら、ordered mapのkey orderとdomain orderが一致してよい。

### Iteration

index自体に意味がないときはelement iterationが直接的。

```ada
for Item of Items loop
   ...
end loop;
```

posting positionやaligned evidenceのようにindexが意味を持つ場合はindex iterationを使う。

**[Ada]** `Ada.Containers`の`Length`はcontainer用のcount型で、index型とは別。
必要な境界で明示的に型を合わせる。

---

## 6. Genericはcompile-timeの再利用語彙

**[Ada]** genericは型・operation・値などをformal parameterに取り、instanceを生成する。

**[ALedger]** 「同じalgorithmを複数domain typeへ適用したい」場合は、runtime object hierarchyを作る前にgenericが自然かを見る。

例:

```ada
generic
   type Element_Type is private;
   with function Key (Item : Element_Type) return String;
package Indexed_Observation is
   ...
end Indexed_Observation;
```

ただしdomain vocabularyが違うものまでgenericへ押し込めない。
共通のlawが本当に同じときに使う。

---

## 7. `with`, qualification, `use type`

**[Ada]** `with P;` はunit dependencyを宣言する。

**[Ada]** package名を付ければsemantic ownerがコード上に残る。

```ada
ALedger.Money.Zero_Quantity
```

**[Ada]** operatorだけをdirectly visibleにしたい場合は`use type`が使える。

```ada
use type ALedger.Money.Quantity;

if Q > ALedger.Money.Zero_Quantity then
   ...
end if;
```

**[ALedger]** domain ownerを読み取りやすくしたい場所ではqualificationを残し、operator noiseだけ減らしたい場所では`use type`を使う。

---

## 8. Textは境界の形に合わせる

**[Ada]** `String`は固定boundsを持つarray type。
unconstrained `String` parameterのlower boundは必ずしも1ではない。

```ada
Text'First
Text'Last
Text'Length
```

を使う。

```ada
Text (Text'First .. Text'First + 9)
```

parserやsource evidenceではempty string、null range、slice境界もdata shapeとして扱う。

**[Ada]** `Unbounded_String`は長さが変化するtextを保持するlibrary type。

**[ALedger]** call中だけ読むtextは`String`、recordに保持するsource path・metadata・diagnosticは`Unbounded_String`が自然なことが多い。

identityやmoneyには専用型を使い、domain modelをtext中心に戻さない。

---

## 9. Contractは「成立している意味」を型とoperationへ近づける

**[Ada]** `Pre` / `Post` でcallerとsubprogramの契約を表せる。

```ada
function Load (...)
  return Boolean
  with Pre => Root_Path'Length > 0;
```

型全体の性質にはpredicateやinvariantも使える。

**[ALedger]** contractはcaller/program側のlawへ使う。
user-owned sourceのsyntax、unknown reference、duplicate identityなどはadmissionが検査し、diagnosticを返す。

```text
caller/program law  -> contract
source/data law      -> admission
```

SPARKでproveできるlawは、domain vocabularyを保ったままmachine-checkableに寄せる。

---

## 10. Admission resultは完全な値として返す

**[ALedger]** parser/admissionは、成功なら完全にadmittedなvalue、失敗ならdiagnosticという境界を持つ。

現在のAPIで`Boolean + out`を使う場合は、failure側も明示的なempty valueから始める。

```ada
Result := Empty_Observation;

if Invalid then
   Diag := ...;
   return False;
end if;
```

**[Current]** `Empty_Registry`, `Empty_History`, `Empty_Observation`は現在のcomposition style。
将来より自然なresult representationが見つかれば変えてよい。

---

## 11. Exceptionはexceptionとして、domain resultはdomain resultとして扱う

**[Ada]** exceptionは正規の言語機能。

**[ALedger]** filesystemやstream I/Oのようにoperation自体が失敗する境界では、Adaのexceptionを受けてsource diagnosticへ翻訳することがある。

予想できるexternal failureは狭いboundaryで扱う。
domain上の通常状態はenumeration、variant、admission resultなどのdomain valueとして表す。

private Household sourceの内容はdiagnostic/public logへ複製しない。

---

## 12. Value、access、tagged typeを意味で選ぶ

### 普通のdomain value

**[Ada]** record、private type、package operationだけで多くのdomain modelを表せる。

**[ALedger]** identity、money、posting、routing、observationはまずvalueとして考える。

### Access type

**[Ada]** aliasing、dynamic allocation、lifetimeを明示して参照する必要がある場合はaccess typeがある。

**[ALedger]** その意味がdomainまたはimplementationに本当に存在するとき使う。

### Tagged type / dispatching

**[Ada]** runtime polymorphismが必要ならtagged typeとdispatching operationがある。

**[ALedger]** report kindやaccount roleが単なるfinite classificationならenumeration/caseが自然な場合も多い。
異なるimplementationをruntimeで同じinterfaceとして扱う意味が現れたらdispatchを検討する。

---

## 13. Ada-nativeとperformance

**Ada-nativeは「速くするためのsyntax」ではない。**
第一の利点は、domain shapeをcompiler・contract・proof toolが理解しやすい形で書けること。

そのうえでperformanceにも良い土台になりやすい。

- subtype/rangeで値域が明確になる
- array/containerのshapeが型に残る
- genericはinstanceごとに具体化される
- value-orientedなcodeは不要なaliasingを減らしやすい
- staticに分かるoperationはdynamic dispatchを必要としない

ただし、これだけで高速性は保証されない。

- standard containerは種類によってallocation/storage特性が違う
- unconstrained arrayにはruntime boundsが伴う
- Adaのrange/bounds/overflow等のruntime checksには実行costが生じる場合がある
- abstractionが実際に遅いかはcompiler optimizationと実行profileで確認する

**[Current]** aledgerの通常buildはAda 2022、assertions/contracts、warnings、`-O2`を有効にしている。
安全性を先に捨ててperformanceを作るのではなく、まず自然なAdaで書き、必要になった箇所を測定する。

SPARKで成立を証明できるcheckについて将来runtime policyを変える場合も、proofとmeasurementを根拠に決める。

---

## aledgerで新しい型やAPIを作るときの順序

1. domainで何が存在するかを普通の言葉で書く
2. finite stateならenumerationを検討する
3. caseでshapeが違うならdiscriminated recordを検討する
4. 値域に意味があるならsubtype/rangeを検討する
5. representationを隠す意味があるならprivate typeにする
6. collectionのshapeからarray/containerを選ぶ
7. 再利用するlawが本当に同じならgenericを検討する
8. caller lawを`Pre`/`Post`、data lawをadmissionへ置く
9. specを読んで意味が分かる状態にしてからbodyを書く
10. tests / proof / canonical rehearsalでlawを確認する

この順序は「Adaらしく見せる」ためではない。
**domainの文をAdaの型・package・contractへ一段ずつ写すための順序**。

---

## aledger固有のdomain law

次はAda一般ではなくaledgerのarchitecture law。
Adaの語彙を使って、これらを明瞭に表現する。

- exact amountは`ALedger.Money`が所有する
- source provenanceをadmitted valueと一緒に保持する
- posting orderとaligned evidenceを保つ
- unknown meaningを明示的にadmission failureまたはunknown stateとして扱う
- source observation / admission / calculation / rendering / mutationを別ownerにする
- domain vocabularyをpackage/API名に残す

---

## 検証

正式な入口は`AGENTS.md`とrepository scriptsをsource of truthにする。

```sh
alr build
./bin/test_runner
./tools/prove
./bin/aledger check --base /path/to/canonical-root
```

focused executableがある変更ではそれも実行する。
compilerを実行できない環境では `compiled` / `tests passed` / `proved` と報告しない。

---

## 外部参照

言語仕様を確認するときはこの文書より一次資料を優先する。

- Ada 2022 Reference Manual: https://www.ada-auth.org/standards/22rm/html/RM-TOC.html
- AdaCore Learn, Packages: https://learn.adacore.com/courses/advanced-ada/parts/modular_prog/packages.html
- AdaCore Learn, Containers: https://learn.adacore.com/courses/intro-to-ada/chapters/standard_library_containers.html
- GNAT User's Guide, performance: https://docs.adacore.com/gnat_ugn-docs/html/gnat_ugn/gnat_ugn/gnat_and_program_execution.html
