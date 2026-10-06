#!/bin/sh
# Q9: after the pools: lists; K2 on CONFIRMATION 32001-32480 (the unbiased read of the pipeline); then the mini-batch training Rk2 (pool zh + zh2, held-out zv, init = Rk1 gen-10 snapshot) and its monitor.
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
while [ ! -f out/lj6/q8.done ]; do sleep 5; done
. scratchpad/lj6/env6.sh
export ROBOLAB_LJ_APPROACH=151.025 ROBOLAB_LJ_MARGIN=0.03
rm -f out/lj6/q9.done
.venv/bin/python scratchpad/lj4/mklist.py zh2 34601 35500 out/lj6/zh2 2 1 > out/lj6/zh2_list.log 2>&1
.venv/bin/python scratchpad/lj4/mklist.py zv 36001 36500 out/lj6/zv 2 1 > out/lj6/zv_list.log 2>&1
cat out/lj6/zh_all.txt > out/lj6/ztrain.txt; printf "," >> out/lj6/ztrain.txt; cat out/lj6/zh2_all.txt >> out/lj6/ztrain.txt
scratchpad/lj6/ev6.sh K2 long_jump_v4_beyond_robust96 out/lj6/par_K2.txt bin/challengers/long_jump_run_y-l4b 32001-32480 6
echo ok > out/lj6/q9.conf_done
WORKERS=5 SIGMA=0.02 POP=100 nohup scratchpad/lj6/train6.sh Rk2 out/lj6/ztrain.txt 8000000 out/lj6/rk_Rk1_snap2.txt --obj mix --c 8.735 --tau 0.2 --a1 0.02 --c1 7.8 --a0 0.005 --legal-floor 0.8 --legal-w 1.0 --shift 0.10 --batch 260 --snap 10 --keep > out/lj6/rk_Rk2.run.log 2>&1 &
echo $! > out/lj6/rk_Rk2.pid
nohup scratchpad/lj6/monitor6.sh Rk2 out/lj6/zv_all.txt 420 40 --shift 0.10 > out/lj6/monitor_Rk2.log 2>&1 &
echo $! > out/lj6/monitor_Rk2.pid
echo done > out/lj6/q9.done
