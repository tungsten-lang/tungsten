#!/bin/sh
# how many harness-invalid pen states (with the fixed program rob_a4_final) do other steering settings produce? 128 captures each, 2 processes (L2)
cd /Users/erik/tungsten/bits/tungsten-robolab
export ROBOLAB_CALIB=v4 ROBOLAB_PROFILE=p95 ROBOLAB_PROFILE_PARTS=strength,speed,tendon,activation ROBOLAB_LJ_APPROACH=44
for spec in "s2:j_st_w=0.4,j_st_max=0.2" "s3:j_st_w=0.5,j_st_max=0.15,j_st_n=6" "s4:j_st_w=0.3,j_st_max=0.25"; do
  tag=${spec%%:*}; ov=${spec#*:}
  # approach params: A4c with the overrides appended (later lines win)
  cp scratchpad/lj2/A4c.txt scratchpad/lj2/A4_$tag.txt
  echo "$ov" | tr ',' '\n' | sed 's/=/ /' >> scratchpad/lj2/A4_$tag.txt
  scratchpad/lj2/capture_set.sh scratchpad/lj2/A4_$tag.txt $tag bin/challengers/long_jump_run-c3 8001 8128 2
  L=$(ls out/long_jump_limits | grep "^${tag}_s.*_capture" | sed 's/_capture.npz//' | tr '\n' ',' | sed 's/,$//')
  echo "== $tag ($ov): $(echo $L | tr ',' '\n' | wc -l) captures"
  .venv/bin/python scratchpad/lj2/harness_eval.py out/long_jump_limits/rob_a4_final.txt $L --quiet 2>&1 | tail -2
done
echo DONE
