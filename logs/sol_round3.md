判定: **[NO-GO]**

### 投稿前の GO 条件（以下4件ですべて）

1. **[NO-GO] split counter の発生源について断定が残っている**
   §3.2 の以下は、§3.3 の「発生源を特定できない」「kernel 自身でないとも証明できない」と矛盾する。
   - `foreign traffic entered the dispatch window`
   - `contaminated run`
   - `contaminated denominator`

   すべて `outlier` / `excess-count run` 等の中立表現に変更し、「base が clean fit を超えたことだけが観測事実で、発生源は不明」と統一すること。

2. **[NO-GO] PC sampling の測定バージョンとログ名が不整合**
   §2 は `7.14.0~pre3 / rocprofv3 1.3.2 only` としている一方、表の出典が `p3r2_batch_724.log` になっている。ほかの箇所では `_724` と `_714` をそれぞれ ROCm 7.2.4 / 7.14 として使っているため、現状では測定 provenance を確定できない。

   実際のログ内容に基づき、次を一致させること。
   - `--list-avail` の取得バージョン
   - stochastic 12条件の実行バージョン
   - host_trap 表の実行バージョン
   - 引用ログ名

3. **[NO-GO] perfmon clock への因果帰属が、直前の留保を破っている**
   §3.1 で「perfmon clock を直接観測しておらず、測定したのは相関」と正しく限定した直後に、
   > the zeros that are clock-related move when a `profile_*` mode is selected

   と clock-related を断定している。観測から言えるのは、DPM モード変更に伴って `SQ_INSTS_VALU` と base counter の値が変化し、clean run の split counter は変化しなかったことまで。clock gating と別の mode-dependent collection path は区別できない、と統一すること。

4. **[NO-GO] 「各表にログファイル名」の条件を Environment 表だけ満たしていない**
   冒頭の Environment 表に出典ログがない。既存 commit 内の実ログを付記すること。新たに artifact を追加する場合は、repo の commit hash も更新すること。

### 非阻害だが修正推奨

- **[MINOR]** 冒頭の `raw ... rocprofv3 CSVs are at` は、PC sampling CSV 2本が先頭200行だけであることをコメント本文でも明記した方が正確。
- **[MINOR]** write deficit は、`bytes/256` に対する offset が 24,576 requests = 6 MiB、read fit `bytes/256+2` との差が24,578 requests、と分けて書くと混同がない。
- **[MINOR]** `GL2C EA size-split counters — confirmed, with the cause narrowed` は、非ゼロ例があり原因未確定なので、`FETCH_SIZE=0 reproduced; split-event semantics unresolved` 程度が本文と整合する。
- **[MINOR]** §4 の `every non-profile_* DPM level returning zeros` は `SQ_WAVES` が非ゼロなので、「対象の GL2C / SQ_INSTS counters が zero」と限定する。

上の **[NO-GO] 4件を修正すれば GO**。投稿先を `ROCm/ROCm#6613` の1コメントだけにする条件は満たしている。
