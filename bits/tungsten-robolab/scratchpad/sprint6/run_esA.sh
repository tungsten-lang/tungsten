#!/bin/sh
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
exec nice -n 10 .venv/bin/python scratchpad/sprint6/rses6.py esA scratchpad/sprint6/es_a.txt --ctl bin/challengers/run_gearz-s6f --train out/sprint6/ar_train.txt --valid out/sprint6/ar_valid.txt \
  --only "rk_*" --exclude "rk_thr,rk_cap_st,rk_cap_ln,rk_rate_st,rk_rate_ln" --seconds 5.5 --k 200 --k2 160 --lam 8 --sigma 0.1 --mut 6 --workers 6 > out/sprint6/esA.out 2>&1
