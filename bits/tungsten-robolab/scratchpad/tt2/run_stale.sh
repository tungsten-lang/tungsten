#!/bin/bash
# Post-verdict D2 (agent T2): the controller is told the OFFICIAL peak forces (stale MFORCE) on the beyond arm; LABELLED what-if.
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
for spec in "rung1 1 -" "s12 9 1.2,1.0,1.0"; do
  set -- $spec
  tag=$1; rung=$2; diag=$3
  echo "$(date '+%F %T') stale $tag start" >> out/tt2/run_stale.progress
  if [ "$diag" = "-" ]; then unset MYO_TT_BEYOND_DIAG; else export MYO_TT_BEYOND_DIAG=$diag; fi
  TT_ENV=P2 TT_TASK=myo_tt_beyond MYO_TT_BEYOND=$rung nice -n 10 .venv-myo/bin/python scratchpad/tt2/diag_stale.py --params params/myo_tt_p2_r10_c3.txt \
    --controller bin/challengers/myo_tt_r10-n --seeds 98000:98100 --out out/tt2/diag_stale_${tag}_98000.jsonl --workers 3 > out/tt2/diag_stale_${tag}_98000.summary 2> out/tt2/diag_stale_${tag}_98000.err
  echo "$(date '+%F %T') stale $tag done: $(tail -1 out/tt2/diag_stale_${tag}_98000.summary | head -c 300)" >> out/tt2/run_stale.progress
done
echo "$(date '+%F %T') ALL DONE" >> out/tt2/run_stale.progress
