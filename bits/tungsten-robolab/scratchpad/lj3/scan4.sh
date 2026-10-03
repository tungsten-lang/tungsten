#!/bin/sh
# what-ifs on the board-mode ideal of capture bs45 (cap 20 BW, init = the cap-20 ideal; 5 workers, 200k evals each):
#   strength (ROBOLAB_LJ_FSCALE: every muscle's peak force x f; 0.55 = the beyond body's x2.4 brought down to about P95's x1.32) and
#   approach speed (ROBOLAB_LJ_DV: the whole body +dv m/s at the penultimate touchdown). L3
cd /Users/erik/tungsten/bits/tungsten-robolab
while pgrep -f "playground/long_jump_limits.py landing" > /dev/null; do sleep 5; done
I=out/long_jump_limits/bs45_b20.json
. scratchpad/lj3/env.sh
export ROBOLAB_LJ_APPROACH=151.025
run() { # tag fscale dv
  tag=$1
  echo "run $tag FSCALE=$2 DV=$3" >> out/lj3/scan4.index
  ROBOLAB_LJ_FSCALE=$2 ROBOLAB_LJ_DV=$3 nice -n 10 .venv/bin/python scratchpad/lj3/ljx.py opt bs45 --tag $tag --evals 200000 --sigma 0.03 --pop 200 --init $I --workers 5 --board --margin 0.03 --grfcap 20 --grfw 0.3 --lmin -15 > out/lj3/ljx_bs45_$tag.log 2>&1
}
run w055 0.55 0
run w075 0.75 0
run v_m05 1.0 -0.5
run v_p05 1.0 0.5
run v_m25 1.0 -2.5
echo done > out/lj3/scan4.done
