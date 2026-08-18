#!/bin/bash
# One batch: everything sol asked to re-measure that needs the GPU.
BIN=$1; OUT=$2; mkdir -p $OUT
KERN=${3:-read_f4}

pmc () { # $1 label, $2 kernel-substring, $3 mode, $4 bytes, rest: counters
  local label=$1 kern=$2 mode=$3 bytes=$4; shift 4
  rm -rf $OUT/$label
  rocprofv3 --pmc "$@" --output-format csv -d $OUT/$label -o r -- $BIN $mode $bytes 1 >/dev/null 2>$OUT/$label.err
  local f=$(find $OUT/$label -name "r_counter_collection.csv" | head -1)
  [ -z "$f" ] && { echo "$label NO_CSV"; return; }
  python3 - "$f" "$kern" "$label" <<'PY'
import csv,sys,collections
rows=[r for r in csv.DictReader(open(sys.argv[1])) if sys.argv[2] in r["Kernel_Name"]]
a=collections.defaultdict(float); disp=set()
for r in rows: a[r["Counter_Name"]]+=float(r["Counter_Value"]); disp.add(r["Dispatch_Id"])
print(sys.argv[3], "dispatches=%d"%len(disp), " ".join(f"{k}={v:.0f}" for k,v in sorted(a.items())))
PY
}

echo "### R2-A  read size sweep (baseline + slope), profile_standard assumed"
for mb in 0 16 32 64 128 256 512; do
  if [ $mb -eq 0 ]; then pmc "rd_null" null_kernel 4 268435456 GL2C_EA_RDREQ_sum GL2C_EA_RDREQ_32B_sum GL2C_EA_RDREQ_64B_sum GL2C_EA_RDREQ_128B_sum
  else pmc "rd_${mb}MiB" read_f4 0 $((mb*1048576)) GL2C_EA_RDREQ_sum GL2C_EA_RDREQ_32B_sum GL2C_EA_RDREQ_64B_sum GL2C_EA_RDREQ_128B_sum; fi
done

echo "### R2-B  write size sweep"
for mb in 16 32 64 128 256 512; do
  pmc "wr_${mb}MiB" write_f4 3 $((mb*1048576)) GL2C_EA_WRREQ_sum GL2C_EA_WRREQ_64B_sum
done

echo "### R2-C  every byte-size / traffic metric this rocprofv3 defines, on a 256 MiB read"
pmc "bytesize" read_f4 0 268435456 FETCH_SIZE FetchSize

echo "### R2-D  repeats at fixed size (n=5)"
for i in 1 2 3 4 5; do
  pmc "rep$i" read_f4 0 268435456 SQ_WAVES SQ_INSTS_VALU GL2C_EA_RDREQ_sum GL2C_EA_RDREQ_128B_sum
done

echo "### R2-E  PC sampling: ONE fixed workload, interval sweep"
for iv in 512 1000 10000 100000 1000000 10000000; do
  rm -rf $OUT/pcs_$iv
  rocprofv3 --pc-sampling-beta-enabled --pc-sampling-method host_trap --pc-sampling-unit time \
    --pc-sampling-interval $iv --output-format csv -d $OUT/pcs_$iv -o r -- $BIN 0 268435456 400 >/dev/null 2>$OUT/pcs_$iv.err
  rc=$?
  f=$(find $OUT/pcs_$iv -name "*host_trap.csv" 2>/dev/null | head -1)
  if [ -n "$f" ]; then echo "  host_trap interval=$iv rc=$rc samples=$(( $(wc -l < "$f") - 1 ))"
  else echo "  host_trap interval=$iv rc=$rc NO OUTPUT FILE"; fi
done
echo "### R2-F  stochastic on the same fixed workload"
rocprofv3 --pc-sampling-beta-enabled --pc-sampling-method stochastic --pc-sampling-unit time \
  --pc-sampling-interval 1000 --output-format csv -d $OUT/pcs_stoch -o r -- $BIN 0 268435456 400 >/dev/null 2>$OUT/pcs_stoch.err
echo "  stochastic interval=1000 rc=$? msg=$(grep -m1 '^E[0-9]' $OUT/pcs_stoch.err | sed 's/.*\] //')"
