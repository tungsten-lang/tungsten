#!/bin/sh
# second stage: 60k more evals for the two forward-leaning states, init = their own first-stage optimum (tag ideal2)
cd /Users/erik/tungsten/bits/tungsten-robolab
export ROBOLAB_CALIB=v4 ROBOLAB_PROFILE=p95 ROBOLAB_PROFILE_PARTS=strength,speed,tendon,activation ROBOLAB_LJ_APPROACH=44
while [ ! -f out/long_jump_limits/lean_ideal.done ]; do sleep 10; done
for t in lean_m250 lean_z000; do
  .venv/bin/python playground/long_jump_limits.py optimise $t --evals 60000 --workers 2 --lmax=-1.5 --tag ideal2 --init out/long_jump_limits/${t}_ideal.json > out/long_jump_limits/${t}_ideal2.log 2>&1
done
echo done > out/long_jump_limits/lean_ideal2.done
