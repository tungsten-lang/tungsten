#!/bin/sh
# qbatch.sh PARAMS CTL SEEDS SECS "set1" "set2" ...  -- qv.sh per set (standing start, BEYOND-HUMAN body)
P=$1; C=$2; SEEDS=$3; SECS=$4; shift 4
for S in "$@"; do scratchpad/sprint4/qv.sh "$S" $SEEDS $SECS $P $C ${WORKERS:-3}; done
