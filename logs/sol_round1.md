判定: **[NO-GO] 現案のまま投稿不可。**

## 先に必要な情報・証跡

GO 判定には、以下を1か所の固定 URL（既存リポジトリの commit、添付 archive など。新規 issue/PR は不要）で参照可能にする必要がある。

1. **全測定の完全な証跡**
   - `probes/`、全スクリプト、全ソース、全生ログ
   - 実行コマンド、stdout/stderr、終了コード、環境変数
   - 生成した code object、逆アセンブル、SHA-256
   - rocprofv3 の CSV/JSON と完全な `--list-avail`
2. **測定ごとの実行環境対応表**
   - 各表・各ログを、ホスト／コンテナ A／B のどれで取得したか
   - container image の digest
   - ROCm、rocprofv3、clang、HIP/HSA runtime、amdgpu/kernel/firmware の正確な版
   - `7.14.0~pre3` を使った箇所と、正式な `7.14.0` との区別
   - 7.14 コンテナで追加した symlink を含む全変更
3. **ASAN**
   - 完全なコンパイルコマンドと compiler stderr
   - unbundled `.co` に対する `cmp`/SHA-256。逆アセンブルだけの一致なら、その旨
   - OOB store が最適化で消えていないことを示す ISA
   - `-Werror` および診断グループ表示付きでの実測結果
4. **PC sampling**
   - 使用した rocprofv3 の版、完全なコマンド、カーネル実行時間
   - 期待 dispatch 数と、interval により取得 dispatch 数が 181/95/10 と変わった理由
   - interval 1,000,000 を「失敗」と呼ぶなら、その interval が複数回発火する長さの固定 workload での再測定
5. **GL2C**
   - カーネルソース、ISA、launch geometry、実際に検証した read/write byte 数
   - profiler が対象 dispatch だけを計測したこと
   - no-op/zero-traffic baseline
   - 複数サイズでの sweep と十分な反復
   - DPM 設定の変更前後の readback
   - `auto` で `SQ_WAVES` が 524,288 と 588,761 に割れた原因
   - 「256 MiB write」に対する `WRREQ=1,024,000` の解析値との対応

以下の指摘は、ログ未提示部分を推測したものではなく、(A)/(B) 内の直接の矛盾・過剰主張に限定する。

## 指摘

### [NO-GO] 最終投稿方針に違反している

> say the word and I will [open separate issues]

は、「ROCm/ROCm#6613 への1件のコメントのみ。新規 issue/PR は立てない」と正面から矛盾する。完全に削除すること。3件とも #6613 の1コメント内で報告し、別 ticket の提案もしない。

### [NO-GO] 「commands and raw logs」が本文から参照できない

冒頭で

> with the commands and raw logs

と断定しているが、投稿案にはログへの URL がなく、再現コマンドも省かれている。ローカルパス `logs/...` は相手から参照できない。固定 URL と commit/hash を明記する必要がある。

### [NO-GO] 7.14 の版表記が不正確

(A) は `amdrocm-core7.14-gfx1201 7.14.0~pre3` なのに、(B) は一貫して正式版のように **ROCm 7.14.0** と書いている。少なくとも該当測定は「7.14.0~pre3 snapshot」と表記し、container digest と commit を付けること。

また、7.14 コンテナでは aqlprofile symlink を手作業で追加している。結果に必要な環境変更なので、再現情報から落としてはいけない。

### [NO-GO] コンパイラの target-ID 判定を「driver accepts」と呼んでいる

見出しの

> Which target IDs the driver accepts

は誤り。device-only compile の診断なので、確認しているのは **clang/toolchain の target-ID acceptance** であり、GPU driver の受理ではない。

同様に、両 polarity が compiler に拒否されたことだけから、

> xnack is not in the gfx12 feature set at all

とアーキテクチャ仕様まで断定できない。言えるのは「この2 toolchain は、試した gfx12 target ID に xnack modifier を受理しない」まで。アーキテクチャ上の不存在を維持するなら、gfx12 ISA/perfmon 仕様などの一次資料が必要。

### [NO-GO] 「every RDNA part from gfx1030 on」は未測定範囲を含む

表で試したのは gfx1030、gfx1100、gfx1101、gfx1200、gfx1201 等に限られる。「gfx1030 以降の全 RDNA part」は表から導けない。

この主張を維持するなら、使用 clang が列挙する RDNA target を取得し、gfx1030 以降の**全 target ID**について同じ matrix を実行すること。有限の代表点しか測らない場合は、対象を「tested gfx1030/gfx11/gfx12 targets」に限定せざるを得ない。これは文面を弱めるためではなく、全称命題を有限の未網羅測定から証明できないため。

### [NO-GO] ASAN を「silent」と呼ぶのは記載事実と矛盾する

コンパイラは明示的に

> warning: ignoring '-fsanitize=address'

を出している。したがって、

> silently produces nothing

は不正確。「warning-only no-op that exits 0」なら測定と整合する。

また、

> nobody notices

は人間・CI の挙動についての未測定な推測。「warning を error に昇格しない CI では、未計装のまま成功扱いになり得る」と事実ベースにすること。

### [NO-GO] code object の「byte-identical」が未確定

(A) は「デバイス ISA の `diff` 一致」、(B) は

> the two device images are byte-identical

と、より強い主張になっている。unbundled `.co` 自体を `cmp` し SHA-256 が一致したのか、逆アセンブルテキストだけが一致したのかを確定すること。後者なら “identical instruction streams” と書くべきで、binary-identical とは書けない。

OOB probe についても、store が最適化で消えていないことを ISA で示す必要がある。

### [NO-GO] warning の改善提案が未検証

> make the existing warning `-Werror`-able by default

は意味が曖昧で、現状の `-Werror` で既に失敗する可能性がある。次を実測してから提案すること。

- `-Werror`
- `-fdiagnostics-show-option`
- 専用 warning group が表示される場合は `-Werror=<group>`

その結果に基づき、「既に global `-Werror` で止まる」「専用診断グループがない」「hard error を要望する」のどれかに整理する。

### [NO-GO] PC sampling の interval 1,000,000 は、現状では failure と立証できない

短い workload で sampling interval が実行時間を超えれば、サンプルが0件でも異常とは限らない。`rc=0`、出力なしだけでは silent failure と断定できない。

この記述を残すなら、単一の固定 workload を十分長く走らせ、interval が複数回発火する条件で再測定すること。また、

> same binary, same run

は interval ごとに別実行なら誤りなので、“same binary and workload” に直す。

stochastic の本体については、「gfx1201 の当該 rocprofv3 が広告せず、試した設定を拒否した」という範囲なら整合している。ただし PC sampling が 7.14 だけの測定なら明記すること。

### [NO-GO] GL2C の 256 B 計算が実測値と矛盾している

実測値は `GL2C_EA_RDREQ_sum = 1,048,578` なのに、

> 268,435,456 B / 1,048,576 = 256 B  
> 2^20 requests on the nose

では、分母を実測値から2減らしている。これは「実測から256 B/request」とは言えない。

`WRREQ` 側にも 2 request 相当の baseline を示唆する値があるが、現時点では推測できない。no-op baseline と複数 traffic size を測り、`count = bytes / N + intercept` の傾きと切片を出すこと。256 B 仮説を残すなら、その回帰結果または一次仕様が必要。

### [NO-GO] DPM と perfmon clock の因果を証明していない

変更したのは `power_dpm_force_performance_level` であり、perfmon clock 自体を直接観測していない。したがって、

> Everything that is a perfmon-clock artifact moves when you pin the clock

は因果の飛躍。現状から言えるのは「選択した base counters は `profile_standard` でのみ非ゼロになった」という相関まで。

さらに、周波数で変わるはずのない `SQ_WAVES` が `auto` の2回で 524,288 / 588,761 に割れている。この不安定性を解消するまで、「DPM だけを変えた厳密な対照」とは扱えない。

### [NO-GO] 「split is the only thing broken」は証明されていない

示されているのは、選択した read/write workload で base が非ゼロ、size-split が0だったことだけ。次はまだ証明されていない。

- workload が実際に 32/64/128 B の EA request を生成した
- split event がそれを数える仕様である
- 他の counter plumbing がすべて正常である
- split が全条件で常に0になる

32 B stride は、EA に32 B request が到達することの証明にはならない。主張を維持するなら、gfx12 perfmon 仕様に基づき 32/64/128 B request を生成する lane-mask、幅、alignment、stride の microbench を作り、ISA と event 結果を示す必要がある。

仕様が入手できない場合、有限の測定から “only broken” や “can ever match” は証明できないため、「tested workloads では0」に限定する必要がある。

### [NO-GO] write 側の数値整合が示されていない

「256 MiB float4 write」に対し `EA_WRREQ_sum = 1,024,000` だが、この値が期待値とどう対応するか説明されていない。read 側だけ解析値を提示し、write 側を「方向を正しく追う証明」に使うのは不十分。

launch geometry、実書込み byte 数、checksum、baseline、期待 request 数を提示すること。

### [NO-GO] `FETCH_SIZE` に関する全称主張が過剰

以下は現状の測定範囲を超えている。

- `gfx1201では常に0`
- `There is currently no way`
- `the only memory-traffic size metrics`
- `GL2C_EA_RDREQ_sum ... does track it`

完全な `--list-avail` と derived metric 定義を公開し、列挙された全 byte-size metric を同一 workload で試す必要がある。それでも証明できるのは「当該バージョンが列挙する built-in byte-size metrics の範囲」。

また `EA_RDREQ_sum` が追うのは request 数であり、byte 数ではない。request granularity が確定する前に「bytes を追う」とは書けない。

### [NO-GO] 「Long-standing」は first-bad を特定していない

7.2.4 と 7.14 snapshot の双方で再現したことから言えるのは、

> reproduced in both 7.2.4 and 7.14.0~pre3; not introduced after 7.2.4

まで。「long-standing」は発生開始時期を調べていないため削除する。

### [MINOR] 相手への表現が強すぎる

以下は協力的な相手へのコメントとして不要に断定的・挑発的。

- “cheap mitigation”
- “nobody notices”
- “confirm or kill this in a minute”
- “the split is the only thing broken”

工数を推測せず、測定・仮説・依頼を分離すること。たとえば “Could you confirm from the gfx12 perfmon specification whether…” で十分。

### [MINOR] 再現コマンドの環境依存性

`card*`、固定 group ID `44/992`、ローカル絶対パスはそのままでは移植できない。実際に使用した DRM card と group 名を記録し、再現例では環境に応じて置換が必要と明記する。

## GO の必要十分条件

次の全項目を満たせば GO。次ラウンドで別の新規条件は追加しない。

1. **#6613 への1コメントだけ**にし、新規 issue/PR を申し出る文を削除する。
2. ソース・コマンド・生ログ・生成物を固定 URL と hash 付きで公開し、本文の各表から対応証跡を追えるようにする。
3. 7.14 を `7.14.0~pre3` と正確に表記し、測定ごとの host/container、image digest、symlink 変更を明示する。
4. ASAN について、compiler と driver を区別し、全 RDNA 主張を維持するなら clang が列挙する対象を全件測る。
5. `.co` の binary equality、OOB store の残存、warning の `-Werror` 挙動を実測し、結果どおりに記述する。
6. “silent” を warning-only と区別し、CI や利用者の行動を未測定で断定しない。
7. PC sampling は使用版を明示し、固定 workload で control を取り直す。interval 1,000,000 の記述を残すなら十分長い実行で再現する。
8. GL2C は baseline、複数 byte size、複数反復、対象 dispatch の分離、DPM readbackを追加し、`SQ_WAVES` の不一致と write count を解消する。
9. 256 B/request は実測値を勝手に2減らさず、baseline 差分と size sweep の傾き、または一次仕様で裏付ける。
10. split counter の故障を主張するなら、32/64/128 B EA request を生成した証拠または gfx12 perfmon 仕様を付ける。
11. `always`、`only broken`、`no way`、`every RDNA part`、`long-standing` は、網羅測定または一次資料がない限り使用しない。
12. 事実・観測・仮説・改善依頼を明示的に分離し、The-Monk の既存判断を断定的に代弁しない。

全称命題については、有限の追加測定だけでは原理的に証明できない場合がある。その場合に scope を実測範囲へ限定するのは「文面を弱める」のではなく、論理上必須の修正である。
