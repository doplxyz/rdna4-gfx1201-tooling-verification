#!/bin/bash
# $1 = tag, $2 = outdir suffix (describes the environment/knobs)
TAG=$1; SUF=$2
OUT=/w/logs/gl2c_${TAG}_${SUF}; rm -rf $OUT; mkdir -p $OUT
APP="/w/bin/$TAG/traffic"
collect () { # $1 label, $2 pmc list, $3.. app args
  local label=$1 pmc=$2; shift 2
  rocprofv3 --pmc $pmc --output-format csv -d $OUT/$label -o r -- $APP "$@" > $OUT/$label.out 2> $OUT/$label.err
  echo "rc=$? label=$label" >> $OUT/$label.err
}
GROUP1="GL2C_EA_RDREQ_sum GL2C_EA_RDREQ_32B_sum GL2C_EA_RDREQ_64B_sum GL2C_EA_RDREQ_128B_sum"
GROUP2="GL2C_EA_WRREQ_sum GL2C_EA_WRREQ_64B_sum GL2C_REQ_sum GL2C_MISS_sum"
GROUP3="FETCH_SIZE WRITE_SIZE"
for mode in 0 1 2 3; do
  collect m${mode}_g1 "$GROUP1" $mode 268435456 1
  collect m${mode}_g2 "$GROUP2" $mode 268435456 1
  collect m${mode}_g3 "$GROUP3" $mode 268435456 1
done
