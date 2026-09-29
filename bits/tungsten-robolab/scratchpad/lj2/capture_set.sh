#!/bin/sh
# capture the penultimate-touchdown states of a set of starts for an approach params file (runner + planner: rebuild it with
# scratchpad/lj2/mkparams.py when the runner changes). usage: capture_set.sh <approach.txt> <name> <controller> [first_seed last_seed] [procs]
cd /Users/erik/tungsten/bits/tungsten-robolab
P=$1; N=$2; C=$3; A=${4:-8001}; B=${5:-8064}; K=${6:-1}
export ROBOLAB_CALIB=v4 ROBOLAB_PROFILE=p95 ROBOLAB_PROFILE_PARTS=strength,speed,tendon,activation
mk() { python3 -c "print(','.join(str(i) for i in range($1, $2+1)))"; }
.venv/bin/python playground/long_jump_limits.py capture long_jump_v4_p95b --params $P --controller $C --name ${N}_nom --from pen > out/long_jump_limits/cap_${N}_nom.log 2>&1
# split the seed range over K processes
i=0
tot=$(( B - A + 1 )); per=$(( (tot + K - 1) / K ))
while [ $i -lt $K ]; do
  lo=$(( A + i * per )); hi=$(( lo + per - 1 )); [ $hi -gt $B ] && hi=$B
  S=$(mk $lo $hi)
  nohup .venv/bin/python playground/long_jump_limits.py capture long_jump_v4_p95b --params $P --controller $C --seeds $S --name $N --from pen > out/long_jump_limits/cap_${N}_$lo.log 2>&1 &
  i=$(( i + 1 ))
done
wait
echo done > out/long_jump_limits/cap_${N}.done
