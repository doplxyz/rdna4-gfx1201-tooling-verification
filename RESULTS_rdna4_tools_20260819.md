# RDNA4 検証ツール3件の gfx1201 実機追試

日付: 2026-08-19 / 実施: doplxyz / GPU: **AMD Radeon RX 9070 XT (gfx1201)**
発端: CK#3759 で著者 The-Monk が挙げた「RDNA4 で欠けている検証ツール3件」の追試約束。
出す先: **ROCm/ROCm#6613 へのコメント**（新規 issue は立てない。相手の issue に乗せる）

## 0. 環境

| | ホスト | コンテナ A | コンテナ B |
|---|---|---|---|
| ROCm | 7.14.0 (`amdrocm-core7.14-gfx1201` 7.14.0~pre3) | 7.14.0 (wheel SDK) | 7.2.4 |
| clang | 23.0.0git (46fcb339fb) | 同左 | 22.0.0git (roc-7.2.4) |
| rocprofv3 | 1.3.2 (2b22ab019) | 1.3.2 | **1.1.0** (97f5574fe) |
| イメージ | — | `rocm/pytorch:rocm7.14_ubuntu24.04_py3.12_pytorch_release_2.12.0` | `rocm/pytorch:rocm7.2.4_..._2.9.1` |

カーネル 6.14.0-37-generic / `ppfeaturemask=0xfff7ffff`（bit19 = PP_GFXOFF_MASK クリア済み）。
計測中は ComfyUI・llama-server・fah-client を停止し、`rocm-smi` で **KFD プロセス 0** を確認済み
（`logs/gpu_free_confirmed.log`）。

ソースは `probes/`、生ログは `logs/`。

---

## 1. device ASAN — 主張は正しい。しかも RDNA4 固有ではない

### 1.1 target-ID 受理マトリクス（`logs/p1_matrix_host714.log`, `p1_matrix_724.log`）

`-fsanitize=address -fgpu-sanitize` つきで device-only コンパイル。**7.14/clang23 と 7.2.4/clang22 で結果は完全に一致。**

| offload-arch | rc | 診断 |
|---|---|---|
| gfx90a:xnack+ / gfx908:xnack+ / gfx942:xnack+ / gfx950:xnack+ | 0 | (なし=受理) |
| **gfx1010:xnack+** | **0** | (なし=受理) |
| gfx1030:xnack+ / gfx1100:xnack+ / gfx1101:xnack+ | 1 | `invalid target ID` |
| gfx1200:xnack+ / **gfx1201:xnack+** / gfx1201:xnack- / gfx12-generic:xnack+ | 1 | `invalid target ID` |
| gfx90a / gfx942 / gfx1100 / gfx1201（xnack 無し） | 0 | `warning: ignoring '-fsanitize=address' ... Use it with an offload arch containing 'xnack+' instead` |

**gfx1010 は受理される。gfx1030 以降の RDNA は全部拒否。**
つまりこれは RDNA4 の欠落というより **GFX10.3 以降の RDNA 全世代**の話。
`gfx1201:xnack-` すら拒否されるので、xnack は gfx12 の feature 集合に存在しない。

### 1.2 「付けても黙る」ところまで（`logs/p1_asan_run_714.log`）

CK#3759 バグ1と同型の device 側 OOB（2要素配列の外へ書く）と、hipMalloc の 4 バイト先へ書くカーネル。

| ビルド | stack OOB | heap OOB |
|---|---|---|
| sanitizer 無し | rc=0、エラー無し、黙って通る | rc=0、エラー無し |
| `-fsanitize=address -fgpu-sanitize` | rc=0、**同一出力。報告なし** | rc=0、**報告なし** |
| 同上 + `HSA_XNACK=1` | rc=0、**報告なし** | rc=0、**報告なし** |

### 1.3 決定的証拠 — デバイスイメージが素通し（`logs/p1_devimg_compare.log`）

実行ファイルから `.hip_fatbin` を抜き、`clang-offload-bundler --unbundle` で
デバイスコードオブジェクトだけを取り出して比較した。

| ターゲット | ビルド | .co サイズ | `asan` シンボル | 命令数 |
|---|---|---|---|---|
| **gfx942:xnack+**（対照） | 素 | 6,032 B | 0 | — |
| **gfx942:xnack+**（対照） | ASAN | **54,280 B** | **76** | — |
| gfx1201 | 素 | 5,456 B | 0 | 176 |
| gfx1201 | ASAN | **5,456 B** | **0** | **176** |

**gfx1201 では素のビルドと ASAN ビルドのデバイス ISA が完全一致**（`diff` 一致、命令数 176）。
同じコンパイラ・同じソースで gfx942:xnack+ は 9 倍に膨れ計装が入る。
→ **RDNA4 で `-fgpu-sanitize` は「効かない」のではなく「何も生成しない」。**
警告は出るがビルドは成功するので、CI で気づかず素通りする。

### 1.4 ランタイム側

- `rocminfo` の agent ISA は `amdgcn-amd-amdhsa--gfx1201`（**xnack サフィックス自体が無い**）。
  gfx9 なら `:xnack-` が付く。`XNACK enabled: NO`。
- KFD topology node の `gfx_target_version=120001`。
- `HSA_XNACK=1` は挙動を一切変えない（上表）。

---

## 2. stochastic PC sampling — 主張は正しい（host_trap のみ）

### 2.1 エージェントが広告する設定（`logs/p2_pcs_714.log`）

```
GPU: 0  Name: gfx1201
configs:
   Method: host_trap   Unit: time   Min_Interval: 512   Max_Interval: 18446744073709551615
```
**host_trap の1件だけ。stochastic は列挙されない。**

### 2.2 実行（`logs/p2_pcs_stochastic_sweep.log`）

`--pc-sampling-method stochastic` を **unit × interval の 12 通り**（time/cycles/instructions ×
512/1000/32/65504）で実行 → **12/12 すべて rc=1**、
`Given PC sampling configuration is not supported on any of the agents`。

### 2.3 対照 — host_trap は同じバイナリで実際にサンプルを採る（`logs/p2_pcs_control.log`）

| interval (unit=time) | rc | サンプル数 | 異なる命令 | dispatch 数 |
|---|---|---|---|---|
| 512 | 0 | **21,601** | 24 | 181 |
| 1000 | 0 | 11,252 | 23 | 95 |
| 10000 | 0 | 1,091 | 15 | 10 |
| 1000000 | 0 | **出力ファイルが作られない（無言）** | — | — |

最頻サンプルは `v_add_f32_e32 v0, v0, v2`（20,750/21,601）でカーネル本体と一致。
→ ハーネスは正しい。**stochastic だけが落ちている。**

補足（副次的な引っかかり）: interval が大きすぎると **rc=0 のまま何も出力されない**。
最初この設定で測って「host_trap も動かない」と誤読しかけた。

**開示**: CDNA 実機を持っていないので「gfx9 では stochastic が動く」側の対照は取れていない。

---

## 3. GL2C EA size-split カウンタ — 主張は正しい。**そして原因の切り分けまで取れた**

### 3.1 まず前提: `power_dpm_force_performance_level` を変えないと何も測れない

256 MiB を float4 で読むだけのカーネル（解析値 268,435,456 B）。**同一コマンドで DPM レベルだけを振った**
（`logs/p3_dpm_matrix.log`、各2回）。

| DPM level | SQ_WAVES | SQ_INSTS_VALU | GL2C_EA_RDREQ_sum | 32B/64B/128B_sum | FETCH_SIZE |
|---|---|---|---|---|---|
| `auto`（既定） | 524,288 / 588,761 | **0** | **0** | 0 | 0 |
| `high` | 524,288 | **0** | **0** | 0 | 0 |
| `low` | 524,348 / 524,288 | **0** | **0** | 0 | 0 |
| **`profile_standard`** | **524,288**（解析値と一致、2回とも） | **5,242,880** | **1,048,578** | **0** | **0** |

- `profile_standard` **以外では SQ_WAVES 以外のすべてが 0** を返す。`high` でも駄目。
- `profile_standard` のときだけ 2 回の再実行がビット一致し、SQ_WAVES が解析値
  16,777,216 lanes / 32 = **524,288** と厳密に一致する。
- **つまり「カウンタが 0」の大半は perfmon clock の問題で、`profile_standard` で消える。**
  これは The-Monk の「perfmon clock ではない」という主張を否定するものではなく、**支持する**。
  clock 起因のゼロは条件を変えれば消えるのに、**size-split だけはどの条件でも 0 のまま**だからである。

### 3.2 profile_standard 固定でのアクセスパターン別（`logs/p3_gl2c_modes.log`）

| カーネル | GL2C_EA_RDREQ_sum | RDREQ 32B/64B/128B | GL2C_EA_WRREQ_sum | WRREQ_64B |
|---|---|---|---|---|
| 256 MiB 連続 float4 READ | **1,048,578** | **0 / 0 / 0** | 0 | 0 |
| 256 MiB 連続 float READ | 1,048,578 | 0 / 0 / 0 | — | — |
| 32 B ストライド READ | 1,048,578 | 0 / 0 / 0 | — | — |
| 256 MiB 連続 float4 WRITE | 2 | 0 / 0 / 0 | **1,024,000** | **0** |

- base は**方向を正しく追う**（読みカーネルで RDREQ が立ち WRREQ=0、書きカーネルでその逆）。
  base カウンタが生きていることの証明。
- **size-split は読み・書きとも、全パターンで 0。**

### 3.3 内部整合 — 数が合う

`GL2C_MISS_sum = 1,048,578` が `GL2C_EA_RDREQ_sum = 1,048,578` と**完全一致**（7.14 実測）。
268,435,456 B ÷ 1,048,576 = **256 B / EA リクエスト**（ちょうど 2^20 リクエスト）。

→ **仮説（実測ではない）**: gfx12 の EA リクエスト粒度は 256 B で、
`GL2C_EA_RDREQ_{32,64,128}B` が数えようとしている 3 つの箱のどれにも入らない。
そうであれば size-split がゼロなのは配線ミスではなく**カウンタ定義が gfx12 に合っていない**ことになる。
32B/64B/128B 以外のサイズ別カウンタは gfx1201 のカウンタ表に存在しない
（`GL2C_EA_RDREQ{,_32B,_64B,_128B}{,_sum}` と `GL2C_EA_WRREQ{,_64B,_STALL}{,_sum}` が全部）。

### 3.4 ユーザーに見える害 — `FETCH_SIZE` が構造的に 0 KB

`--list-avail` の定義（`logs/listavail_724.txt:265`）:
```
FETCH_SIZE = (GL2C_EA_RDREQ_32B_sum*32 + GL2C_EA_RDREQ_64B_sum*64 + GL2C_EA_RDREQ_128B_sum*128)/1024
```
式が壊れた 3 カウンタ**だけ**で出来ている。よって **gfx1201 では FETCH_SIZE / FetchSize は常に 0 KB**。
実際に 256 MiB 読んだ実行で 0 KB を報告する。
しかも gfx1201 のカウンタ表にある**メモリ転送量メトリクスはこの 2 つだけ**（`WRITE_SIZE` は未定義）。
→ **RDNA4 では rocprofv3 から「このカーネルが何バイト読んだか」を得る手段が無い。**

### 3.5 版差 — 無い（回帰ではない）

| | ROCm 7.2.4 / rocprofv3 1.1.0 | ROCm 7.14 / rocprofv3 1.3.2 |
|---|---|---|
| GL2C_EA_RDREQ_sum | 1,048,578 | 1,048,578 |
| 32B / 64B / 128B_sum | 0 / 0 / 0 | 0 / 0 / 0 |
| FETCH_SIZE | 0 | 0 |
| SQ_INSTS_VALU | 5,242,880 | 5,242,880 |

**2 つの ROCm 版・2 つの rocprofv3 版で同一。**最近の退行ではない。

---

## 4. 副次的に見つけた罠（上流の話ではなく、環境側）

- **`rocm/pytorch:rocm7.14_*` イメージでは rocprofv3 のカウンタ収集が
  `aqlprofile API table load failed` で SIGABRT する。**原因は wheel レイアウトに
  `libhsa-amd-aqlprofile64.so`（バージョン無しの symlink）が無いこと。
  `ln -sf libhsa-amd-aqlprofile64.so.1 libhsa-amd-aqlprofile64.so` で解決。
  同じ罠が `libamdhip64.so` にもあり、HIP のリンクが失敗する。
  → **これを「7.14 ではカウンタが壊れている」と報告しなくて良かった。**
- ホスト側の split install（`/usr/bin/rocprofv3` + `/opt/rocm`）では、カウンタ収集も
  PC sampling も `ring_buffer.cpp:106 mmap failed with errno 22` で abort し、
  **被計測プロセスが永久にハングして SIGKILL が要る**。コンテナ経由なら起きない。
  上流に出すには材料が足りないので**今回は報告しない**（環境固有の疑いが濃い）。
- rocprofv3 の silent failure が 3 種類あった: ①interval 過大で無言・出力なし
  ②未対応カウンタ名を無言で落とす（`SQ_INSTS_VMEM` `GL2C_REQ_sum` は出力に現れない）
  ③DPM が profile_standard 以外だと無言で 0。**どれもエラーを出さない。**

## 5. 再現手順

```bash
cd /mnt/monooki/comfy_rocm724/rdna4_tools
# ビルド（7.14 / 7.2.4 どちらでも）
docker run --rm -v $PWD:/w -w /w rocm/pytorch:rocm7.2.4_ubuntu24.04_py3.12_pytorch_release_2.9.1 \
  bash -c './build.sh rocm724 /opt/rocm/llvm/bin/amdclang++ "-Wno-unused-value"'
./matrix.sh amdclang++                       # §1.1 target-ID マトリクス
# GPU を空けてから:
echo profile_standard | sudo tee /sys/class/drm/card*/device/power_dpm_force_performance_level
docker run --rm --device=/dev/kfd --device=/dev/dri --group-add 44 --group-add 992 \
  -v $PWD:/w -w /w rocm/pytorch:rocm7.2.4_ubuntu24.04_py3.12_pytorch_release_2.9.1 \
  bash -c './gl2c_sweep.sh /w/bin/rocm724/traffic /w/logs/x'
echo auto | sudo tee /sys/class/drm/card*/device/power_dpm_force_performance_level
```

---

# ラウンド2 — sol/high の NO-GO を受けた再測定 (2026-08-19)

sol は 15 件の NO-GO を返した（`logs/sol_round1.md`）。**うち 2 件はこちらの測定が実際に誤っていた。**
以下は測り直しの結果。文面を弱めた箇所は「有限測定から全称命題を出せない」ものだけ。

## R2-1 target-ID: 代表点 → **全 58 ターゲット網羅**（`logs/p1_matrix_full_714.log`）

`amdclang++ -target amdgcn-amd-amdhsa -mcpu=help` が列挙する全ターゲットで実施。
`:xnack+` 受理は gfx801/gfx810/全 gfx9xx/gfx9(-4)-generic と **gfx1010–1013 + gfx10-1-generic のみ**。
gfx1030–1036, gfx10-3-generic, 全 gfx11, 全 gfx12 (gfx1250/1251/1310 含む) は全部 `invalid target ID`。
→「gfx1030 以降の RDNA は全部」は**代表点ではなく網羅測定になった**。

## R2-2 「driver が受理」→「toolchain が受理」

device-only コンパイルの診断なので、見ているのは clang の target-ID テーブル。文面を修正。
「xnack は gfx12 の feature set に存在しない」もアーキ断定なので落とし、
「この2つの toolchain はどの gfx10.3+ ターゲットでも xnack modifier を受理しない」に限定。

## R2-3 `-Werror` は**既に効く**（`logs/p1_werror.log`）

| flags | rc | 診断 |
|---|---|---|
| (なし) | 0 | warning |
| `-Werror` | **1** | **error** |
| `-Werror=option-ignored` | **1** | **error** |

→ **「-Werror 可能にせよ」という提案は誤りだったので撤回。**既に named group にある。
残る事実は「既定が warning」だけ。

## R2-4 stack OOB プローブは**無効なテストだった**（`logs/oob_gfx1201.disasm`）

`oob_stack` の 2 要素配列はレジスタに畳まれ、scratch ストアが 1 本も出ていない。
→ **ASAN のテストケースとして成立しない。落とした。**
`oob_heap` は `global_store_b32 v[1:2], v0, off` が無条件に残っており有効。こちらだけ使う。

## R2-5 `.co` は byte-identical ではない（`logs/p1_co_bytediff.log`）

同サイズ 5,456 B、**差分は 39 バイト、範囲 [2488, 4417]、`.text` (offset 2816..3584) の外**。
`.text` は `a[.text]==b[.text]` で完全一致。逆アセンブルも diff クリーン、176 命令。
→ 「byte-identical」は誤り。**「`.text` が byte-for-byte 一致」**が正しい。

## R2-6 PC sampling: 固定ワークロードで取り直し（`logs/p3r2_batch_724.log` R2-E/F）

同一バイナリ・同一ワークロード（400 反復）で interval だけを振った:
512→129,532 / 1,000→71,160 / 10,000→7,727 / 100,000→731 /
**1,000,000→出力なし (rc=0)** / **10,000,000→出力なし (rc=0)**。
100,000 で 731 サンプル出ているので、1,000,000 なら外挿で ~73 サンプル出るはず。
→ **「実行時間より interval が長いから 0 件」では説明できない。**silent failure と言ってよい。
stochastic は同じ固定ワークロードでも rc=1。

## R2-7 GL2C: baseline + サイズ sweep で傾きと切片を出した

**null カーネル（同一 launch geometry・メモリ非アクセス）= 0。**
読み: 16/32/64/128/256 MiB → 65,538 / 131,074 / 262,146 / 524,290 / 1,048,578。
**count = bytes/256 + 2 に全点が厳密に乗る。**
→ 256 B/request は**回帰で実測**された（前回は 1,048,578 を勝手に 1,048,576 と読み替えていた。誤り）。

書き: 40,960 / 106,496 / 237,568 / 499,712 / 1,024,000 / 2,072,576。
差分は 65,536 / 131,072 / 262,144 / 524,288 / 1,048,576 で**同じ傾き**、
読み側 fit に対する不足は**全サイズで一定の 24,578 req ≈ 6 MiB**。
→ write-back L2 にダーティ行が残った分。**sol が要求した write 側の解析対応が付いた。**

## R2-8 split カウンタは「常に 0」ではない — **主張を訂正**

同一コマンド 8 回（7.2.4）: **7 回は 0/0/0 で base ちょうど 1,048,578**、
1 回だけ `128B=15` かつ **base も 1,110,127 に膨らんでいた**。
別の run では `128B=193, 32B=6, 64B=6` / base 1,050,439。7.14 では 8/8 が 0/0/0。
→ **split が拾うのは dispatch 窓に紛れ込んだ外来トラフィックだけで、カーネル自身の EA request は
一度も数えない。**（193 / 1,050,439 = 0.018%）
これは 256 B 粒度仮説と整合する（外来の小さいリクエストだけがバケツに入る）。

## R2-9 DPM: readback つき n=3、`profile_peak` を追加（`logs/p3r2_dpm_matrix_n3.log`）

`auto` / `high` / `low` → SQ_WAVES 以外すべて 0。
**`profile_standard` と `profile_peak` → 全部正常。**`high` では駄目。
SQ_WAVES のブレ（528,983 / 528,982）は `low` でのみ発生し、`profile_*` では 3/3 が 524,288 ちょうど。
→ sol が指摘した「対照が不安定」は**非 profile レベルに限局**すると確定。
因果の言い方は「相関」に落とした（perfmon clock 自体は観測していない）。

## R2-10 スコープを落とした主張（測っても決まらないもの）

- 「always 0」→「測った全ワークロードで、カーネル自身のリクエストは一度も数えられない」
- 「no way to get bytes」→「この rocprofv3 版が列挙する built-in メトリクスの範囲では無い」
- 「long-standing」→「7.2.4 と 7.14.0~pre3 の両方で再現。開始時期は調べていない」
- 「split is the only thing broken」→ 削除
- 新規 issue の申し出 → **削除**（#6613 の1コメントのみ）
