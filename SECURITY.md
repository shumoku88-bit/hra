# Security and private data boundary

HRAのsource codeと公開test fixtureには、canonical Household sourceの内容を含めない。

禁止対象:

- private Account名、Transaction、日付、数量、Plan、Issue、policyの転載
- canonical repository、backup、temporary file、recovery workspaceのcommit
- private rootのabsolute pathやsource本文をCI・Issue・PRへ出力すること
- generated Reportをfixtureとして公開すること

公開testにはsynthetic dataだけを使用する。private-root rehearsalは内容を標準出力へ出さず、成功・失敗と集約件数だけを扱う。writerを追加する場合はcanonical source外のsibling temporary file、stale rejection、checked restoreを検証し、writer authorityの明示的cutoverなしに運用しない。
