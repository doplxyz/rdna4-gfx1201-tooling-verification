#!/bin/bash
# Builds the probes. Usage: build.sh <tag> <clangxx>
set -u
TAG=$1; CXX=$2; EXTRA="${3:-}"
mkdir -p bin/$TAG
echo "=== $TAG : $CXX"
$CXX --version | head -2

echo "--- traffic (gfx1201, no sanitizer)"
$CXX $EXTRA -x hip --offload-arch=gfx1201 -O3 -o bin/$TAG/traffic probes/traffic.hip
echo "rc=$?"

echo "--- oob plain (gfx1201, no sanitizer)"
$CXX $EXTRA -x hip --offload-arch=gfx1201 -O1 -o bin/$TAG/oob_plain probes/oob.hip
echo "rc=$?"

echo "--- oob with -fsanitize=address -fgpu-sanitize (gfx1201)"
$CXX $EXTRA -x hip --offload-arch=gfx1201 -O1 -fsanitize=address -fgpu-sanitize \
     -o bin/$TAG/oob_asan probes/oob.hip
echo "rc=$?"

echo "--- oob with -fsanitize=address -fgpu-sanitize (gfx1201:xnack+)  [expected: reject]"
$CXX $EXTRA -x hip --offload-arch=gfx1201:xnack+ -O1 -fsanitize=address -fgpu-sanitize \
     -o bin/$TAG/oob_asan_xnack probes/oob.hip
echo "rc=$?"

echo "--- CONTROL: oob with ASAN for gfx942:xnack+ (compile only, no such GPU here)"
$CXX $EXTRA -x hip --offload-arch=gfx942:xnack+ -O1 -fsanitize=address -fgpu-sanitize \
     -c -o bin/$TAG/oob_gfx942_xnack.o probes/oob.hip
echo "rc=$?"

ls -l bin/$TAG
