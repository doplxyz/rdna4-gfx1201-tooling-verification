Unrelated to this PR's review — just closing the loop on the offer I made earlier. I ran the three
RDNA4 verification-tooling items you listed on my 9070 XT. Short answer to "if you've gotten any of
those three working": none of them, but two came with a sharper description than "unsupported", and
two of my own first-pass conclusions turned out to be wrong and are corrected in the write-up.

Posted as a comment on your ROCm/ROCm#6613 rather than as new issues, since it is your ticket and
splitting it seemed worse than keeping it in one place:
https://github.com/ROCm/ROCm/issues/6613#issuecomment-5331188358

Measurements, scripts and raw logs:
https://github.com/doplxyz/rdna4-gfx1201-tooling-verification

Headline for each: device ASAN — every RDNA target from gfx1030 on rejects `xnack+`, not just
RDNA4, and on gfx1201 `-fgpu-sanitize` emits a device `.text` byte-identical to the plain build
while exiting 0. Stochastic PC sampling — not advertised, rejected in all 12 configurations tried,
with host_trap working on the same workload as a control. GL2C — the base EA counters are exact
(`count = bytes/256 + 2` across a size sweep, so 256 B per request), the size-split counters are
zero on every run that lands on that fit, and `FETCH_SIZE` is defined solely from those three, so
it reports 0 KB for a kernel that read 256 MiB. Same on ROCm 7.2.4 and 7.14.

The ball on this PR is still yours; nothing here needs a reply from you.
