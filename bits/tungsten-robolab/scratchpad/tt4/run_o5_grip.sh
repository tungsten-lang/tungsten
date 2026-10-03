#!/bin/bash
# Stage 1, second half (scratchpad/tt4/PLANE_NOTE.md): T3's IDEAL pad-space arm servo (o5a of scratchpad/tt3/queue6.sh: computed-torque PD to the plan's pad centre and normal on the gentle plan bn0.1)
# with a FIRMER GRIP (tt_eval --set overrides on the champion), serves 98000-98099. o5_base must reproduce out/tt3/o5a_A.jsonl (identity check). A LABELLED DIAGNOSTIC ORACLE: never compared with the official trials.
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
mkdir -p out/tt4
run() { # TAG SET
  TAG=$1; SET=$2
  rm -f out/tt4/${TAG}_A.jsonl
  echo "$(date '+%F %T') $TAG start ($SET)" >> out/tt4/run_o5_grip.progress
  MYO_TT_ORACLE=o5 TT_TASK=myo_tt_oracle TT_ENV=P2 TT3_PLAN=scratchpad/tt3/results/plan_bn0.1.json TT3_CFG='{"o5_tact":0.30,"o5_tau":0.10,"o5_hold":0.03,"o5_wrot":0.30}' \
    TT_SAVE_LOG=out/tt4/logs_$TAG TT3_LOG=out/tt4/orc_$TAG nice -n 10 .venv-myo/bin/python playground/tt_eval.py --params params/myo_tt_p2_r10_c3.txt \
    --controller bin/challengers/myo_tt_r10-n --seeds 98000:98100 ${SET:+--set "$SET"} --out out/tt4/${TAG}_A.jsonl --workers 3 > out/tt4/${TAG}_A.summary 2> out/tt4/${TAG}_A.err
  echo "$(date '+%F %T') $TAG done" >> out/tt4/run_o5_grip.progress
}
run o5_base ""
run o5_gd15 "grip_drive=1.5"
run o5_gfull "grip_drive=0.8,g_fpl=0.6,g_idx=0.6,g_mid=0.6,g_ring=0.4,g_idx_int=0.6"
echo "$(date '+%F %T') ALL DONE" >> out/tt4/run_o5_grip.progress
