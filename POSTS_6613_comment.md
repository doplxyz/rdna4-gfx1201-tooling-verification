Second gfx1201 data point, from an RX 9070 XT — this is the follow-up I promised in
ROCm/composable_kernel#3759, where you asked whether any of the three had been made to work on a
9070 XT. Short answer: none of them, but two of the three turned out to have a sharper description
than "unsupported", and one of my first-pass conclusions was wrong and is corrected below.

Sources, scripts, raw logs, the extracted code objects and the rocprofv3 CSVs are at
**REPO_URL @ REPO_COMMIT**; each table names the log file it comes from. Where something is
inference rather than measurement I say so explicitly, and I have tried to keep the two separated
throughout.

**Environment.** RX 9070 XT (gfx1201), kernel 6.14.0-37-generic, `ppfeaturemask=0xfff7ffff`.
Two toolchains, because the version comparison matters:

| | A | B |
|---|---|---|
| ROCm | **7.14.0~pre3** (`amdrocm-core7.14-gfx1201 7.14.0~pre3-29052710811`) | 7.2.4 |
| clang | 23.0.0git (`46fcb339fb`) | 22.0.0git (`roc-7.2.4`) |
| rocprofv3 | 1.3.2 (`2b22ab0195`) | 1.1.0 (`97f5574fe2`) |
| image | `rocm/pytorch:rocm7.14_ubuntu24.04_py3.12_pytorch_release_2.12.0`<br>`sha256:c38eeda81d85f00fbe35d3d50ce42ce59c524e87d810624f4eb5c52fddb3b9ad` | `rocm/pytorch:rocm7.2.4_ubuntu24.04_py3.12_pytorch_release_2.9.1`<br>`sha256:7fe531fa185af260352fe7fbb3fa64ad749abe72adf0600a648c4692801b125a` |

Note it is a pre-release 7.14 snapshot, not a released 7.14.0. Two environment changes were needed
inside the 7.14 image and are part of the reproduction: the wheel layout ships
`libamdhip64.so.7` and `libhsa-amd-aqlprofile64.so.1` with no unversioned `.so` symlink, so HIP
linking fails and rocprofv3 counter collection aborts with `aqlprofile API table load failed`
until both symlinks are created. That is a packaging detail of that image, not a profiler bug —
I mention it only because without it I would have reported "counters are broken on 7.14", which
is false.

All GPU measurements were taken with every other compute client stopped and `rocm-smi` reporting
zero KFD processes.

## 1. Device ASAN — confirmed, and the boundary is not at RDNA4

### 1.1 Target IDs the *compiler* accepts

To be precise about what this measures: it is clang's target-ID acceptance in a device-only
compile, not anything the driver or runtime decides. I enumerated every AMDGPU target the
toolchain knows (`amdclang++ -target amdgcn-amd-amdhsa -mcpu=help`, 58 targets) and tried
`<target>:xnack+` with `-fsanitize=address -fgpu-sanitize` on each, on **both** toolchains. The
accepted set is identical on clang 23 and clang 22; the only difference is that five targets
(`gfx1170/1171/1172`, `gfx12-5-generic`, `gfx1310`) are unknown to clang 22 altogether, so they
fail there as unsupported architectures rather than as invalid target IDs.

(logs: `p1_matrix_full_714.log`, `p1_matrix_full_724.log`)

| group | `:xnack+` accepted? |
|---|---|
| `gfx801`, `gfx810`, all `gfx9xx`, `gfx9-generic`, `gfx9-4-generic` | **accepted** |
| `gfx1010`, `gfx1011`, `gfx1012`, `gfx1013`, `gfx10-1-generic` | **accepted** |
| `gfx1030`–`gfx1036`, `gfx10-3-generic` | rejected — `invalid target ID` |
| `gfx1100`–`gfx1103`, `gfx115x`, `gfx117x`, `gfx11-generic` | rejected |
| `gfx1200`, `gfx1201`, `gfx1250`, `gfx1251`, `gfx12-generic`, `gfx12-5-generic`, `gfx1310` | rejected |
| `gfx6xx`, `gfx7xx`, `gfx802/803/805` | rejected |

That is the complete enumeration, not a sample. The line is not RDNA4: **every RDNA target from
gfx1030 onward is rejected**, while gfx101x is accepted. `gfx1201:xnack-` is rejected too, so it
is not a polarity question — this toolchain accepts no xnack modifier on any gfx10.3+ target.
Whether that reflects the hardware or only the toolchain's target-ID table is something I cannot
determine from here; if it is architectural, the issue title may be worth widening beyond RDNA4.

Without an xnack modifier, every target — gfx942 included — emits
`warning: ignoring '-fsanitize=address' option for offload arch '…' as it is not currently
supported there`, exit code 0.

### 1.2 What the resulting binary actually does

**Correction to something I would have written otherwise.** My first probe used a write past a
2-element function-local array (bug 1's shape in #3759). Disassembling the device image shows the
compiler folded that array entirely into registers — no scratch traffic at all — so it is *not* a
valid ASAN test case and I dropped it. The test below is a heap overflow, and I verified in the
gfx1201 ISA that the store survives: `oob_heap` compiles to a single unconditional
`global_store_b32 v[1:2], v0, off`, executed by `n+1` threads over an `n`-int `hipMalloc`.

(logs: `p1_asan_run_714.log`; ISA in `oob_gfx1201.disasm`)

| build | result |
|---|---|
| no sanitizer | rc=0, no diagnostic, 4-byte overflow lands silently |
| `-fsanitize=address -fgpu-sanitize` | rc=0, **identical output, no report** |
| same + `HSA_XNACK=1` | rc=0, **no report** |

The mechanism, which is the part I think is worth acting on. I dumped `.hip_fatbin` from each
executable and unbundled the gfx1201 code object:

(logs: `p1_devimg_compare.log`, `p1_co_bytediff.log`)

| target | build | device `.co` | symbols matching `asan` | instructions |
|---|---|---|---|---|
| `gfx942:xnack+` (control) | plain | 6,032 B | 0 | — |
| `gfx942:xnack+` (control) | ASAN | **54,280 B** | **76** | — |
| `gfx1201` | plain | 5,456 B | 0 | 176 |
| `gfx1201` | ASAN | 5,456 B | **0** | 176 |

For gfx1201 the two `.co` files are the same size and **`.text` is byte-for-byte identical**
(they differ in 39 bytes total, at file offsets 2488–4417, all outside the `.text` range
2816–3584 given by the section headers; the disassembly diff is clean at 176 instructions each). The same compiler and source targeting
`gfx942:xnack+` produces a device image about 9x larger with instrumentation in it. So on gfx1201
`-fgpu-sanitize` is not a degraded mode; it emits the identical device code and exits 0.

On making that louder — **I was wrong about what is missing here.** I was going to suggest making
the warning `-Werror`-able; it already is. Measured: plain `-Werror` turns it into an error (rc=1),
and so does `-Werror=option-ignored` (log: `p1_werror.log`), so the diagnostic is in a named group and a project that
wants a hard failure can already get one today. What remains is only that the default is a warning,
so a sanitizer CI job that does not opt in gets a green, uninstrumented run. Whether that default
should change is a judgement call for you and the maintainers, not something I can measure.

Runtime side: `rocminfo` reports the agent ISA as `amdgcn-amd-amdhsa--gfx1201` with no xnack
suffix at all (gfx9 parts carry `:xnack-`), `XNACK enabled: NO`, and `HSA_XNACK=1` changes nothing
in any run above.

## 2. Stochastic PC sampling — confirmed

Measured on 7.14.0~pre3 / rocprofv3 1.3.2 only.

`rocprofv3 --list-avail` advertises exactly one config for this agent:
`Method: host_trap, Unit: time, Min_Interval: 512, Max_Interval: 18446744073709551615`.
`--pc-sampling-method stochastic` across 12 combinations (unit ∈ {time, cycles, instructions} ×
interval ∈ {32, 512, 1000, 65504}) fails **12/12** with rc=1,
`Given PC sampling configuration is not supported on any of the agents`.

Control, on **one fixed workload** (400 iterations of the same kernel, identical command line
except the interval):

(log: `p3r2_batch_724.log`, section R2-E)

| unit=time interval | rc | samples |
|---|---|---|
| 512 | 0 | 129,532 |
| 1,000 | 0 | 71,160 |
| 10,000 | 0 | 7,727 |
| 100,000 | 0 | 731 |
| 1,000,000 | 0 | **no output file** |
| 10,000,000 | 0 | **no output file** |

So host_trap works and scales as expected down to 100,000. The last two rows need stating
carefully: at 1,000,000 and 10,000,000, rocprofv3 returned rc=0 and created no output file at all.
A simple inverse-interval extrapolation from the 100,000 row predicts roughly 73 samples at
1,000,000. I have not established whether rocprofv3 has a minimum-sample count or an output-flush
threshold, so I cannot tell such a threshold apart from a defect — I can only report the
observation. Same stochastic result on the same fixed workload: rc=1, same message.

**Disclosure: I have no CDNA part, so I cannot show the positive control of stochastic sampling
working anywhere.** All I can say is that this agent does not advertise it and rejects every
configuration I tried.

## 3. GL2C EA size-split counters — confirmed, with the cause narrowed

This is the one where I have something to add beyond confirmation. Kernel: a 256 MiB `float4`
streaming read, byte count known from the source.

### 3.1 A prerequisite that is easy to trip over

Varying **only** `power_dpm_force_performance_level` (readback verified each time), n=3 per level:

(log: `p3r2_dpm_matrix_n3.log`; the level was read back from sysfs after each write)

| DPM level | SQ_WAVES | SQ_INSTS_VALU | GL2C_EA_RDREQ_sum | 128B_sum |
|---|---|---|---|---|
| `auto` (default) | 524,288 | **0** | **0** | 0 |
| `high` | 524,288 | **0** | **0** | 0 |
| `low` | 524,288 / 528,983 / 528,982 | **0** | **0** | 0 |
| **`profile_standard`** | 524,288 ×3 | 5,242,880 | 1,048,578 | 0 |
| **`profile_peak`** | 524,288 ×3 | 5,242,880 | 1,048,578 | 0 |

Only the `profile_*` modes produce anything but `SQ_WAVES`; `high` is not enough. Under those two
modes the numbers are exactly reproducible (5/5 repeats bit-identical at 256 MiB) and `SQ_WAVES`
matches the analytic 16,777,216 lanes / 32 = **524,288** exactly, while the small `SQ_WAVES` drift
appears only at the non-`profile_*` levels.

I want to be careful about the causal claim: I varied a DPM setting and did not observe the
perfmon clock directly, so what is measured is a correlation. But it does give your
"counter-plumbing, not the perfmon clock" reading a test rather than a judgement: the zeros that
are clock-related move when a `profile_*` mode is selected, and the size-split zeros do not move
under any of the five levels.

### 3.2 The base counters are correct — with a slope and an intercept

Read sweep, `profile_standard`, one dispatch each, plus a null kernel with the same launch
geometry and no memory access:

(logs: `p3r2_batch_724.log` R2-A, `p3r2b_724.log`, `p3r2b_714.log`)

| workload | GL2C_EA_RDREQ_sum | 32B / 64B / 128B | expected by `bytes/256 + 2` |
|---|---|---|---|
| null kernel, same launch geometry, 0 B | **0** | 0 / 0 / 0 | — |
| 16 MiB read | 65,538 | 0 / 0 / 0 | 65,538 |
| 32 MiB read | 131,074 | 0 / 0 / 0 | 131,074 |
| 64 MiB read | 262,146 | 0 / 0 / 0 | 262,146 |
| 128 MiB read | 524,290 | 0 / 0 / 0 | 524,290 |
| 256 MiB read | 1,048,578 | 0 / 0 / 0 | 1,048,578 |
| 256 MiB read (one contaminated run) | 1,050,439 | 6 / 6 / 193 | 1,048,578 |
| 512 MiB read (only run taken, contaminated) | 2,099,030 | 0 / 6 / 193 | 2,097,154 |

The zero-traffic baseline is exactly 0 and every clean point sits exactly on
**count = bytes / 256 + 2**. The two rows marked contaminated are the ones where foreign traffic
entered the dispatch window; see §3.3 — the excess over the fit and the non-zero split counters
appear together, which is the whole story of this section. The 16/64/256 MiB points reproduce
identically on both toolchains; the 256 MiB point is 1,048,578 in 5/5 dedicated repeats on 7.2.4
and 8/8 on 7.14.0~pre3. (In my first pass I divided 268,435,456 by 1,048,576 and called it "256 B
on the nose", which quietly dropped the intercept and used a contaminated denominator; the sweep
is the honest version of that claim.)

Write sweep, same method:

(log: `p3r2_batch_724.log` R2-B)

| workload | GL2C_EA_WRREQ_sum | 64B |
|---|---|---|
| 16 MiB write | 40,960 | 0 |
| 32 MiB write | 106,496 | 0 |
| 64 MiB write | 237,568 | 0 |
| 128 MiB write | 499,712 | 0 |
| 256 MiB write | 1,024,000 | 0 |
| 512 MiB write | 2,072,576 | 0 |

Successive differences are exactly 65,536 / 131,072 / 262,144 / 524,288 / 1,048,576 — the same
1 request per 256 B slope. The points fit `count = bytes/256 - 24,576` exactly — a constant
deficit of 24,578 requests against the read-side fit, identical at every size from 16 MiB to
512 MiB, and 24,576 x 256 B is exactly 6 MiB. Data still resident in a write-back cache at the end
of the measured dispatch is one explanation that fits, but I did not measure cache residency and
did not test a post-dispatch flush, so I am not claiming it. The measured facts are the exact
slope and the constant offset.

The base counters also track direction correctly: the read kernel gives RDREQ high and WRREQ 0,
the write kernel gives WRREQ high and RDREQ = 2 — which is exactly the +2 intercept of the read
fit showing up on its own when there are no reads.

### 3.3 What the split counters actually do

(logs: `p3r2b_724.log`, `p3r2b_714.log`, `p3r2_batch_724.log` R2-A)

**Correction to my own first pass:** they are not identically zero. Over 8 repeats of the same
256 MiB read on 7.2.4, seven runs gave 0/0/0 with base exactly 1,048,578, and one gave
`128B_sum=15` — and in that run the *base* was also inflated, to 1,110,127. A separate run reached
`128B=193, 32B=6, 64B=6`, with base likewise inflated, to 1,050,439. All 8 repeats on
7.14.0~pre3 gave 0/0/0 with base exactly 1,048,578.

So "the split counters are dead" is not what I measured. What I measured is: **non-zero split
counts appeared only in runs where the base counter was also above the clean `bytes/256 + 2` fit,
and every clean run had zero split counts.** In the largest such run the split events total
6+6+193 = 205 against a base of 1,050,439. I cannot identify the source of those extra events —
stopping the other compute clients does not exclude display, blits, firmware, or the collection
machinery itself — and I equally cannot prove they were not the kernel's own.

**Inference, clearly labelled as such:** that pattern is consistent with — but does not prove —
the hypothesis that gfx12's EA request size is the 256 B the sweep measures, so the kernel's own
requests land in none of the 32 B / 64 B / 128 B buckets, while whatever produces the excess in the
contaminated runs uses a size that does land in one. If that is right, the zeros would be a counter
*definition* predating gfx12 rather than broken plumbing. I cannot confirm it — it needs the gfx12
perfmon spec. Could you or
someone at AMD check whether the gfx12 EA request size makes those three events unreachable by
construction? gfx1201's counter table offers no other bucket:
`GL2C_EA_RDREQ{,_32B,_64B,_128B}{,_sum}` and `GL2C_EA_WRREQ{,_64B,_STALL}{,_sum}` are all of them.

### 3.4 The consequence a user actually hits

`--list-avail` defines, on this agent:

```
FETCH_SIZE = (GL2C_EA_RDREQ_32B_sum*32 + GL2C_EA_RDREQ_64B_sum*64 + GL2C_EA_RDREQ_128B_sum*128)/1024
FetchSize  = FETCH_SIZE
```

built entirely from the three counters above (log: `p3r2_batch_724.log` R2-C).
Measured on the 256 MiB read: `FETCH_SIZE = 0`,
`FetchSize = 0`. Of the metrics this rocprofv3 version enumerates for gfx1201, those two are the
only byte-size traffic metrics present at all — there is no `WRITE_SIZE` in the list — so within
the set of built-in metrics this version offers, there is nothing that reports how many bytes a
kernel moved on this part. `GL2C_EA_RDREQ_sum` does track it on the clean runs, at the 256 B/request the sweep measures, so a
candidate replacement expression may be reachable — but only once the event semantics, the `+2`
intercept and the contaminated runs are understood.

### 3.5 Version comparison

Base 1,048,578, splits 0, `FETCH_SIZE` 0, `SQ_INSTS_VALU` 5,242,880, and the same 256 B slope on
**both** ROCm 7.2.4 / rocprofv3 1.1.0 and ROCm 7.14.0~pre3 / rocprofv3 1.3.2. So this reproduces
in both and was not introduced between them; I have not tested older releases, so I am not
claiming when it started.

## 4. Reproduction pitfalls

Three behaviours that each return success, and each of which cost me a wrong preliminary
conclusion. I am not claiming any of them is a defect — I do not know the intended contract for
any of the three — only that they are easy to walk into: the large PC sampling interval writing no
output at rc=0; counter names this version does not support being dropped from the output with no
diagnostic (`SQ_INSTS_VMEM` and `GL2C_REQ_sum` simply do not appear); and every non-`profile_*`
DPM level returning zeros. Together they mean that the natural first attempt at any of this reads
"all counters are broken on RDNA4", which is not what is happening.

The reproduction scripts hard-code a DRM card index and the `video`/`render` group IDs from this
machine (44 and 992); both need substituting elsewhere.
