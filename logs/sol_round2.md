## 判定に必要な情報

- `logs/sol_round1.md` にある前回の NO-GO 15件の原文。提示された (A) は R2-1〜R2-10 に再編されており、15件との厳密な一対一対応を確定できない。
- 投稿前には、公開済みの `REPO_URL` と不変な `REPO_COMMIT`。各表に対応するログ、ソース、スクリプト、生ログ、code object、CSV がその commit に存在する必要がある。

以下の15件判定は、(A) から前回指摘を復元した暫定判定である。原文なしに「前回15件を厳密に1件ずつ確認済み」とは断定できない。

## 結論

**[NO-GO] 現在の投稿案はまだ投稿不可。**

公開 URL の未確定だけではない。R2で新たに追加された解釈に、測定を超えた断定が残っている。特に GL2C の「外来トラフィックだけ」「カーネル自身は一度も数えない」と、write-back L2 への帰属は測定から確定していない。

追加実験は必須としない。下記の断定を観測事実と推論に分離すれば閉じられる。

## GO に必要な全条件

以下が今回提示する全条件であり、これ以外を後出ししない。

1. `REPO_URL` / `REPO_COMMIT` を実在する公開 URL と commit hash に置換する。
2. 「Every table below names the log it comes from」と書くなら、**各表に実際のログファイル名を付ける**。現案では各表にログ名がない。付けないならその一文を削除する。
3. 「clang 22 と clang 23 で identical results」を維持するなら、両 toolchain の全58件の matrix log を公開する。`p1_matrix_full_714.log` しかないなら、「全58件網羅」は clang 23 に限定し、clang 22 について実際に測った範囲だけを書く。
4. PC sampling の 1,000,000 / 10,000,000 を、仕様上の保証なしに `silent failure` と断定しない。rc=0・出力なしという観測と、約73件という外挿を分離する。
5. GL2C split counter について、「外来トラフィックだけ」「カーネル自身の request は一度も数えない」を断定しない。非zero split と base inflation が同時に観測されたことまでに限定し、発生源は不明とする。
6. write sweep の一定差を write-back L2 の dirty line と確定しない。「整合する推論」「候補説明」と明記する。
7. `count*256` を corrected metric として到達可能と断定しない。`+2` intercept、非zero split、dispatch 外または終了後の write-back の意味が未確定であることを残す。
8. §4 の「failure modes」を中立化する。特に、非 `profile_*` DPM での zero counter と、列挙されていない counter 名の無診断省略は、仕様違反と確認できていない。削除するか「reproduction pitfalls / observed behaviors」とする。
9. `un-pinned levels` を `non-profile levels` に直す。`high` / `low` も設定上は performance level であり、「un-pinned」は不正確。
10. split の比率を示すなら全 split events を使う。該当 run は `6+6+193=205` なので、`205 / 1,050,439 ≈ 0.0195%`。または比率自体を削除する。
11. 上記修正後の最終成果物は **ROCm/ROCm#6613 への1件のコメントのみ**とする。新規 issue、PR、別コメントへの分割は行わない。

条件4〜10は前回の未提示要求の追加ではなく、R2で初めて現れた新しい測定・解釈へのレビューである。前回は固定ワークロード外挿、外来トラフィック帰属、一定 write deficit、DPM matrix が提示されていなかったため指摘できなかった。

## 前回15件への対応状況

前回原文がないため、以下は (A) から復元した対応表。

| # | 復元した前回指摘 | 判定 | 理由 |
|---|---|---|---|
| 1 | 公開 artifact URL / commit がない | **部分的** | push 準備済みだが、現案は placeholder のまま。投稿前置換を条件として閉じられる。 |
| 2 | target-ID が代表点のみ | **解決** | 全58ターゲットへの拡張で測定範囲は解決。ただし両 clang の完全ログ公開が必要。 |
| 3 | compiler の結果を driver 受理と表現している | **解決** | device-only compile と clang target-ID table に限定された。 |
| 4 | xnack のハードウェア／アーキテクチャ断定 | **解決** | hardware か toolchain table か不明と明記された。 |
| 5 | warning を `-Werror` 化できないという誤認 | **解決** | `-Werror` と `-Werror=option-ignored` の rc=1 を測定し、提案を撤回した。 |
| 6 | stack OOB probe が実際に scratch OOB か未確認 | **解決** | 無効な probe と認めて削除し、ISA上 store が残る heap OOB に変更した。 |
| 7 | `.co` byte-identical の根拠不足 | **解決** | `.text` のみ byte-for-byte identical に訂正し、39 bytes の非 `.text` 差分を開示した。 |
| 8 | PC sampling で workload が固定されていない | **解決** | 同一 binary・400反復で interval のみ変更した。 |
| 9 | 大 interval の zero output を実行時間だけで説明している | **部分的** | 外挿は改善。ただし仕様上の保証なしに `silent failure` と断定している。 |
| 10 | stochastic の positive control がない | **解決** | CDNA positive control がないことを明示し、gfx1201上の広告・拒否だけに限定した。 |
| 11 | GL2C の baseline とサイズ sweep がない | **解決** | null=0、16〜256 MiB の exact fit が追加された。 |
| 12 | write counter 側の解析がない | **部分的** | sweep と一定差は解決。dirty write-back L2 への帰属は未確定。 |
| 13 | split counter を「常に0」と断定 | **未解決** | 0でない測定は反映したが、「外来だけ」「kernel自身は数えない」という別の全称・因果断定に置き換わっている。 |
| 14 | DPM 対照が不安定、readback・profile control・反復不足 | **解決** | readback、n=3、`profile_standard` / `profile_peak` が追加され、相関に限定された。`un-pinned` の語だけ要修正。 |
| 15 | `always` / `no way` / `long-standing` / 新規 issue 等の過剰なスコープ | **部分的** | 多くは適切に限定されたが、split、PC silent failure、§4 の failure 扱いに過剰断定が残る。投稿先を1コメントに限定した点は解決。 |

## 個別指摘

### [NO-GO] 各表がログ名を示すという記述が事実と一致しない

冒頭は次のように保証している。

> Every table below names the log it comes from.

しかし投稿案中の表にはログファイル名が付いていない。各見出しまたは table caption に、例えば `(log: logs/p3r2_dpm_matrix_n3.log)` のように記載する必要がある。

### [NO-GO] split counter の発生源を特定できていない

次の断定は測定からは出ない。

> they register only the stray non-kernel traffic  
> and never the kernel's own EA requests

他 compute client の停止と KFD process 0 は、display、blit、firmware、counter collection 自体、測定窓のずれなどを排除しない。一方で、nonzero split が kernel request 由来でないことも証明していない。

置換例:

> In these runs, non-zero split counts appeared only in runs where the base counter was also above the clean `bytes/256 + 2` fit. I cannot identify the source of those extra events. All clean 256 MiB stream runs had zero split counts. This is consistent with, but does not prove, the hypothesis that the kernel's requests use a size not represented by the 32/64/128 B buckets.

### [NO-GO] write deficit の dirty-L2 帰属は推論

次は因果を確定しすぎている。

> That is the expected signature of dirty lines still resident in a write-back L2

測定で確定したのは、実際には次の式である。

```text
WRREQ = bytes / 256 - 24,576
```

read fit `bytes/256 + 2` との差は24,578 requests。24,576 requests × 256 B は正確に6 MiBだが、それが dirty L2 であることは flush control や perfmon event semantics なしには決まらない。

置換例:

> The write points fit `count = bytes/256 - 24,576`, i.e. a constant 6 MiB-equivalent deficit relative to `bytes/256`. Dirty data remaining in a write-back cache at the end of the measured dispatch is one possible explanation, but I did not measure cache residency or a post-dispatch flush.

### [NO-GO] PC sampling の `silent failure` は未確定

100,000からの外挿で約73件というのは有用だが、以下は未確認である。

- 最低出力件数や buffer flush threshold
- 最初の sample までの挙動
- zero-sample run で出力ファイルを作る契約
- interval が実際に厳密な周期を意味するか

したがって、「予想外の rc=0/no file」は言えるが、「failure」はまだ言えない。

置換例:

> At 1,000,000 and 10,000,000, rocprofv3 returned rc=0 and created no output file. A simple inverse-interval extrapolation from 100,000 predicts roughly 73 samples at 1,000,000, but I have not established whether rocprofv3 has a minimum-sample or output-flush threshold, so I cannot distinguish such a threshold from a profiler defect.

### [NO-GO] §4 は仕様違反でないものまで failure としている

- non-`profile_*` で hardware counter が0になること
- `--list-avail` にない counter 名が出力されないこと
- 大 interval で出力がないこと

これらは現状では「観測された落とし穴」であり、すべてを failure とする根拠はない。§4は削除するか、`Reproduction pitfalls` に変更するべき。

### [MINOR] split 比率の分子が一部だけ

`193 / 1,050,439 = 0.018%` は128B bucketだけを使っている。同じ run の全 split は205なので、全体なら約0.0195%。主張に不要なら比率を削除した方がよい。

### [MINOR] `un-pinned levels` は不正確

`low` と `high` も明示的に設定した performance level である。`non-profile levels` とする。

### [MINOR] `.co` 差分の内容を推測しない

> build-id and similar

section mappingで確認済みでなければ、`all outside .text, in note/metadata sections` までにする。

### [MINOR] corrected expression はまだ候補に留める

`GL2C_EA_RDREQ_sum * 256` は clean stream の傾きには合うが、`+2` intercept と contaminated run の扱いが未確定である。

> a candidate replacement expression may be possible if the event semantics and the +2 intercept are confirmed

程度が妥当。

## 最終判定

**[NO-GO]**

上記GO条件をすべて反映し、公開 URL と commitを確定した後は、追加実験なしで **条件付きGO** にできる。最終成果物は指定どおり **ROCm/ROCm#6613 への1件のコメント投稿のみ**とする。
