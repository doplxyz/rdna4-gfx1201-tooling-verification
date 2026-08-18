#!/bin/bash
CXX=$1
echo "compiler: $($CXX --version | head -1)"
printf '%-22s %-6s %s\n' "offload-arch" "rc" "diagnostic"
for arch in gfx90a gfx90a:xnack+ gfx908:xnack+ gfx942 gfx942:xnack+ gfx950:xnack+ \
            gfx1010:xnack+ gfx1030:xnack+ gfx1100 gfx1100:xnack+ gfx1101:xnack+ \
            gfx1200:xnack+ gfx1201 gfx1201:xnack+ gfx1201:xnack- gfx12-generic:xnack+; do
  out=$($CXX -x hip --offload-arch="$arch" -fsanitize=address -fgpu-sanitize \
        -nogpuinc -nogpulib --cuda-device-only -S -o /dev/null probes/empty.hip 2>&1)
  rc=$?
  d=$(echo "$out" | grep -m1 -E "error:|warning:" | sed 's/^clang++: //')
  printf '%-22s %-6s %s\n' "$arch" "$rc" "${d:0:110}"
done
