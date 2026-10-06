#!/bin/sh
# L6: capture the penultimate-touchdown states of a range of perturbed starts for an approach params file (the jump's planner included), LABELLED beyond-human body, unlimited run-up,
# check mark of task long_jump_v4_beyond_a (151.025 m); captures out/long_jump_limits/<prefix>_s<seed>_capture.npz. (copy of scratchpad/lj4/capset.sh with L6's paths, thread caps, nice)
# usage: capset6.sh <approach.txt> <prefix> <controller> <first_seed> <last_seed> <procs>
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
. scratchpad/lj6/env6.sh
P=$1; N=$2; C=$3; A=$4; B=$5; K=${6:-6}
i=0
tot=$(( B - A + 1 )); per=$(( (tot + K - 1) / K ))
rm -f out/lj6/capset_${N}.done
while [ $i -lt $K ]; do
  lo=$(( A + i * per )); hi=$(( lo + per - 1 )); [ $hi -gt $B ] && hi=$B
  S=$(python3 -c "print(','.join(str(i) for i in range($lo, $hi+1)))")
  nice -n 10 .venv/bin/python playground/long_jump_limits.py capture long_jump_v4_beyond_a --params $P --controller $C --seeds $S --name $N --from pen > out/lj6/capset_${N}_$lo.log 2>&1 &
  i=$(( i + 1 ))
done
wait
echo done > out/lj6/capset_${N}.done
