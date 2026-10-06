#!/bin/sh
# L6 FINAL phase: CONFIRMATION 32001-32480 of the chosen candidate (if not yet run), then TEST 33001-33480 ONCE for the candidate, ONCE for C7 and ONCE for L3's stock champion.
# LABELLED beyond-human body, unlimited run-up. usage: final.sh <tag> <candidate params> [conf]   (conf = also run CONFIRMATION)
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
tag=$1; par=$2
T=long_jump_v4_beyond_robust96
rm -f out/lj6/final_$tag.done
if [ "$3" = "conf" ]; then
  scratchpad/lj6/ev6.sh $tag $T $par bin/challengers/long_jump_run_y-l4b 32001-32480 6
fi
if [ "$4" = "test" ] || [ "$3" = "test" ]; then
  scratchpad/lj6/ev6.sh $tag $T $par bin/challengers/long_jump_run_y-l4b 33001-33480 6
  scratchpad/lj6/ev6.sh C7 $T params/long_jump_beyond_rob2.txt bin/challengers/long_jump_run_y-l4b 33001-33480 6
  scratchpad/lj6/ev6.sh L3 $T playground/arena/params/long_jump_v4_beyond_robust96-20260930-190409.txt bin/champions/long_jump_v4_beyond_robust96-20260930-190409 33001-33480 6
fi
echo done > out/lj6/final_$tag.done
