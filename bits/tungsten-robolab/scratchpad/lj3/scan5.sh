#!/bin/sh
# yielding-knee what-if: the plant knee must flex >= 0.15 / 0.30 rad in the stance (a human plant knee flexes 0.3-0.5 rad), board mode, cap 20 BW, init the cap-20 ideal. L3
cd /Users/erik/tungsten/bits/tungsten-robolab
while [ ! -f out/lj3/scan4.done ]; do sleep 5; done
I=out/long_jump_limits/bs45_b20.json
. scratchpad/lj3/env.sh
export ROBOLAB_LJ_APPROACH=151.025
for spec in "kn15 0.15" "kn30 0.30"; do
  set -- $spec
  echo "run $1 kneemin $2" >> out/lj3/scan5.index
  nice -n 10 .venv/bin/python scratchpad/lj3/ljx.py opt bs45 --tag $1 --evals 250000 --sigma 0.03 --pop 200 --init $I --workers 5 --board --margin 0.03 --grfcap 20 --grfw 0.3 --lmin -15 --kneemin $2 > out/lj3/ljx_bs45_$1.log 2>&1
done
echo done > out/lj3/scan5.done
