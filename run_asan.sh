#!/bin/bash
TAG=$1
export ASAN_OPTIONS=detect_leaks=0     # host LeakSanitizer noise from the HSA runtime
echo "=== ASAN behaviour on gfx1201 ($TAG), ASAN_OPTIONS=$ASAN_OPTIONS"
for mode in 0 1; do
  case $mode in 0) d="device stack OOB (write past 2-elem array; CK#3759 bug-1 shape)";;
                1) d="device heap OOB (write 4 B past a hipMalloc'd buffer)";; esac
  echo; echo "--- mode $mode: $d"
  for variant in "plain:./bin/$TAG/oob_plain" "asan:./bin/$TAG/oob_asan" "asan+HSA_XNACK=1:env HSA_XNACK=1 ./bin/$TAG/oob_asan"; do
    name=${variant%%:*}; cmd=${variant#*:}
    out=$($cmd $mode 2>&1); rc=$?
    echo "  [$name] rc=$rc"
    echo "$out" | sed 's/^/      /'
  done
done

echo
echo "=== is the gfx1201 device image actually instrumented?"
BUNDLER=$(dirname $CLANGXX)/clang-offload-bundler
for b in oob_plain oob_asan; do
  rm -f /tmp/dev_$b.co
  $BUNDLER --type=o --targets=hipv4-amdgcn-amd-amdhsa--gfx1201 \
      --input=bin/$TAG/$b --output=/tmp/dev_$b.co --unbundle 2>/dev/null
  if [ -s /tmp/dev_$b.co ]; then
    n=$($(dirname $CLANGXX)/llvm-nm /tmp/dev_$b.co 2>/dev/null | grep -c "asan")
    echo "  $b: device code object extracted, symbols matching 'asan' = $n"
  else
    echo "  $b: (could not unbundle from the executable; using the fat binary instead)"
    n=$($(dirname $CLANGXX)/llvm-strings bin/$TAG/$b 2>/dev/null | grep -c "__asan_report")
    echo "  $b: __asan_report strings in whole binary = $n"
  fi
done
