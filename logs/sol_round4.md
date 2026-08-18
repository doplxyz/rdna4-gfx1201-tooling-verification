[NO-GO] **現状は投稿不可。**

必須修正は1系統・2箇所のみ。前回の「excess-count / on-fit に統一」が完了していない。

1. §3.1  
   `the split counters on clean runs`  
   → `the split counters on on-fit runs`

2. §3.4  
   `the +2 intercept and the contaminated runs are understood`  
   → `the +2 intercept and the excess-count runs are understood`

特に `contaminated` は発生源が外部にあるとの含意を再導入しており、「発生源不明」という本文の結論を壊す。

[MINOR] §3.3 の `In the largest such run` は、base が最大なのは 1,110,127 の run なので曖昧。意図が split 合計最大なら、次にするとよい。

> In the run with the largest split-event total, the split events total ...

**GO条件は上記2箇所の必須置換のみ。** 置換後は、MINORを直さなくても ROCm/ROCm#6613 への1件のコメントとして投稿可。新規 issue / PR は不要。
