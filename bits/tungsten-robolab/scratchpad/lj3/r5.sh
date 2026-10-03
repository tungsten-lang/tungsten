#!/bin/sh
# robust stage r5: the same as r2/r3 but from the YIELDING-KNEE ideal (kl35) as base and init, with the knee kept flexed >= 0.2 rad at the instant of peak force. Waits for the kl35 landing search. L3
cd /Users/erik/tungsten/bits/tungsten-robolab
while pgrep -f "landing --handover hk35" > /dev/null; do sleep 5; done
scratchpad/lj3/rob.sh r5 out/lj3/r1_train2.txt 1200000 out/lj3/ik_bs45_kl35.txt --init out/lj3/par_one_kl35.txt --sigma 0.025 --pop 100 --risk 0.3 --tailq 0.1 --kneeload 0.2
