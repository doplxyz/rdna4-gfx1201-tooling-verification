#!/bin/bash
BIN=$1; OUT=$2; mkdir -p $OUT
pmc () { local label=$1 kern=$2 mode=$3 bytes=$4; shift 4
  rm -rf $OUT/$label
  rocprofv3 --pmc "$@" --output-format csv -d $OUT/$label -o r -- $BIN $mode $bytes 1 >/dev/null 2>$OUT/$label.err
  local f=$(find $OUT/$label -name "r_counter_collection.csv" | head -1)
  [ -z "$f" ] && { echo "$label NO_CSV"; return; }
  python3 - "$f" "$kern" "$label" <<'PY'
import csv,sys,collections
rows=[r for r in csv.DictReader(open(sys.argv[1])) if sys.argv[2] in r["Kernel_Name"]]
a=collections.defaultdict(float); d=set()
for r in rows: a[r["Counter_Name"]]+=float(r["Counter_Value"]); d.add(r["Dispatch_Id"])
print(" ", sys.argv[3], "disp=%d"%len(d), " ".join(f"{k.replace('GL2C_EA_RDREQ','R')}={v:.0f}" for k,v in sorted(a.items())))
PY
}
echo "### split-counter noise characterisation: 8 runs, 256 MiB read, identical command"
for i in $(seq 1 8); do pmc "noise$i" read_f4 0 268435456 GL2C_EA_RDREQ_sum GL2C_EA_RDREQ_32B_sum GL2C_EA_RDREQ_64B_sum GL2C_EA_RDREQ_128B_sum; done
echo "### read sweep (this toolchain)"
pmc "sw_null" null_kernel 4 268435456 GL2C_EA_RDREQ_sum GL2C_EA_RDREQ_128B_sum
for mb in 16 64 256; do pmc "sw_${mb}" read_f4 0 $((mb*1048576)) GL2C_EA_RDREQ_sum GL2C_EA_RDREQ_128B_sum; done
