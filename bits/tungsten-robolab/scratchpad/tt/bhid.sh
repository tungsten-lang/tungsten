#!/bin/sh
# Backhand posture Jacobian in the bk + kk regime: base + 8 posture parameters +0.06 rad, 60 backhand-pool serves each (3 workers).
cd /Users/erik/tungsten/bits/tungsten-robolab
C=bin/challengers/myo_tt_r10-k; P=params/myo_tt_p2_r5_bhprac.txt; S="bk=1,kk=1,lc=1,lt_arms=0,kk_m2=-0.48"
scratchpad/tt/ev1.sh bhid_b0 $P $C scratchpad/tt/bh60.txt "$S" 3
for kv in bh_elv:-1.2273290434866613 bh_sh_elv:0.743059065225087 bh_sh_rot:1.2820870687040262 bh_elbow:2.0102294955633875 bh_pro_sup:0.8873248649064687 bh_dev:-0.07325952553292492 bh_wflex:0.24613588296111355 bh_trunk_ar:0.41773193104793793; do
  k=${kv%%:*}; v=${kv##*:}
  nv=$(python3 -c "print(round($v+0.06,5))")
  scratchpad/tt/ev1.sh bhid_$k $P $C scratchpad/tt/bh60.txt "$S,$k=$nv" 3
done
