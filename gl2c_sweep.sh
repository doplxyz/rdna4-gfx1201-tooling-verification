#!/bin/bash
# Sweep GL2C and neighbouring blocks. Each group is one rocprofv3 pass.
BIN=$1; OUT=$2; mkdir -p $OUT
run () {
  local label=$1; shift
  rocprofv3 --pmc "$@" --output-format csv -d $OUT/$label -o r -- $BIN 0 268435456 1 >/dev/null 2>$OUT/$label.err
  local rc=$?
  local f=$(find $OUT/$label -name "r_counter_collection.csv" | head -1)
  if [ -z "$f" ]; then echo "  [$label] rc=$rc NO CSV: $(grep -m1 -E '^E|error|Error' $OUT/$label.err | head -c 120)"; return; fi
  python3 - "$f" <<'PY'
import csv,sys,collections
rows=list(csv.DictReader(open(sys.argv[1])))
agg=collections.defaultdict(float)
for r in rows:
    if "read_f4" in r["Kernel_Name"]:
        agg[r["Counter_Name"]]+=float(r["Counter_Value"])
for k in sorted(agg): print(f"    {k:<28} {agg[k]:>18,.0f}")
PY
}
echo "### counters for the read_f4 kernel, 256 MiB contiguous float4 read (analytic: 268,435,456 B)"
echo "  -- group: sanity (wave/instruction level)"
run sanity SQ_WAVES SQ_INSTS_VALU SQ_INSTS_VMEM
echo "  -- group: GL2C EA read, base + size split"
run ea_rd GL2C_EA_RDREQ_sum GL2C_EA_RDREQ_32B_sum GL2C_EA_RDREQ_64B_sum GL2C_EA_RDREQ_128B_sum
echo "  -- group: GL2C request/miss (same block, not EA)"
run gl2c_req GL2C_REQ_sum GL2C_MISS_sum GL2C_HIT_sum
echo "  -- group: GL2C EA write"
run ea_wr GL2C_EA_WRREQ_sum GL2C_EA_WRREQ_64B_sum
echo "  -- group: derived metrics that depend on the size split"
run derived FETCH_SIZE WRITE_SIZE
echo "  -- group: per-instance (no reduce) GL2C_EA_RDREQ"
run per_inst GL2C_EA_RDREQ
