# Ada for aledger

aledgerを実装するときのAdaクイックリファレンス。
Adaの入門書や一般的なcoding standardではない。

この文書の最重要ルールは、**Adaの言語規則とaledger固有の選択を混同しないこと**。

## ラベル

- **[Ada]** 言語仕様またはstandard libraryの性質
- **[GNAT]** GNAT/GPRbuildなどtoolchain側の性質
- **[ALedger]** このrepositoryで選ぶ設計方針
- **[Current]** 現在の実装形。長期的な規則ではない

`[ALedger]` と `[Current]` を「Adaではこう書く」と一般化しない。
迷ったらcompilerとAda Reference Manualを優先する。

---

## 1. Package / spec / body / private

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

**[ALedger]** stable identity、admitted history、container-backed universeなど、representation自体が契約でない型ではprivate typeをまず検討する。

ただし「すべてprivate」は規則ではない。公開data shapeそのものに意味があるrecordまで隠す必要はない。

### Genericとprivate type

**[Ada]** generic instantiationには、その場所で必要な型やoperationがvisibleでなければならない。

**[ALedger]** containerがrepresentationならprivate part/bodyへ置く。clientが必要なのが

```text
Empty / Include / Contains / Length
```

だけなら、そのsemantic APIを公開する。
compile workaroundとしてprivate representationを公開しない。

---

## 2. `with`, `use`, `use type`

**[Ada]** `with P;` はunit dependency。

**[Ada]** `use P;` はpackage visible partの名前をdirectly visibleにする。

**[Ada]** `use type T;` は型のprimitive operatorをdirectly visibleにするときに使える。

```ada
use type ALedger.Money.Quantity;

if Q > ALedger.Money.Zero_Quantity then
   ...
end if;
```

**[ALedger]** operatorだけが欲しいなら広い`use`より`use type`を検討する。
semantic ownerを見せたい場所ではpackage qualificationを残す。

これは絶対的なAda style ruleではない。

---

## 3. `Natural`, `Positive`, container length

**[Ada]** `Natural`は0以上、`Positive`は1以上。

**[ALedger]** 本当に0が無効な座標だけ`Positive`にする。

```ada
Header_Line : Positive;
```

探索中の「まだ見つからない」を0で表すなら`Natural`が自然なことがある。

```ada
Best_Index : Natural := 0;
```

**[Ada]** subtype conversionはrange checkを伴いうる。

```ada
Positive (I)
```

は「ここでは0でない」という根拠がある場所で行う。

**[Ada]** Ada.Containersの`Length`はcontainerのcount型で、index型そのものではない。

**[Current]** aledgerには次の形がある。

```ada
for I in 1 .. Natural (Items.Length) loop
   ...
end loop;
```

Ada一般の唯一のidiomではない。
indexが不要なら、より直接的な

```ada
for Item of Items loop
   ...
end loop;
```

を優先する。
indexはposting positionやaligned evidenceなど、index自体に意味があるとき使う。

---

## 4. `String` のboundsを決め打ちしない

**[Ada]** unconstrained `String` のlower boundは必ずしも1ではない。

```ada
Text'First
Text'Last
Text'Length
```

を使う。

```ada
Text (Text'First .. Text'First + 9)
```

のように書き、理由なく `Text (1 .. 10)` としない。

empty string、null range、slice境界にも注意する。
parser/source evidence/filesystem boundaryでは特に重要。

### `String` と `Unbounded_String`

**[Ada]** `String`は固定boundsのarray。`Unbounded_String`は長さが変化するtextを保持するlibrary type。

**[ALedger]** call中だけ読む入力は`String`、recordへ保持するsource path、metadata、diagnosticなどは`Unbounded_String`が自然なことが多い。

```ada
Source_Path : Unbounded_String;
Message     : Unbounded_String;
```

identityやmoneyに専用型があるなら、text型へ戻してdomain modelの中心を作らない。

---

## 5. Containersはgeneric。公開するかは別問題

**[Ada]** standard containersはgeneric packageをinstantiateして使う。

```ada
package Payment_Vectors is new Ada.Containers.Indefinite_Vectors
  (Index_Type   => Positive,
   Element_Type => Planned_Payment);
```

**[ALedger]** container型そのものがclient contractならvisible partでもよい。
単なるrepresentationなら隠す。

containerを隠すためだけの巨大wrapper層は作らない。
`Contains`, `Resolve`, `Observe`, `Length`などdomain上必要な語彙だけを公開する。

---

## 6. Discriminated recordでcaseを型にする

**[Ada]** discriminated recordはkindごとに存在するcomponentを変えられる。

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

**[ALedger]** `Target`が存在してよいcase/いけないcaseがdomain上明確なら有力。
Boolean flag + 常時存在するdummy fieldへ潰さない。

ただし単純なenumで十分な状態までvariant recordにしない。

---

## 7. Constructor / admission / contractを分ける

**[ALedger]** 小さなvalue constructorと、source全体を検証するadmissionは別責任。

```text
Create_Plan_Id
```

が成功しても、cross-reference、duplicate history、whole-document invariantまでadmittedとは限らない。

### `Pre` / `Post`

**[Ada]** preconditionはcallerの義務を表せる。

```ada
with Pre => Root_Path'Length > 0
```

**[ALedger]** user-owned sourceのsyntax errorやunknown referenceを`Pre`へ押し込まない。
それらはparser/admissionがfail-closedでdiagnosticを返す。

```text
caller obligation     -> Pre/Post
untrusted source law  -> admission result + diagnostic
```

---

## 8. `Boolean + out` とfailure state

**[ALedger]** fail-closed APIで`Boolean`と`out`を使う場合、failure pathで半端なresultを残さない。

```ada
Result := Empty_Observation;

if Invalid then
   Diag := ...;
   return False;
end if;
```

`Empty_Registry`, `Empty_History`, `Empty_Observation`はaledgerのcompositionで便利なpattern。
**[Current]** すべてのAda programに必要なidiomではない。

---

## 9. Exceptionはboundary failureとprogramming errorを分ける

**[Ada]** exceptionは正規の言語機能。

**[ALedger]** filesystem、stream I/O、external library boundaryでは、予想されるexternal failureをdiagnosticへ変換することがある。

`when others`を通常のdomain branchingとして使わない。
可能なら予想されるexceptionを狭く扱う。

broad catchを使うときはprogramming errorまで「source error」に見せかけていないか確認する。
private Household sourceの内容をpublic logへ複製しない。

---

## 10. AdaをOOPやpointerへ寄せすぎない

**[Ada]** package/private type/generic/contractはtagged typeなしでも使える。

**[ALedger]** domainがdispatch hierarchyを必要とするまで、package + plain type + operationでよい。
「Adaらしく見せるため」にinheritanceを作らない。

**[Ada]** parameter passingやcontainer利用だけを理由にCのpointer相当を毎回書く必要はない。

**[ALedger]** ownership/lifetime上の理由がない限りaccess typeをdefault abstractionにしない。

---

## 11. Package hierarchyとdirectoryを混同しない

**[Ada]** child packageは名前自体がsemantic hierarchyになる。

```text
ALedger.Envelope
ALedger.Envelope.Fulfillment
```

**[GNAT]** default naming schemeではexpanded unit nameがsource filenameへ対応する。

**[ALedger]** `src/`がflat directoryであること自体は問題ではない。
child package化はprivacy、dependency、semantic ownershipに本物の階層があるときに行う。
見た目だけのためにpackage名を変更しない。

package変更時はまず `.ads` のvisible/private partを読み、その後body、tests、callersを見る。
これはAda言語規則ではなく、spec/body分離を活かすaledgerの作業順。

---

## 12. aledger固有のlawをAda一般へ輸出しない

次は重要だが、**Ada一般のbest practiceではない**。

- exact amountは`ALedger.Money`を通す
- source provenanceを後からraw text再探索で復元しない
- admitted valueとsource evidenceのalignmentを保つ
- unknown meaningを推測しない
- source observation / admission / calculation / rendering / mutationを分ける
- domain vocabularyを`Generic_Manager`や`Process_Items`へ潰さない

これらはaledgerのdomain/architecture law。

SPARKについても同じ。
proofしやすさのためだけにpublic domain vocabularyを歪めない。
まずsemantic ownerとlawを明確にし、machine-checkableな部分を強める。

---

## 新しいpatternを広げる前の5問

1. これは **[Ada]** の言語上必要な形か
2. **[GNAT]** のtoolchain都合か
3. **[ALedger]** のdomain/architecture上の選択か
4. 単なる **[Current]** convenienceか
5. 別のAda codebaseでも通用する知識だと誤解させないか

分類できないものを「Ada best practice」として追加しない。

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

GNATのstyle checksやformatterはAda言語仕様そのものではない。
導入するならproject policyとして明示する。

---

## 外部参照

言語仕様を確認するときはこの文書より一次資料を優先する。

- Ada 2022 Reference Manual: https://www.ada-auth.org/standards/22rm/html/RM-TOC.html
- AdaCore Learn, Packages: https://learn.adacore.com/courses/advanced-ada/parts/modular_prog/packages.html
- AdaCore Learn, Containers: https://learn.adacore.com/courses/intro-to-ada/chapters/standard_library_containers.html
- GNAT User's Guide, style checking: https://docs.adacore.com/gnat_ugn-docs/html/gnat_ugn/gnat_ugn/building_executable_programs_with_gnat.html
