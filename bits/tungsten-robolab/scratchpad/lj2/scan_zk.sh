#!/bin/sh
# hop-height steering (j_st_zk, controller c2): step-length sensitivity to z_ref, then steering configs with it (L2)
cd /Users/erik/tungsten/bits/tungsten-robolab
C=bin/challengers/long_jump_run-c2
echo "== step length vs g2_z_ref (approach only, 8 starts)"
.venv/bin/python scratchpad/lj2/steps.py scratchpad/lj2/A1.txt $C long_jump_v4_p95b 44 None,401-407 "g2_z_ref=0.8" "g2_z_ref=0.86" "g2_z_ref=0.92" "g2_z_ref=1.0" 2>&1 | grep -a "^g2_z_ref"
for cfg in "j_st_w=0,j_st_zk=1.0,j_st_max=0.3,j_st_n=6" "j_st_w=0,j_st_zk=2.0,j_st_max=0.3,j_st_n=6" "j_st_w=0.3,j_st_zk=1.0,j_st_max=0.3,j_st_n=6"; do
  echo "== $cfg"
  .venv/bin/python scratchpad/lj2/ikgap.py long_jump_v4_p95_robust32 long_jump_v4_p95b $C scratchpad/lj2/A1ik.txt 8001-8064 "$cfg" 2 2>&1 | tail -2
done
echo DONE
