#!/bin/sh
# board-mode force-cap scan on capture bs45 (board 151.025): caps 12, 8 and none, init = the cap-20 ideal (bs45_b20.json). Sequential, 6 workers. L3
cd /Users/erik/tungsten/bits/tungsten-robolab
I=out/long_jump_limits/bs45_b20.json
for spec in "b12 --grfcap 12" "b8 --grfcap 8" "bnone"; do
  set -- $spec
  tag=$1; shift
  echo "run $tag $*" >> out/lj3/scan3.index
  scratchpad/lj3/optb.sh bs45 $tag 151.025 300000 0.03 200 $I --grfw 0.3 --lmin -15 "$@"
done
echo done > out/lj3/scan3.done
