#!/bin/sh
# plausibility scan: plant-foot peak normal force cap (12 ms average, BW) vs the best foot-mode D. Sequential, 6 workers. L3
cd /Users/erik/tungsten/bits/tungsten-robolab
. scratchpad/lj3/env.sh
export ROBOLAB_LJ_APPROACH=150.35
run() { # tag, extra args...
  tag=$1; shift
  echo "run $tag $*" >> out/lj3/scan2.index
  nice -n 10 .venv/bin/python scratchpad/lj3/ljx.py opt b0_nom --tag $tag --workers 6 --evals 300000 "$@" > out/lj3/ljx_b0_nom_$tag.log 2>&1
}
S1=out/long_jump_limits/b0_nom_s1.json
run g20 --grfcap 20 --grfw 0.3 --lmin -15 --init $S1 --sigma 0.03
run g20r --grfcap 20 --grfw 0.3 --lmin -15 --sigma 0.04
run g12 --grfcap 12 --grfw 0.3 --lmin -15 --sigma 0.04
run g8 --grfcap 8 --grfw 0.3 --lmin -15 --sigma 0.04
run u2 --lmin -15 --sigma 0.04 --seed 2
echo done > out/lj3/scan2.done
