# RDNA4 (gfx1201) verification-tooling measurements

Raw material behind a comment on [ROCm/ROCm#6613](https://github.com/ROCm/ROCm/issues/6613):
an on-hardware follow-up, on an **AMD Radeon RX 9070 XT (gfx1201)**, to the three RDNA4
verification-tooling gaps raised by @The-Monk in
[ROCm/composable_kernel#3759](https://github.com/ROCm/composable_kernel/pull/3759) —
device ASAN, stochastic PC sampling, and the GL2C EA size-split counters.

Everything here is measurement plus the scripts that produced it. Conclusions, with the
inference/observation split spelled out, are in **`POSTS_6613_comment.md`** (the comment as posted)
and **`RESULTS_rdna4_tools_20260819.md`** (the working record, in Japanese, including the two
first-pass claims that turned out to be wrong and how they were corrected).

## Layout

| path | what |
|---|---|
| `probes/oob.hip` | deliberate device-side OOB kernels (stack and heap) for the ASAN test |
| `probes/traffic.hip` | memory-traffic microkernels with analytically known byte counts, plus a zero-traffic null kernel |
| `build.sh`, `matrix.sh`, `matrix_full.sh` | build and target-ID acceptance matrices |
| `run_asan.sh`, `run_pcs.sh` | ASAN behaviour and PC sampling runs |
| `gl2c_sweep.sh`, `gl2c_modes.sh`, `round2_gpu.sh`, `round2b.sh` | counter collection |
| `logs/` | raw output of every run quoted in the comment |
| `logs/devimg/` | gfx1201 device code objects extracted from the plain and `-fgpu-sanitize` builds |

Two PC sampling CSVs were truncated to their first 200 rows to keep the repository small; the
row counts quoted in the comment are from the full files and are recorded in the logs.

## Environment

RX 9070 XT (gfx1201), kernel 6.14.0-37-generic, `ppfeaturemask=0xfff7ffff`. Two toolchains:
ROCm **7.14.0~pre3** (clang 23.0.0git, rocprofv3 1.3.2) and ROCm **7.2.4** (clang 22.0.0git,
rocprofv3 1.1.0); container image digests are in `logs/image_digests.txt`. All GPU measurements
were taken with every other compute client stopped and `rocm-smi` reporting zero KFD processes.

The scripts hard-code this machine's DRM card index and `video`/`render` group IDs (44, 992);
both need substituting elsewhere.

## Licence

MIT.
