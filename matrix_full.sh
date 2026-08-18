#!/bin/bash
CXX=$1
echo "compiler: $($CXX --version | head -1)"
echo "targets enumerated by: $CXX -target amdgcn-amd-amdhsa -mcpu=help"
printf '%-20s %-10s %s\n' "target" "xnack+" "plain+ASAN diagnostic"
for t in $(cat logs/all_gfx_targets.txt); do
  o1=$($CXX -x hip --offload-arch="$t:xnack+" -fsanitize=address -fgpu-sanitize --cuda-device-only -S -o /dev/null probes/empty.hip 2>&1); r1=$?
  o2=$($CXX -x hip --offload-arch="$t"        -fsanitize=address -fgpu-sanitize --cuda-device-only -S -o /dev/null probes/empty.hip 2>&1); r2=$?
  if [ $r1 -eq 0 ]; then x="ACCEPTED"; else
     echo "$o1" | grep -q "invalid target ID" && x="invalid-tid" || x="other-err"; fi
  d=""
  echo "$o2" | grep -q "ignoring '-fsanitize=address'" && d="warn:ignored"
  [ $r2 -ne 0 ] && d="$d rc=$r2"
  printf '%-20s %-10s %s\n' "$t" "$x" "$d"
done
