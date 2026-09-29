#!/bin/sh
# steering with more shortening authority: j_st_max 0.30 / 0.35 / 0.40 (w 0.5, n 5, rnd 0.75), 128 captures each, fixed program rob_a4_final (L2); 4 capture processes
cd /Users/erik/tungsten/bits/tungsten-robolab
export ROBOLAB_CALIB=v4 ROBOLAB_PROFILE=p95 ROBOLAB_PROFILE_PARTS=strength,speed,tendon,activation ROBOLAB_LJ_APPROACH=44
for spec in "s8:j_st_rnd=0.9" "s9:j_st_rnd=1.0"; do
  tag=${spec%%:*}; ov=${spec#*:}
  cp scratchpad/lj2/A4c.txt scratchpad/lj2/A4_$tag.txt
  echo "$ov" | tr ',' '\n' | sed 's/=/ /' >> scratchpad/lj2/A4_$tag.txt
  scratchpad/lj2/capture_set.sh scratchpad/lj2/A4_$tag.txt $tag bin/challengers/long_jump_run-c3 8001 8128 4
  L=$(ls out/long_jump_limits | grep "^${tag}_s.*_capture" | sed 's/_capture.npz//' | tr '\n' ',' | sed 's/,$//')
  echo "== $tag ($ov): $(echo $L | tr ',' '\n' | wc -l) captures"
  .venv/bin/python scratchpad/lj2/harness_eval.py out/long_jump_limits/rob_a4_final.txt $L --quiet 2>&1 | tail -2
done
echo DONE
