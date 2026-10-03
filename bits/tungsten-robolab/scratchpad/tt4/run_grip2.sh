#!/bin/bash
# Stage 1, second batch: how far can the swivel be pushed? Waits for run_grip.sh, then the champion with the finger flexors at and past their search bounds (grip_drive up to 2.0, the
# thumb and finger extensors lengthened so they do not fight), forehand and backhand grips. Same recipe and serves as run_grip.sh.
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
while ! grep -q "ALL DONE" out/tt4/run_grip.progress 2>/dev/null; do sleep 5; done
for v in "gmax|grip_drive=2.0,g_fpl=0.6,g_op=0.6,g_idx=0.6,g_mid=0.6,g_ring=0.6,g_idx_int=0.6,g_text=-0.5,g_fext=-0.5" "gmaxbh|grip_drive=2.0,g_fpl=0.6,g_op=0.6,g_idx=0.6,g_mid=0.6,g_ring=0.6,g_idx_int=0.6,g_text=-0.5,g_fext=-0.5,bh_grip=0.4,bh_grip_drive=0.8"; do
  name=${v%%|*}; set=${v#*|}
  echo "$(date '+%F %T') grip_$name start ($set)" >> out/tt4/run_grip.progress
  TT_ENV=P2 TT_SAVE_LOG=out/tt4/logs_grip_$name nice -n 10 .venv-myo/bin/python playground/tt_eval.py --params params/myo_tt_p2_r10_c3.txt \
    --controller bin/challengers/myo_tt_r10-n --seeds 98000:98100 --set "$set" --out out/tt4/grip_$name.jsonl --workers 3 > out/tt4/grip_$name.summary 2> out/tt4/grip_$name.err
  echo "$(date '+%F %T') grip_$name done" >> out/tt4/run_grip.progress
done
echo "$(date '+%F %T') ALL DONE 2" >> out/tt4/run_grip.progress
