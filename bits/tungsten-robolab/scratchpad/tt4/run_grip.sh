#!/bin/bash
# Stage 1 of scratchpad/tt4/PLANE_NOTE.md: does a firmer grip stop the paddle swivelling in the hand? The CHAMPION (bin/challengers/myo_tt_r10-n, params/myo_tt_p2_r10_c3.txt)
# with grip overrides (--set, nothing else changed) on serves 98000-98099, per-episode logs for scratchpad/tt4/plane_probe.py (section 3, the in-hand swivel).
# Measures the swivel, NOT the score (the champion's other parameters were practised around its own grip). 3 workers, nice 10.
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
mkdir -p out/tt4
for v in "gd04|grip_drive=0.4" "gd08|grip_drive=0.8" "gd15|grip_drive=1.5" "gfull|grip_drive=0.8,g_fpl=0.6,g_idx=0.6,g_mid=0.6,g_ring=0.4,g_idx_int=0.6" "bhmax|bh_grip=0.4,bh_grip_drive=0.8"; do
  name=${v%%|*}; set=${v#*|}
  echo "$(date '+%F %T') grip_$name start ($set)" >> out/tt4/run_grip.progress
  TT_ENV=P2 TT_SAVE_LOG=out/tt4/logs_grip_$name nice -n 10 .venv-myo/bin/python playground/tt_eval.py --params params/myo_tt_p2_r10_c3.txt \
    --controller bin/challengers/myo_tt_r10-n --seeds 98000:98100 --set "$set" --out out/tt4/grip_$name.jsonl --workers 3 > out/tt4/grip_$name.summary 2> out/tt4/grip_$name.err
  echo "$(date '+%F %T') grip_$name done" >> out/tt4/run_grip.progress
done
echo "$(date '+%F %T') ALL DONE" >> out/tt4/run_grip.progress
