#!/bin/sh
# Backhand validation on independent pool serves (bh_val200 = pool bh[100:300]): champion, bk only, and RSM-derived candidates. 3 workers, sequential.
cd /Users/erik/tungsten/bits/tungsten-robolab
K=bin/challengers/myo_tt_r10-k; CH=bin/champions/tt_p2_300-20260927-194659; P=params/myo_tt_p2_r5_bhprac.txt
B="bk=1,kk=1,lc=1,lt_arms=0,kk_m2=-0.48"
scratchpad/tt/ev1.sh val_bh_champ $P $CH scratchpad/tt/bh_val200.txt "" 3
scratchpad/tt/ev1.sh val_bh_bk $P $K scratchpad/tt/bh_val200.txt "bk=1,lc=1,lt_arms=0" 3
scratchpad/tt/ev1.sh val_bh_c1 $P $K scratchpad/tt/bh_val200.txt "$B,kk_amp=1.0,kk_k=0.3,kk_v0=5.2,bh_gain=0.92,bh_p_n=0.3" 3
scratchpad/tt/ev1.sh val_bh_c2 $P $K scratchpad/tt/bh_val200.txt "$B,kk_amp=1.0,kk_k=0.3,kk_v0=5.2,bh_gain=0.88,bh_p_n=0.3" 3
.venv-myo/bin/python playground/tt_rsm_run_params.py --out out/tt_r10/rsm_bh3 --run 21 --write params/myo_tt_p2_r10_bh_run21.txt
scratchpad/tt/ev1.sh val_bh_run21 params/myo_tt_p2_r10_bh_run21.txt $K scratchpad/tt/bh_val200.txt "" 3
