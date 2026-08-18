#!/bin/bash
TAG=$1; OUT=logs/pcs_$TAG; rm -rf $OUT; mkdir -p $OUT
APP="./bin/$TAG/traffic 0 268435456 20"
echo "=== rocprofv3 version"; rocprofv3 --version 2>&1 | grep -E "version|rocm_version"
echo; echo "=== PC sampling configurations advertised for this agent"
rocprofv3 --list-avail 2>/dev/null | awk '/^GPU/{p=1} /Counter_Name/{p=0} p' | head -20
for m in host_trap stochastic; do
  echo; echo "=== --pc-sampling-method $m"
  rocprofv3 --pc-sampling-beta-enabled --pc-sampling-method $m --pc-sampling-unit time \
            --pc-sampling-interval 1000000 -d $OUT/$m -o s --output-format csv -- $APP \
            > $OUT/$m.stdout 2> $OUT/$m.stderr
  echo "rc=$?"
  echo "--- stderr (first 6 lines)"; head -6 $OUT/$m.stderr | sed 's/^/    /'
  f=$(find $OUT/$m -name "*pc_sampling*" 2>/dev/null | head -1)
  if [ -n "$f" ]; then
    echo "--- output: $f  rows=$(( $(wc -l < "$f") - 1 ))"
    echo "--- distinct PCs: $(tail -n +2 "$f" | cut -d, -f5 | sort -u | wc -l)"
    head -2 "$f" | sed 's/^/    /'
  else
    echo "--- no pc_sampling output file produced"; find $OUT/$m -type f 2>/dev/null | head -5 | sed 's/^/    /'
  fi
done
