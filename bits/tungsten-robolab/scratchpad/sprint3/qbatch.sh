#!/bin/sh
# qbatch.sh PARAMS CTL SEEDS SECS "set1" "set2" ...  -- qv.sh per set (standing start, SPRINTER body)
P=$1; C=$2; SEEDS=$3; SECS=$4; shift 4
for S in "$@"; do scratchpad/sprint3/qv.sh "$S" $SEEDS $SECS $P $C ${WORKERS:-3}; done
