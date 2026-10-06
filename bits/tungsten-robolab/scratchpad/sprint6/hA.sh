#!/bin/sh
# hA: intermediate-gear chains of F1 (gear half-way between gears 1 and 2) on the 1000 selection seeds, 30 s (paired against m1_F1_sel.jsonl)
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
until grep -q "Done scan mclassA" out/sprint6/scan_mclassA.log 2>/dev/null; do sleep 5; done
for T in H1 H2; do
  nice -n 10 .venv/bin/python scratchpad/sprint6/fr6.py scratchpad/sprint6/chains/F1$T.txt bin/challengers/run_gearz-s6h 24001-25000 out/sprint6/hA_$T.jsonl --workers 6 --tag "F1$T SELECTION" >> out/sprint6/hA.log 2>&1
done
echo "==> Done hA" >> out/sprint6/hA.log
