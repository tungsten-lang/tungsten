#!/bin/sh
# mkprac.sh CHAIN OUT KIND  -- practice file of a chain for the run_geary controller: every gear twin explicit (incl. the geary mechanisms at 0), then
#   KIND top : gear0 2 + fly_entry 2 (the rollout starts in gear 2 at a snapshot and makes the real switch to gear 3)
#   KIND hand: fly_entry 2, no gear0 (the rollout starts in gear 1 at a snapshot and makes the real switches to gears 2 and 3)
#   KIND chain: just the frozen twins (a standing-start chain file)
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
. scratchpad/sprint4/env.sh
CH=$1; OUT=$2; KIND=$3
ROBOLAB_CONTROLLER=bin/challengers/run_geary-s5a .venv/bin/python scratchpad/sprint4/freeze_twins.py $CH $OUT.tmp --note "(frozen twins, $KIND)" > /dev/null
grep -v -E "^(gear0|fly_entry) " $OUT.tmp > $OUT
rm -f $OUT.tmp
case $KIND in
  top) echo "gear0 2.0" >> $OUT; echo "fly_entry 2.0" >> $OUT ;;
  hand) echo "fly_entry 2.0" >> $OUT ;;
esac
echo "wrote $OUT ($KIND)"
