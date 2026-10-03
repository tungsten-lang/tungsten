#!/bin/sh
# capture the penultimate-touchdown states of a range of perturbed starts for an approach params file (the jump's planner included),
# LABELLED BEYOND-HUMAN BODY, check mark of task long_jump_v4_beyond_a. usage: capset.sh <approach.txt> <prefix> <controller> <first_seed> <last_seed> <procs>
cd /Users/erik/tungsten/bits/tungsten-robolab
. scratchpad/lj3/env.sh
P=$1; N=$2; C=$3; A=$4; B=$5; K=${6:-3}
mk() { python3 -c "print(','.join(str(i) for i in range($1, $2+1)))"; }
i=0
tot=$(( B - A + 1 )); per=$(( (tot + K - 1) / K ))
rm -f out/lj3/capset_${N}.done
while [ $i -lt $K ]; do
  lo=$(( A + i * per )); hi=$(( lo + per - 1 )); [ $hi -gt $B ] && hi=$B
  S=$(mk $lo $hi)
  nice -n 10 .venv/bin/python playground/long_jump_limits.py capture long_jump_v4_beyond_a --params $P --controller $C --seeds $S --name $N --from pen > out/lj3/capset_${N}_$lo.log 2>&1 &
  i=$(( i + 1 ))
done
wait
echo done > out/lj3/capset_${N}.done
