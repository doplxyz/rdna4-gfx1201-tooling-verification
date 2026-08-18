#!/bin/bash
BIN=$1; OUT=$2; mkdir -p $OUT
run () { # label mode counters...
  local label=$1 mode=$2; shift 2
  rocprofv3 --pmc "$@" --output-format csv -d $OUT/$label -o r -- $BIN $mode 268435456 1 >/dev/null 2>$OUT/$label.err
  local f=$(find $OUT/$label -name "r_counter_collection.csv" | head -1)
  [ -z "$f" ] && { echo "  [$label] NO CSV"; return; }
  python3 - "$f" "$label" <<'PY'
import csv,sys,collections
rows=[r for r in csv.DictReader(open(sys.argv[1])) if "rocclr" not in r["Kernel_Name"]]
agg=collections.defaultdict(float)
for r in rows: agg[r["Counter_Name"]]+=float(r["Counter_Value"])
print("   ", sys.argv[2], " ".join(f"{k}={v:,.0f}" for k,v in sorted(agg.items())))
PY
}
echo "mode 0 = 256 MiB contiguous float4 READ  (analytic 268,435,456 B)"
run m0_rd 0 GL2C_EA_RDREQ_sum GL2C_EA_RDREQ_32B_sum GL2C_EA_RDREQ_64B_sum GL2C_EA_RDREQ_128B_sum
run m0_wr 0 GL2C_EA_WRREQ_sum GL2C_EA_WRREQ_64B_sum
run m0_dv 0 FETCH_SIZE WRITE_SIZE
echo "mode 1 = 256 MiB contiguous float  READ"
run m1_rd 1 GL2C_EA_RDREQ_sum GL2C_EA_RDREQ_32B_sum GL2C_EA_RDREQ_64B_sum GL2C_EA_RDREQ_128B_sum
echo "mode 2 = 32 MiB requested, 32 B stride READ (sparse)"
run m2_rd 2 GL2C_EA_RDREQ_sum GL2C_EA_RDREQ_32B_sum GL2C_EA_RDREQ_64B_sum GL2C_EA_RDREQ_128B_sum
echo "mode 3 = 256 MiB contiguous float4 WRITE (analytic 268,435,456 B)"
run m3_wr 3 GL2C_EA_WRREQ_sum GL2C_EA_WRREQ_64B_sum
run m3_rd 3 GL2C_EA_RDREQ_sum GL2C_EA_RDREQ_32B_sum GL2C_EA_RDREQ_64B_sum GL2C_EA_RDREQ_128B_sum
run m3_dv 3 FETCH_SIZE WRITE_SIZE
