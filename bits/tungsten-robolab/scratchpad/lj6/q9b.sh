#!/bin/sh
# Q9b: after the running K2 CONFIRMATION evaluation: the mini-batch training Rk2 (pool zh + zh2 = 1291 states, batch 260, init = Rk1 generation-20 snapshot, shift 0.10) and its monitor on the held-out pool zv (425 states).
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
while pgrep -f "scratchpad/lj6/ev6.sh K2" > /dev/null; do sleep 3; done
. scratchpad/lj6/env6.sh
export ROBOLAB_LJ_APPROACH=151.025 ROBOLAB_LJ_MARGIN=0.03
rm -f out/lj6/q9.done
WORKERS=5 SIGMA=0.02 POP=100 nohup scratchpad/lj6/train6.sh Rk2 out/lj6/ztrain.txt 8000000 out/lj6/rk_Rk1_snap3.txt --obj mix --c 8.735 --tau 0.2 --a1 0.02 --c1 7.8 --a0 0.005 --legal-floor 0.8 --legal-w 1.0 --shift 0.10 --batch 260 --snap 10 --keep > out/lj6/rk_Rk2.run.log 2>&1 &
echo $! > out/lj6/rk_Rk2.pid
nohup scratchpad/lj6/monitor6.sh Rk2 out/lj6/zv_all.txt 420 40 --shift 0.10 > out/lj6/monitor_Rk2.log 2>&1 &
echo $! > out/lj6/monitor_Rk2.pid
echo done > out/lj6/q9.done
